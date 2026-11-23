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


def caminho_feliz_checkout(conn, id_reserva: int, valor_pago: Decimal):
    """Requisito 2: Chamada de procedure com decimal.Decimal e confirmação via commit()."""
    print(f"\n--- [2] Executando Procedure fazer_checkout (Reserva #{id_reserva}) no Caminho Feliz ---")
    try:
        with conn.cursor() as cur:
            # Valor monetário passado estritamente como decimal.Decimal (nunca float)
            cur.execute(
                "CALL fazer_checkout(%s, %s);",
                (id_reserva, valor_pago),
            )
        conn.commit()
        print(
            f"Sucesso! Check-out da Reserva #{id_reserva} concluído com pagamento de "
            f"R$ {valor_pago} -> Transação confirmada (COMMIT)."
        )
    except RaiseException as exc:
        conn.rollback()
        msg = exc.diag.message_primary or str(exc)
        print(f"[Aviso de Negócio no Caminho Feliz]: {msg} -> ROLLBACK executado.")
    except Exception as exc:
        conn.rollback()
        print(f"Erro inesperado no caminho feliz: {exc}")


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

        # 2. Procedure no caminho feliz usando decimal.Decimal e conn.commit()
        # (Reserva #10 está com status CHECK-IN e valor bruto 1200.00)
        caminho_feliz_checkout(
            conn=conn,
            id_reserva=10,
            valor_pago=Decimal("1200.00"),
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
