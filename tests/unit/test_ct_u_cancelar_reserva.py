"""CT-U50 a CT-U60 · RN-04: cancelamento e multa por faixa de antecedência (procedure cancelar_reserva)."""
from datetime import timedelta
from decimal import Decimal

import pytest

from helpers import codigo_negocio, hoje, reserva, reserva_confirmada_futura, todos, um


def _cancelar(conn, rid, entrada, dias_ate_entrada, motivo=None):
    """Chama cancelar_reserva simulando que hoje = entrada - dias."""
    conn.execute("CALL cancelar_reserva(%s, %s, %s)", (rid, entrada - timedelta(days=dias_ate_entrada), motivo))


def _multa(conn, rid):
    linhas = todos(conn, "SELECT taxa_multa_aplicada FROM cancelamento WHERE id_reserva=%s", (rid,))
    return [l[0] for l in linhas]


@pytest.mark.parametrize("dias,status,multa", [
    (30, "CANCELADA", "0.00"),
    (8, "CANCELADA", "0.00"),
    (7, "CANCELADA", "0.00"),
    (6, "CANCELADA", "100.00"),
    (2, "CANCELADA", "100.00"),
    (1, "CANCELADA", "200.00"),
    (0, "CANCELADA", "200.00"),
    (-1, "NO-SHOW", "200.00"),
    (-30, "NO-SHOW", "200.00"),
])
def test_ct_u50_multa_por_faixa_de_antecedencia(conn, dias, status, multa):
    """Given uma reserva CONFIRMADA de 3 noites, bruto R$ 600,00 (D = R$ 200,00)
    When cancelar_reserva é chamada com N dias até a entrada
    Then o status final e a multa seguem a tabela 4.1 do regras.md"""
    rid, entrada = reserva_confirmada_futura(conn)
    _cancelar(conn, rid, entrada, dias)
    assert reserva(conn, rid)["status_reserva"] == status
    assert _multa(conn, rid) == [Decimal(multa)]


def test_ct_u51_multa_usa_a_diaria_da_reserva(conn):
    """Given a reserva 12 (3 noites, bruto R$ 900,00, D = R$ 300,00) a 5 dias da entrada
    When cancelo a reserva
    Then a multa é R$ 150,00 (50% de 300)"""
    conn.execute("CALL cancelar_reserva(12)")
    assert _multa(conn, 12) == [Decimal("150.00")]
    assert reserva(conn, 12)["status_reserva"] == "CANCELADA"


def test_ct_u52_multa_e_arredondada_a_2_casas(conn):
    """Given uma reserva de 3 noites com bruto R$ 100,00 (D = 33,333...)
    When cancelo com 1 dia e com 3 dias de antecedência
    Then a multa é R$ 33,33 e R$ 16,67"""
    rid, entrada = reserva_confirmada_futura(conn, bruto=Decimal("100.00"))
    _cancelar(conn, rid, entrada, 1)
    assert _multa(conn, rid) == [Decimal("33.33")]
    rid2, entrada2 = reserva_confirmada_futura(conn, bruto=Decimal("100.00"), quarto=6)
    _cancelar(conn, rid2, entrada2, 3)
    assert _multa(conn, rid2) == [Decimal("16.67")]


def test_ct_u53_reserva_pendente_tambem_cancela(conn):
    """Given a reserva 18 (PENDENTE, entrada em D+20)
    When cancelo a reserva
    Then ela vira CANCELADA sem multa"""
    conn.execute("CALL cancelar_reserva(18)")
    assert reserva(conn, 18)["status_reserva"] == "CANCELADA"
    assert _multa(conn, 18) == [Decimal("0.00")]


@pytest.mark.parametrize("rid,status", [(10, "CHECK-IN"), (1, "CHECK-OUT"), (13, "CANCELADA"), (17, "NO-SHOW")])
def test_ct_u54_so_pendente_e_confirmada_cancelam(conn, rid, status):
    """Given uma reserva em CHECK-IN, CHECK-OUT, CANCELADA ou NO-SHOW
    When cancelar_reserva é chamada
    Then o banco recusa com HOTEL-007 e o status não muda"""
    antes = reserva(conn, rid)["status_reserva"]
    assert antes == status
    assert codigo_negocio(conn, "CALL cancelar_reserva(%s)", (rid,))[0] == "HOTEL-007"
    assert reserva(conn, rid)["status_reserva"] == status


