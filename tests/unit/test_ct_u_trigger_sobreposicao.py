"""CT-U30 a CT-U37 · RN-02: um quarto não pode ter duas reservas ativas sobrepostas (trg_reserva_sobreposicao)."""
from datetime import timedelta
from decimal import Decimal

import pytest

from helpers import codigo_negocio, hoje, nova_reserva, novo_hospede, um

QUARTO = 7  # quarto 302: sem reservas nos dados de exemplo


def _reserva(conn, entrada, saida, status="CONFIRMADA", quarto=QUARTO):
    h = hoje(conn)
    return nova_reserva(conn, novo_hospede(conn), quarto, h + timedelta(days=entrada),
                        h + timedelta(days=saida), status, Decimal("600.00"))


def test_ct_u30_sobreposicao_de_uma_noite_e_recusada(conn):
    """Given o quarto 302 tem reserva CONFIRMADA de D+10 a D+13
    When insiro direto uma reserva CONFIRMADA de D+12 a D+14 no mesmo quarto
    Then o banco recusa com HOTEL-005"""
    _reserva(conn, 10, 13)
    codigo, _ = codigo_negocio(
        conn, "INSERT INTO reserva (id_hospede,id_quarto,data_entrada_prevista,data_saida_prevista,"
              "status_reserva,valor_total_bruto) VALUES (1,%s,CURRENT_DATE+12,CURRENT_DATE+14,'CONFIRMADA',600)",
        (QUARTO,))
    assert codigo == "HOTEL-005"


def test_ct_u31_saida_e_entrada_no_mesmo_dia_sao_aceitas(conn):
    """Given o quarto 302 tem reserva CONFIRMADA de D+10 a D+13
    When insiro reservas de D+13 a D+15 e de D+8 a D+10
    Then ambas são aceitas (intervalo semiaberto [entrada, saída))"""
    _reserva(conn, 10, 13)
    assert _reserva(conn, 13, 15) > 0
    assert _reserva(conn, 8, 10) > 0


@pytest.mark.parametrize("entrada,saida,conflita", [
    (11, 13, True),    # dentro
    (8, 18, True),     # engloba
    (8, 11, True),     # pega o início
    (14, 18, True),    # pega o fim
    (10, 15, True),    # idêntica
    (15, 17, False),   # começa na saída da outra
    (7, 10, False),    # termina na entrada da outra
])
def test_ct_u32_formas_de_sobreposicao(conn, entrada, saida, conflita):
    """Given o quarto 302 tem reserva ativa de D+10 a D+15
    When insiro reserva em cada forma de sobreposição
    Then só as que invadem o período são recusadas com HOTEL-005"""
    _reserva(conn, 10, 15)
    sql = ("INSERT INTO reserva (id_hospede,id_quarto,data_entrada_prevista,data_saida_prevista,"
           "status_reserva,valor_total_bruto) VALUES (1,%s,CURRENT_DATE+%s,CURRENT_DATE+%s,'CONFIRMADA',600)")
    if conflita:
        assert codigo_negocio(conn, sql, (QUARTO, entrada, saida))[0] == "HOTEL-005"
    else:
        conn.execute(sql, (QUARTO, entrada, saida))


@pytest.mark.parametrize("status", ["CANCELADA", "NO-SHOW", "CHECK-OUT"])
def test_ct_u33_reserva_nao_ativa_nao_bloqueia(conn, status):
    """Given o quarto 302 tem reserva CANCELADA, NO-SHOW ou CHECK-OUT de D+10 a D+13
    When insiro reserva CONFIRMADA no mesmo quarto e período
    Then a reserva é aceita"""
    _reserva(conn, 10, 13, status)
    assert _reserva(conn, 10, 13) > 0


@pytest.mark.parametrize("status", ["PENDENTE", "CONFIRMADA", "CHECK-IN"])
def test_ct_u34_reserva_ativa_bloqueia(conn, status):
    """Given o quarto 302 tem reserva PENDENTE, CONFIRMADA ou CHECK-IN de D+10 a D+13
    When insiro reserva CONFIRMADA no mesmo quarto e período
    Then o banco recusa com HOTEL-005"""
    _reserva(conn, 10, 13, status)
    codigo, _ = codigo_negocio(
        conn, "INSERT INTO reserva (id_hospede,id_quarto,data_entrada_prevista,data_saida_prevista,"
              "status_reserva,valor_total_bruto) VALUES (1,%s,CURRENT_DATE+10,CURRENT_DATE+13,'CONFIRMADA',600)",
        (QUARTO,))
    assert codigo == "HOTEL-005"


def test_ct_u35_quartos_diferentes_nao_conflitam(conn):
    """When insiro duas reservas ativas no mesmo período em quartos diferentes
    Then ambas são aceitas"""
    assert _reserva(conn, 10, 13, quarto=6) > 0
    assert _reserva(conn, 10, 13, quarto=7) > 0


@pytest.mark.parametrize("alteracao", ["datas", "quarto", "reativar"])
def test_ct_u36_update_que_cria_conflito_e_recusado(conn, alteracao):
    """Given duas reservas ativas no quarto 302, sem sobreposição
    When faço UPDATE direto que cria conflito (datas, quarto ou reativação de CANCELADA)
    Then o banco recusa com HOTEL-005"""
    primeira = _reserva(conn, 10, 13)
    if alteracao == "datas":
        segunda = _reserva(conn, 20, 23)
        sql, params = ("UPDATE reserva SET data_entrada_prevista=CURRENT_DATE+11, data_saida_prevista=CURRENT_DATE+14 "
                       "WHERE id_reserva=%s", (segunda,))
    elif alteracao == "quarto":
        segunda = _reserva(conn, 10, 13, quarto=6)
        sql, params = "UPDATE reserva SET id_quarto=%s WHERE id_reserva=%s", (QUARTO, segunda)
    else:
        segunda = _reserva(conn, 10, 13, "CANCELADA")
        sql, params = "UPDATE reserva SET status_reserva='CONFIRMADA' WHERE id_reserva=%s", (segunda,)
    assert primeira != segunda
    assert codigo_negocio(conn, sql, params)[0] == "HOTEL-005"


def test_ct_u37_update_inofensivo_nao_conflita_consigo_mesma(conn):
    """Given uma reserva ativa
    When atualizo colunas sem relação com a regra (valor_final_pago, check-in real)
    Then o UPDATE é aceito e a própria linha não conta como conflito"""
    rid = _reserva(conn, 10, 13)
    conn.execute("UPDATE reserva SET valor_final_pago = 1 WHERE id_reserva = %s", (rid,))
    conn.execute("UPDATE reserva SET data_checkin_real = CURRENT_TIMESTAMP WHERE id_reserva = %s", (rid,))
    assert um(conn, "SELECT valor_final_pago FROM reserva WHERE id_reserva=%s", (rid,))[0] == Decimal("1.00")


def test_ct_u31_mensagem_identifica_a_reserva_em_conflito(conn):
    """Given o quarto 302 tem uma reserva ativa
    When outra a sobrepõe
    Then a mensagem de erro cita o quarto e o id da reserva em conflito (o recepcionista sabe o que corrigir)"""
    existente = _reserva(conn, 10, 13)
    _, msg = codigo_negocio(
        conn, "INSERT INTO reserva (id_hospede,id_quarto,data_entrada_prevista,data_saida_prevista,"
              "status_reserva,valor_total_bruto) VALUES (1,%s,CURRENT_DATE+11,CURRENT_DATE+12,'CONFIRMADA',600)",
        (QUARTO,))
    assert str(existente) in msg and str(QUARTO) in msg
