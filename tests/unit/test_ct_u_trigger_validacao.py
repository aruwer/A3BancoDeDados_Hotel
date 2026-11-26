"""CT-U40 a CT-U43 (RN-03), CT-U80 a CT-U82 (RN-06) e CT-U94 a CT-U96 (RN-07) · trigger trg_reserva_validacao."""
from datetime import timedelta
from decimal import Decimal

import pytest

from helpers import codigo_negocio, erro_banco, hoje, nova_reserva, novo_hospede, um

# Dados de exemplo: quarto 4 = 201 (Superior, capacidade 3), 6 = 301 (Suíte, capacidade 4),
# 7 = 302 (Suíte, sem reservas), 2 = 102 (Standard), 3 = 103 (MANUTENCAO).
_INSERT = ("INSERT INTO reserva (id_hospede,id_quarto,numero_hospedes,data_entrada_prevista,data_saida_prevista,"
           "status_reserva,valor_total_bruto) VALUES (1,%s,%s,CURRENT_DATE+%s,CURRENT_DATE+%s,%s,600)")


def _reserva(conn, quarto=7, entrada=90, status="CONFIRMADA"):
    h = hoje(conn)
    return nova_reserva(conn, novo_hospede(conn), quarto, h + timedelta(days=entrada),
                        h + timedelta(days=entrada + 3), status, Decimal("600.00"))


# ------------------------------------------------------------------ RN-03: capacidade
@pytest.mark.parametrize("quarto,hospedes", [(6, 1), (6, 4), (4, 3)])
def test_ct_u40_hospedes_ate_a_capacidade_e_aceito(conn, quarto, hospedes):
    """When insiro uma reserva com 1 hóspede ou com exatamente a capacidade do quarto
    Then ela é aceita"""
    conn.execute(_INSERT, (quarto, hospedes, 80, 83, "CONFIRMADA"))


@pytest.mark.parametrize("quarto,hospedes", [(6, 5), (4, 4), (7, 99)])
def test_ct_u41_hospedes_acima_da_capacidade_e_recusado(conn, quarto, hospedes):
    """When insiro uma reserva com capacidade + 1 hóspedes
    Then o banco recusa com HOTEL-003"""
    assert codigo_negocio(conn, _INSERT, (quarto, hospedes, 80, 83, "CONFIRMADA"))[0] == "HOTEL-003"


@pytest.mark.parametrize("hospedes", [0, -1])
def test_ct_u42_zero_hospedes_e_recusado(conn, hospedes):
    """When insiro uma reserva com 0 (ou negativo) de hóspedes
    Then o banco recusa com HOTEL-003 (e a ck_reserva_hospedes barra o que o trigger deixasse passar)"""
    assert codigo_negocio(conn, _INSERT, (6, hospedes, 80, 83, "CONFIRMADA"))[0] == "HOTEL-003"


def test_ct_u42_constraint_ck_reserva_hospedes_existe(conn):
    """Given o DDL
    Then a constraint ck_reserva_hospedes (numero_hospedes > 0) existe e o padrão de uma reserva é 1 hóspede"""
    assert um(conn, "SELECT COUNT(*) FROM pg_constraint WHERE conname='ck_reserva_hospedes'")[0] == 1
    rid = _reserva(conn)
    assert um(conn, "SELECT numero_hospedes FROM reserva WHERE id_reserva=%s", (rid,))[0] == 1


def test_ct_u43_regra_vale_para_update_direto(conn):
    """Given uma reserva de 1 hóspede no quarto 6 (capacidade 4)
    When faço UPDATE direto para 5 hóspedes, ou troco para o quarto 2 (capacidade 2) com 3 hóspedes
    Then o banco recusa com HOTEL-003"""
    rid = _reserva(conn, quarto=6)
    assert codigo_negocio(conn, "UPDATE reserva SET numero_hospedes=5 WHERE id_reserva=%s", (rid,))[0] == "HOTEL-003"
    conn.execute("UPDATE reserva SET numero_hospedes=3 WHERE id_reserva=%s", (rid,))
    assert codigo_negocio(conn, "UPDATE reserva SET id_quarto=2 WHERE id_reserva=%s", (rid,))[0] == "HOTEL-003"


# ------------------------------------------------------------------ RN-06: quarto em manutenção
def test_ct_u80_reserva_em_quarto_de_manutencao_e_recusada(conn):
    """Given o quarto 103 em MANUTENCAO
    When insiro uma reserva ativa nele
    Then o banco recusa com HOTEL-004"""
    for status in ("PENDENTE", "CONFIRMADA", "CHECK-IN"):
        assert codigo_negocio(conn, _INSERT, (3, 1, 80, 83, status))[0] == "HOTEL-004"


def test_ct_u80_reserva_que_nao_segura_o_quarto_nao_e_barrada(conn):
    """Given o quarto 103 em MANUTENCAO
    When insiro reservas CANCELADA ou NO-SHOW (histórico, que não seguram o quarto)
    Then elas são aceitas: só reserva ativa depende do quarto"""
    for status in ("CANCELADA", "NO-SHOW"):
        conn.execute(_INSERT, (3, 1, 80, 83, status))


def test_ct_u81_reserva_em_quarto_disponivel_e_aceita(conn):
    """Given o quarto 102 DISPONIVEL e sem conflito
    When insiro uma reserva
    Then ela é aceita"""
    conn.execute(_INSERT, (2, 1, 80, 83, "CONFIRMADA"))


