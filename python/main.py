import os
from decimal import Decimal
import psycopg
from psycopg.errors import RaiseException


def get_connection():
    """Conecta ao PostgreSQL utilizando a variável de ambiente PG_DSN."""
    dsn = os.getenv(
        "PG_DSN",
        "host=localhost port=5432 dbname=hotel user=hotel password=hotel_lab_pwd",
    )
    return psycopg.connect(dsn)


def consultar_reservas(conn, status_filtro: str):
    """Requisito 1: SELECT parametrizado com bind (%s), sem f-string ou concatenação."""
    print(f"\n--- [1] Consultando reservas com status = '{status_filtro}' ---")
    sql = """
        SELECT r.id_reserva, h.nome_completo, q.numero_quarto, r.status_reserva, r.valor_total_bruto
        FROM Reserva r
        JOIN Hospede h ON h.id_hospede = r.id_hospede
        JOIN Quarto q ON q.id_quarto = r.id_quarto
        WHERE r.status_reserva = %s
        ORDER BY r.id_reserva
        LIMIT 5;
    """
    with conn.cursor() as cur:
        cur.execute(sql, (status_filtro,))
        linhas = cur.fetchall()
        if not linhas:
            print("Nenhuma reserva encontrada com esse status.")
        for linha in linhas:
            print(
                f"Reserva #{linha[0]} | Hóspede: {linha[1]} | Quarto: {linha[2]} | "
                f"Status: {linha[3]} | Valor Bruto: R$ {linha[4]}"
            )


def caminho_feliz_checkout(conn, valor_pago: Decimal):
    """Requisito 2: Chamada de procedure com decimal.Decimal em transação isolada (idempotente)."""
    print("\n--- [2] Executando Procedure fazer_checkout no Caminho Feliz (Transação Isolada) ---")
    try:
        with conn.cursor() as cur:
            # Insere uma reserva própria em CHECK-IN iniciada há 1 hora, em quarto livre no período
            cur.execute(
                """
                INSERT INTO Reserva (
                    id_hospede, id_quarto, data_entrada_prevista, data_saida_prevista,
                    data_checkin_real, status_reserva, valor_total_bruto, percentual_desconto
                )
                VALUES (
                    (SELECT MIN(id_hospede) FROM Hospede),
                    (
                        SELECT MIN(id_quarto)
                        FROM Quarto
                        WHERE status_quarto <> 'MANUTENCAO'
                          AND id_quarto NOT IN (
                              SELECT id_quarto
                              FROM Reserva
                              WHERE status_reserva IN ('PENDENTE', 'CONFIRMADA', 'CHECK-IN')
                                AND data_saida_prevista > CURRENT_DATE - 1
                                AND data_entrada_prevista < CURRENT_DATE + 2
                          )
                    ),
                    CURRENT_DATE,
                    CURRENT_DATE + 1,
                    CURRENT_TIMESTAMP - INTERVAL '1 hour',
                    'CHECK-IN',
                    %s,
                    0
                )
                RETURNING id_reserva;
                """,
                (valor_pago,),
            )
            id_reserva_demo = cur.fetchone()[0]

            # Valor monetário passado estritamente como decimal.Decimal (nunca float)
            cur.execute(
                "CALL fazer_checkout(%s, %s);",
                (id_reserva_demo, valor_pago),
            )

            # Verifica o resultado da procedure antes de reverter a transação de demonstração
            cur.execute(
                "SELECT status_reserva, valor_final_pago FROM Reserva WHERE id_reserva = %s;",
                (id_reserva_demo,),
            )
            status_atual, valor_final = cur.fetchone()
            print(
                f"Sucesso! Check-out da Reserva #{id_reserva_demo} validado "
                f"(status='{status_atual}', valor_final_pago=R$ {valor_final})."
            )
    except RaiseException as exc:
        msg = exc.diag.message_primary or str(exc)
        print(f"[Aviso de Negócio no Caminho Feliz]: {msg}")
    except Exception as exc:
        print(f"Erro inesperado no caminho feliz: {exc}")
    finally:
        # Reverte a demonstração e restaura a sequence para não sujar o banco para os testes
        conn.rollback()
        with conn.cursor() as cur:
            cur.execute(
                "SELECT setval(pg_get_serial_sequence('reserva', 'id_reserva'), COALESCE(MAX(id_reserva), 1)) FROM reserva;"
            )
        conn.commit()
        print("Estado do banco preservado (ROLLBACK da demonstração executado).")


def erro_negocio_checkout(conn, id_reserva: int, valor_pago: Decimal):
    """Requisito 3: Violação de regra de negócio capturada com RaiseException + rollback()."""
    print(f"\n--- [3] Testando Violação de Regra de Negócio (Reserva #{id_reserva} sem CHECK-IN) ---")
    try:
        with conn.cursor() as cur:
            cur.execute(
                "CALL fazer_checkout(%s, %s);",
                (id_reserva, valor_pago),
            )
        conn.commit()
    except RaiseException as exc:
        conn.rollback()
        msg = exc.diag.message_primary or str(exc)
        print(f"[Regra de Negócio Capturada]: {msg} -> Transação revertida (ROLLBACK).")
    except psycopg.Error as exc:
        conn.rollback()
        msg = exc.diag.message_primary or str(exc)
        print(f"[Erro de Banco Capturado]: {msg} -> Transação revertida (ROLLBACK).")


def main():
    print("Iniciando integração Python + PostgreSQL (Hotel Host)...")
    with get_connection() as conn:
        # 1. Consulta com bind (%s)
        consultar_reservas(conn, "CONFIRMADA")

        # 2. Procedure no caminho feliz usando decimal.Decimal e reserva isolada
        caminho_feliz_checkout(
            conn=conn,
            valor_pago=Decimal("200.00"),
        )

        # 3. Procedure violando regra de negócio -> captura RaiseException e faz conn.rollback()
        # (Reserva #11 está apenas CONFIRMADA, sem CHECK-IN)
        erro_negocio_checkout(
            conn=conn,
            id_reserva=11,
            valor_pago=Decimal("600.00"),
        )

    print("\nExecução concluída com segurança.")


if __name__ == "__main__":
    main()