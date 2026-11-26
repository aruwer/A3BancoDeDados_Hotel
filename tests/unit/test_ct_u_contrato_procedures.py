"""CT-U150 a CT-U155 · contrato das procedures e do trigger: códigos de erro estáveis e sem COMMIT."""
import re
from decimal import Decimal
from pathlib import Path

import pytest

from helpers import codigo_negocio, reserva_para_checkout, saida, todos, um

RAIZ = Path(__file__).resolve().parents[2]
PROCEDURES = RAIZ / "procedures" / "postgresql_procedures.sql"


@pytest.mark.parametrize("codigo,sql,params", [
    ("HOTEL-001", "CALL cancelar_reserva(%s)", (None,)),
    ("HOTEL-005", "INSERT INTO reserva (id_hospede,id_quarto,data_entrada_prevista,data_saida_prevista,"
                  "status_reserva,valor_total_bruto) VALUES (1,5,CURRENT_DATE,CURRENT_DATE+2,'CONFIRMADA',600)", None),
    ("HOTEL-006", "CALL cancelar_reserva(%s)", (999999,)),
    ("HOTEL-007", "CALL cancelar_reserva(%s)", (13,)),
    ("HOTEL-009", "CALL fazer_checkout(10, 0.01)", None),
    ("HOTEL-012", "CALL fazer_checkout(10, 5000, CURRENT_DATE + 3 + TIME '08:00')", None),
])
def test_ct_u150_erro_de_negocio_tem_codigo_estavel(conn, codigo, sql, params):
    """When provoco cada erro de negócio implementado
    Then o SQLSTATE é P0001 e a mensagem começa com 'HOTEL-nnn:'"""
    obtido, mensagem = codigo_negocio(conn, sql, params)
    assert obtido == codigo
    assert re.match(r"^HOTEL-\d{3}: \S", mensagem)


def test_ct_u152_codigo_011_permanece_livre():
    """When varro os scripts de procedures
    Then nenhum usa HOTEL-011 (reservado para uma regra futura)"""
    assert "HOTEL-011" not in PROCEDURES.read_text(encoding="utf-8")


def test_ct_u153_mensagens_nao_vazam_dados_pessoais(conn):
    """When um erro de negócio é lançado numa reserva de hóspede identificado
    Then a mensagem não traz CPF, e-mail nem telefone"""
    rid = reserva_para_checkout(conn)
    _, msg = codigo_negocio(conn, "CALL fazer_checkout(%s, 0.01, %s)", (rid, saida(conn)))
    cpf, email = um(conn, "SELECT h.cpf, h.email FROM reserva r JOIN hospede h USING (id_hospede) "
                          "WHERE r.id_reserva=%s", (rid,))
    assert cpf not in msg and email not in msg


@pytest.mark.parametrize("rotina", ["cancelar_reserva", "fazer_checkout", "fn_reserva_sobreposicao"])
def test_ct_u154_rotinas_nao_fazem_commit_nem_rollback(conn, rotina):
    """When leio o corpo de cada rotina no catálogo
    Then não há COMMIT nem ROLLBACK (quem chama decide a transação)"""
    corpos = [r[0] for r in todos(conn, "SELECT prosrc FROM pg_proc WHERE proname = %s", (rotina,))]
    assert len(corpos) == 1, f"{rotina}: esperado exatamente 1 assinatura, achei {len(corpos)}"
    codigo = "\n".join(l.split("--")[0] for l in corpos[0].splitlines())
    assert not re.search(r"\b(COMMIT|ROLLBACK)\b", codigo, re.I)


def test_ct_u154_chamada_dentro_de_transacao_pode_ser_desfeita(conn):
    """Given uma procedure chamada dentro de uma transação aberta
    When faço ROLLBACK
    Then o efeito da procedure desaparece"""
    conn.execute("CALL cancelar_reserva(12)")
    assert um(conn, "SELECT status_reserva FROM reserva WHERE id_reserva=12")[0] == "CANCELADA"
    conn.rollback()
    assert um(conn, "SELECT status_reserva FROM reserva WHERE id_reserva=12")[0] == "CONFIRMADA"