def test_ct_u55_cancelar_duas_vezes_nao_duplica_a_multa(conn):
    """Given a reserva 12 foi cancelada
    When cancelar_reserva é chamada de novo
    Then recusa com HOTEL-007 e continua existindo uma única multa"""
    conn.execute("CALL cancelar_reserva(12)")
    assert codigo_negocio(conn, "CALL cancelar_reserva(12)")[0] == "HOTEL-007"
    assert len(_multa(conn, 12)) == 1


@pytest.mark.parametrize("chamada,params,codigo", [
    ("CALL cancelar_reserva(%s)", (None,), "HOTEL-001"),
    ("CALL cancelar_reserva(%s)", (999999,), "HOTEL-006"),
])
def test_ct_u56_parametros_invalidos(conn, chamada, params, codigo):
    """When chamo cancelar_reserva com id nulo ou inexistente
    Then o erro de negócio é HOTEL-001 ou HOTEL-006"""
    assert codigo_negocio(conn, chamada, params)[0] == codigo


def test_ct_u57_cancelamento_altera_duas_tabelas(conn):
    """When cancelo a reserva 12
    Then reserva muda para CANCELADA e cancelamento recebe uma linha com multa e motivo"""
    antes = um(conn, "SELECT count(*) FROM cancelamento")[0]
    conn.execute("CALL cancelar_reserva(12)")
    assert um(conn, "SELECT count(*) FROM cancelamento")[0] == antes + 1
    motivo = um(conn, "SELECT motivo_cancelamento FROM cancelamento WHERE id_reserva=12")[0]
    assert motivo and len(motivo) > 10


@pytest.mark.parametrize("dias,trecho", [(8, "sem multa"), (4, "50%"), (1, "100%"), (-1, "No-show")])
def test_ct_u58_motivo_padrao_descreve_a_faixa(conn, dias, trecho):
    """When cancelo sem informar p_motivo
    Then o motivo gravado descreve a faixa aplicada"""
    rid, entrada = reserva_confirmada_futura(conn)
    _cancelar(conn, rid, entrada, dias)
    motivo = um(conn, "SELECT motivo_cancelamento FROM cancelamento WHERE id_reserva=%s", (rid,))[0]
    assert trecho in motivo


def test_ct_u59_motivo_informado_prevalece(conn):
    """When informo p_motivo
    Then ele é gravado exatamente como veio"""
    rid, entrada = reserva_confirmada_futura(conn)
    _cancelar(conn, rid, entrada, 10, motivo="Hóspede doente")
    assert um(conn, "SELECT motivo_cancelamento FROM cancelamento WHERE id_reserva=%s", (rid,))[0] == "Hóspede doente"


def test_ct_u60_reserva_cancelada_libera_o_quarto(conn):
    """Given a reserva 12 (quarto 4, D+5 a D+8) foi cancelada
    When insiro nova reserva ativa no mesmo quarto e período
    Then a reserva é aceita (e antes do cancelamento seria recusada com HOTEL-005)"""
    sql = ("INSERT INTO reserva (id_hospede,id_quarto,data_entrada_prevista,data_saida_prevista,"
           "status_reserva,valor_total_bruto) VALUES (1,4,CURRENT_DATE+5,CURRENT_DATE+8,'CONFIRMADA',900)")
    assert codigo_negocio(conn, sql)[0] == "HOTEL-005"
    conn.execute("CALL cancelar_reserva(12)")
    conn.execute(sql)


def test_ct_u50_data_padrao_e_hoje_do_banco(conn):
    """Given a reserva 12 com entrada em D+5
    When chamo cancelar_reserva sem p_hoje
    Then a faixa usa CURRENT_DATE (5 dias: 50% da diária de R$ 300,00)"""
    assert (um(conn, "SELECT data_entrada_prevista - CURRENT_DATE FROM reserva WHERE id_reserva=12")[0]) == 5
    conn.execute("CALL cancelar_reserva(12)")
    assert _multa(conn, 12) == [Decimal("150.00")]