def test_ct_u81_quarto_ocupado_ou_em_limpeza_pode_ser_reservado_para_outra_data(conn):
    """Given o quarto 202 OCUPADO e o 101 em LIMPEZA
    When reservo datas futuras
    Then a reserva é aceita: a disponibilidade depende das datas, só MANUTENCAO bloqueia"""
    conn.execute(_INSERT, (5, 1, 80, 83, "CONFIRMADA"))
    conn.execute(_INSERT, (1, 1, 80, 83, "CONFIRMADA"))


def test_ct_u82_reserva_em_quarto_inexistente_e_recusada(conn):
    """When insiro uma reserva num quarto que não existe
    Then o banco recusa (fk_reserva_quarto)"""
    estado, constraint = erro_banco(conn, _INSERT, (9999, 1, 80, 83, "CONFIRMADA"))
    assert (estado, constraint) == ("23503", "fk_reserva_quarto")


def test_ct_u80_update_que_leva_reserva_para_quarto_em_manutencao_e_recusado(conn):
    """Given uma reserva ativa no quarto 7
    When faço UPDATE direto trocando para o quarto 103 (MANUTENCAO)
    Then o banco recusa com HOTEL-004"""
    rid = _reserva(conn)
    assert codigo_negocio(conn, "UPDATE reserva SET id_quarto=3 WHERE id_reserva=%s", (rid,))[0] == "HOTEL-004"


def test_ct_u80_quarto_que_entra_em_manutencao_nao_impede_o_checkout(conn):
    """Given uma reserva em CHECK-IN cujo quarto entrou em MANUTENCAO com o hóspede ainda lá
    When a reserva vai para CHECK-OUT por UPDATE
    Then o UPDATE é aceito (a regra vale para reserva nova, não para quem já está hospedado)"""
    rid = _reserva(conn, status="CHECK-IN")
    conn.execute("UPDATE quarto SET status_quarto='MANUTENCAO' WHERE id_quarto=7")
    conn.execute("UPDATE reserva SET status_reserva='CHECK-OUT' WHERE id_reserva=%s", (rid,))


# ------------------------------------------------------------------ RN-07: máquina de estados
@pytest.mark.parametrize("de,para", [
    ("PENDENTE", "CONFIRMADA"), ("PENDENTE", "CANCELADA"), ("PENDENTE", "NO-SHOW"),
    ("CONFIRMADA", "CHECK-IN"), ("CONFIRMADA", "CANCELADA"), ("CONFIRMADA", "NO-SHOW"),
    ("CHECK-IN", "CHECK-OUT"),
])
def test_ct_u90_transicoes_validas_sao_aceitas(conn, de, para):
    """Given uma reserva no status de origem
    When faço UPDATE direto para o status de destino previsto na sequência
    Then o UPDATE é aceito"""
    rid = _reserva(conn, status=de)
    conn.execute("UPDATE reserva SET status_reserva=%s WHERE id_reserva=%s", (para, rid))
    assert um(conn, "SELECT status_reserva FROM reserva WHERE id_reserva=%s", (rid,))[0] == para


@pytest.mark.parametrize("de,para", [
    ("CHECK-OUT", "CONFIRMADA"),   # CT-U94
    ("CANCELADA", "CHECK-IN"),     # CT-U95
    ("NO-SHOW", "CONFIRMADA"),     # CT-U96
    ("CHECK-OUT", "CHECK-IN"), ("CHECK-OUT", "CANCELADA"), ("CANCELADA", "CONFIRMADA"),
    ("CONFIRMADA", "CHECK-OUT"), ("CONFIRMADA", "PENDENTE"), ("PENDENTE", "CHECK-IN"),
    ("CHECK-IN", "CANCELADA"), ("CHECK-IN", "CONFIRMADA"), ("CHECK-IN", "NO-SHOW"),
])
def test_ct_u94_a_u96_transicoes_invalidas_sao_recusadas(conn, de, para):
    """Given uma reserva num status
    When faço UPDATE direto para um status fora da sequência
    Then o banco recusa com HOTEL-007 e o status não muda"""
    rid = _reserva(conn, status=de)
    assert codigo_negocio(conn, "UPDATE reserva SET status_reserva=%s WHERE id_reserva=%s", (para, rid))[0] == "HOTEL-007"
    assert um(conn, "SELECT status_reserva FROM reserva WHERE id_reserva=%s", (rid,))[0] == de


def test_ct_u96_repetir_o_mesmo_status_nao_e_transicao(conn):
    """Given uma reserva CHECK-OUT
    When faço UPDATE de outra coluna mantendo o status
    Then o UPDATE é aceito"""
    rid = _reserva(conn, status="CHECK-OUT")
    conn.execute("UPDATE reserva SET status_reserva='CHECK-OUT', valor_final_pago=1 WHERE id_reserva=%s", (rid,))


def test_ct_u96_procedures_continuam_funcionando_com_o_trigger(conn):
    """Given os dados de exemplo
    When cancelo a reserva 18 (PENDENTE) com a procedure cancelar_reserva
    Then a procedure passa pelo trigger sem erro e a reserva vira CANCELADA
    (o check-out por procedure é coberto em test_ct_u_fazer_checkout.py, que também passa pelo trigger)"""
    conn.execute("CALL cancelar_reserva(18)")
    assert um(conn, "SELECT status_reserva FROM reserva WHERE id_reserva=18")[0] == "CANCELADA"