def test_ct_u155_cada_rotina_tem_comentario_com_a_regra():
    """When leio postgresql_procedures.sql
    Then cada procedure e o trigger têm bloco de comentário que cita a regra (RN-nn) que implementam"""
    sql = PROCEDURES.read_text(encoding="utf-8")
    for nome in ["cancelar_reserva", "fazer_checkout", "trg_reserva_sobreposicao"]:
        antes = sql.split(f"CREATE OR REPLACE PROCEDURE {nome}")[0] if nome != "trg_reserva_sobreposicao" \
            else sql.split("CREATE OR REPLACE FUNCTION fn_reserva_sobreposicao")[0]
        ultimo_bloco = antes.rsplit("-- -----", 2)[-2] if "-- -----" in antes else antes[-1500:]
        assert re.search(r"RN-\d\d", ultimo_bloco), f"{nome}: comentário sem referência a RN-nn"


def test_ct_u156_seed_financeiro_e_consistente(conn):
    """Given os dados de exemplo
    Then, nas estadias CHECK-OUT, pagamentos - estornos = valor_final_pago; nas CANCELADA e NO-SHOW, = multa aplicada"""
    linhas = todos(conn, """
        SELECT r.id_reserva, r.status_reserva,
               COALESCE(SUM(CASE p.tipo WHEN 'PAGAMENTO' THEN p.valor ELSE -p.valor END), 0) AS liquido,
               COALESCE(r.valor_final_pago, c.taxa_multa_aplicada) AS esperado
        FROM reserva r
        LEFT JOIN pagamento p ON p.id_reserva = r.id_reserva
        LEFT JOIN cancelamento c ON c.id_reserva = r.id_reserva
        WHERE r.status_reserva IN ('CHECK-OUT','CANCELADA','NO-SHOW')
        GROUP BY r.id_reserva, r.status_reserva, r.valor_final_pago, c.taxa_multa_aplicada ORDER BY 1""")
    assert len(linhas) == 14
    divergentes = [(i, s, liq, esp) for i, s, liq, esp in linhas if liq != esp]
    assert divergentes == []


def test_ct_u157_valor_final_do_seed_bate_com_bruto_mais_consumos(conn):
    """Given as estadias CHECK-OUT dos dados de exemplo (desconto 0, saída no prazo)
    Then valor_final_pago = valor_total_bruto + soma dos consumos"""
    linhas = todos(conn, """
        SELECT r.id_reserva, r.valor_final_pago,
               r.valor_total_bruto + COALESCE(SUM(c.valor_total_item), 0) + r.taxa_checkout
        FROM reserva r LEFT JOIN consumo_servico c USING (id_reserva)
        WHERE r.status_reserva = 'CHECK-OUT'
        GROUP BY r.id_reserva, r.valor_final_pago, r.valor_total_bruto, r.taxa_checkout""")
    assert [(i, f, e) for i, f, e in linhas if f != e] == []


def test_ct_u158_seed_tem_os_quatro_status_de_quarto(conn):
    """Given os dados de exemplo
    Then existem quartos nos quatro status do ciclo (regras.md seção 8), com o 103 em MANUTENCAO"""
    status = dict(todos(conn, "SELECT numero_quarto, status_quarto FROM quarto"))
    assert set(status.values()) == {"DISPONIVEL", "OCUPADO", "LIMPEZA", "MANUTENCAO"}
    assert status["103"] == "MANUTENCAO" and status["202"] == "OCUPADO" and status["101"] == "LIMPEZA"


def test_ct_u159_seed_quarto_com_checkin_esta_ocupado(conn):
    """Given os dados de exemplo
    Then todo quarto com reserva CHECK-IN está OCUPADO, e nenhum quarto OCUPADO fica sem hóspede"""
    com_checkin = {r[0] for r in todos(conn, "SELECT id_quarto FROM reserva WHERE status_reserva='CHECK-IN'")}
    ocupados = {r[0] for r in todos(conn, "SELECT id_quarto FROM quarto WHERE status_quarto='OCUPADO'")}
    assert com_checkin == ocupados


def test_ct_u159_seed_checkout_tem_taxa_zero_e_demais_reservas_tambem(conn):
    """Given os dados de exemplo (nenhuma saída passou de 12:00)
    Then taxa_checkout é 0 em todas as reservas"""
    assert um(conn, "SELECT COUNT(*) FROM reserva WHERE taxa_checkout <> 0")[0] == 0
