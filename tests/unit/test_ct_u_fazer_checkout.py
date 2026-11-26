"""CT-U70 a CT-U115 · RN-05 (fidelidade), RN-08 (late check-out) e RN-09 (pagamento) da procedure fazer_checkout.

CT-U107 (quarto em LIMPEZA, D-02) e CT-U108 (taxa_checkout gravada) também ficam aqui."""
from datetime import timedelta
from decimal import Decimal

import pytest

from helpers import (codigo_negocio, fazer_checkout, hoje, nova_reserva, novo_hospede, reserva,
                     reserva_para_checkout, saida, todos, um)

GRANDE = Decimal("5000.00")  # valor entregue sempre maior que o saldo (o troco não é lançado)


def _pagamentos(conn, rid):
    return todos(conn, "SELECT tipo, forma, valor FROM pagamento WHERE id_reserva=%s ORDER BY id_pagamento", (rid,))


def _consumo(conn, rid, valor):
    conn.execute("INSERT INTO consumo_servico (id_reserva,id_servico,quantidade,valor_total_item) VALUES (%s,1,1,%s)",
                 (rid, valor))


# ------------------------------------------------------------------ RN-05 fidelidade
@pytest.mark.parametrize("anteriores,desconto,final", [
    (0, 0, "600.00"), (4, 0, "600.00"), (5, 5, "570.00"), (9, 5, "570.00"), (10, 10, "540.00"), (25, 10, "540.00"),
])
def test_ct_u70_percentual_de_fidelidade_por_historico(conn, anteriores, desconto, final):
    """Given um hóspede com N estadias CHECK-OUT anteriores e uma reserva de bruto R$ 600,00
    When o check-out é feito às 11:00 do dia previsto
    Then o desconto é 0%, 5% ou 10% conforme a RN-05 e o valor final é calculado sobre as diárias"""
    rid = reserva_para_checkout(conn, estadias_anteriores=anteriores)
    fazer_checkout(conn, rid, GRANDE, saida(conn))
    r = reserva(conn, rid)
    assert r["percentual_desconto"] == Decimal(desconto)
    assert r["valor_final_pago"] == Decimal(final)


def test_ct_u71_reserva_em_checkout_nao_conta_como_estadia_anterior(conn):
    """Given um hóspede com 4 estadias concluídas e a reserva atual é a quinta
    When o check-out é feito
    Then o desconto é 0% (a atual ainda não conta)"""
    rid = reserva_para_checkout(conn, estadias_anteriores=4)
    fazer_checkout(conn, rid, GRANDE, saida(conn))
    assert reserva(conn, rid)["percentual_desconto"] == 0


def test_ct_u72_so_checkout_conta_para_fidelidade(conn):
    """Given um hóspede com 9 reservas CANCELADA/NO-SHOW e 3 CHECK-OUT
    When o check-out é feito
    Then o desconto é 0%"""
    rid = reserva_para_checkout(conn, estadias_anteriores=3)
    hospede = reserva(conn, rid)["id_hospede"]
    h = hoje(conn)
    for i in range(9):
        entrada = h - timedelta(days=2000 + 5 * i)
        nova_reserva(conn, hospede, 7, entrada, entrada + timedelta(days=1),
                     "CANCELADA" if i % 2 else "NO-SHOW", Decimal("100.00"))
    fazer_checkout(conn, rid, GRANDE, saida(conn))
    assert reserva(conn, rid)["percentual_desconto"] == 0


def test_ct_u73_desconto_incide_so_sobre_as_diarias(conn):
    """Given 5 estadias anteriores (5%) e um consumo de R$ 100,00
    When o check-out é feito dentro do prazo
    Then valor final = 600 x 0,95 + 100 = R$ 670,00"""
    rid = reserva_para_checkout(conn, estadias_anteriores=5)
    _consumo(conn, rid, Decimal("100.00"))
    fazer_checkout(conn, rid, GRANDE, saida(conn))
    assert reserva(conn, rid)["valor_final_pago"] == Decimal("670.00")


def test_ct_u74_taxa_de_late_checkout_usa_a_diaria_cheia(conn):
    """Given 10 estadias anteriores (10%)
    When o check-out é às 12:00:01
    Then valor final = 540,00 + 100,00 (50% da diária cheia de 200) = R$ 640,00"""
    rid = reserva_para_checkout(conn, estadias_anteriores=10)
    fazer_checkout(conn, rid, GRANDE, saida(conn, hora="12:00:01"))
    assert reserva(conn, rid)["valor_final_pago"] == Decimal("640.00")


def test_ct_u75_estadias_de_outro_hospede_nao_contam(conn):
    """Given o hóspede A com 10 estadias e o hóspede B com 0
    When B faz check-out
    Then B recebe 0%"""
    reserva_para_checkout(conn, estadias_anteriores=10, quarto=6)
    rid_b = reserva_para_checkout(conn, estadias_anteriores=0)
    fazer_checkout(conn, rid_b, GRANDE, saida(conn))
    assert reserva(conn, rid_b)["percentual_desconto"] == 0


def test_ct_u76_valor_final_arredondado_a_2_casas(conn):
    """Given bruto R$ 333,33 e desconto de 5%
    When o check-out é feito
    Then o valor final é arredondado a 2 casas (316,66)"""
    rid = reserva_para_checkout(conn, estadias_anteriores=5, bruto=Decimal("333.33"))
    fazer_checkout(conn, rid, GRANDE, saida(conn))
    assert reserva(conn, rid)["valor_final_pago"] == Decimal("316.66")


# ------------------------------------------------------------------ RN-08 late check-out
@pytest.mark.parametrize("hora,final", [
    ("08:00:00", "600.00"), ("12:00:00", "600.00"), ("12:00:01", "700.00"), ("15:00:00", "700.00"),
    ("18:00:00", "700.00"), ("18:00:01", "800.00"), ("23:59:59", "800.00"),
])
def test_ct_u100_taxa_por_horario_de_saida(conn, hora, final):
    """Given uma reserva CHECK-IN de bruto R$ 600,00 (D = 200,00) com saída prevista hoje
    When o check-out é feito em cada horário do dia previsto
    Then a taxa é 0, 50% ou 100% da diária conforme as fronteiras 12:00:00 e 18:00:00"""
    rid = reserva_para_checkout(conn)
    fazer_checkout(conn, rid, GRANDE, saida(conn, hora=hora))
    assert reserva(conn, rid)["valor_final_pago"] == Decimal(final)


def test_ct_u101_saida_antecipada_nao_gera_taxa_nem_estorno(conn):
    """When o check-out é feito um dia antes do previsto, às 15:00
    Then o valor final continua R$ 600,00 e nenhum ESTORNO é lançado"""
    rid = reserva_para_checkout(conn)
    fazer_checkout(conn, rid, GRANDE, saida(conn, dias=-1, hora="15:00:00"))
    assert reserva(conn, rid)["valor_final_pago"] == Decimal("600.00")
    assert [p for p in _pagamentos(conn, rid) if p[0] == "ESTORNO"] == []


def test_ct_u102_saida_depois_do_dia_previsto_e_recusada(conn):
    """When o check-out é às 08:00 do dia seguinte ao previsto
    Then o banco recusa com HOTEL-012 e a reserva continua em CHECK-IN"""
    rid = reserva_para_checkout(conn)
    codigo, _ = codigo_negocio(conn, "CALL fazer_checkout(%s,%s,%s)", (rid, GRANDE, saida(conn, dias=1, hora="08:00:00")))
    assert codigo == "HOTEL-012"
    assert reserva(conn, rid)["status_reserva"] == "CHECK-IN"


def test_ct_u103_saida_antes_do_checkin_real_e_recusada(conn):
    """When a saída informada é anterior ao check-in real
    Then o banco recusa com HOTEL-001"""
    rid = reserva_para_checkout(conn)
    codigo, _ = codigo_negocio(conn, "CALL fazer_checkout(%s,%s,%s)", (rid, GRANDE, saida(conn, dias=-4, hora="08:00:00")))
    assert codigo == "HOTEL-001"


def test_ct_u104_sem_horario_informado_usa_agora(conn):
    """When p_data_hora_saida é nulo
    Then data_checkout_real é gravada com o horário do banco (agora)"""
    rid = reserva_para_checkout(conn)
    conn.execute("CALL fazer_checkout(%s, %s)", (rid, GRANDE))
    gravado, agora = um(conn, "SELECT data_checkout_real, LOCALTIMESTAMP FROM reserva WHERE id_reserva=%s", (rid,))[0], \
        um(conn, "SELECT LOCALTIMESTAMP")[0]
    assert abs((agora - gravado).total_seconds()) < 60


def test_ct_u105_checkout_grava_data_checkout_real(conn):
    """When informo o horário de saída
    Then data_checkout_real é gravada exatamente como veio"""
    rid = reserva_para_checkout(conn)
    quando = saida(conn, hora="10:30:15")
    fazer_checkout(conn, rid, GRANDE, quando)
    assert reserva(conn, rid)["data_checkout_real"] == quando


def test_ct_u106_consumos_entram_no_valor_final(conn):
    """Given a reserva 10 (bruto 1200, consumos 70 + 45)
    When o check-out é feito dentro do prazo
    Then o valor final é R$ 1.315,00"""
    fazer_checkout(conn, 10, GRANDE, saida(conn, dias=2))
    assert reserva(conn, 10)["valor_final_pago"] == Decimal("1315.00")


# ------------------------------------------------------------------ RN-09 pagamento
@pytest.mark.parametrize("valor,aceito", [("600.00", True), ("599.99", False), ("650.00", True), ("0.00", False)])
def test_ct_u110_fronteira_do_pagamento(conn, valor, aceito):
    """Given um saldo de R$ 600,00
    When o valor pago é igual, 1 centavo a menos, maior ou zero
    Then só o valor que cobre o saldo é aceito, e o PAGAMENTO lançado é o saldo (sem troco)"""
    rid = reserva_para_checkout(conn)
    sql = "CALL fazer_checkout(%s,%s,%s)"
    params = (rid, Decimal(valor), saida(conn))
    if aceito:
        conn.execute(sql, params)
        assert _pagamentos(conn, rid) == [("PAGAMENTO", "PIX", Decimal("600.00"))]
    else:
        assert codigo_negocio(conn, sql, params)[0] == "HOTEL-009"
        assert reserva(conn, rid)["status_reserva"] == "CHECK-IN"
        assert _pagamentos(conn, rid) == []


@pytest.mark.parametrize("pago,estorno,lancado", [
    ("180.00", "0", "420.00"), ("0", "0", "600.00"), ("700.00", "100.00", None), ("600.00", "0", None),
])
def test_ct_u111_saldo_considera_pagamentos_e_estornos_ja_lancados(conn, pago, estorno, lancado):
    """Given valor final R$ 600,00 e pagamentos/estornos já lançados
    When o check-out é feito pagando o saldo
    Then o PAGAMENTO lançado é valor final - (pagamentos - estornos), ou nenhum se o saldo for zero"""
    rid = reserva_para_checkout(conn)
    if Decimal(pago) > 0:
        conn.execute("INSERT INTO pagamento (id_reserva,tipo,forma,valor) VALUES (%s,'PAGAMENTO','PIX',%s)", (rid, pago))
    if Decimal(estorno) > 0:
        conn.execute("INSERT INTO pagamento (id_reserva,tipo,forma,valor) VALUES (%s,'ESTORNO','PIX',%s)", (rid, estorno))
    antes = len(_pagamentos(conn, rid))
    fazer_checkout(conn, rid, Decimal(lancado or "0"), saida(conn))
    novos = _pagamentos(conn, rid)[antes:]
    assert [n[2] for n in novos] == ([Decimal(lancado)] if lancado else [])


@pytest.mark.parametrize("forma,esperado", [
    (None, "PIX"), ("DINHEIRO", "DINHEIRO"), ("CARTAO_CREDITO", "CARTAO_CREDITO"), ("CARTAO_DEBITO", "CARTAO_DEBITO"),
])
def test_ct_u112_forma_de_pagamento_valida(conn, forma, esperado):
    """When faço check-out com cada forma de pagamento (ou a padrão)
    Then a quitação é gravada com a forma informada (padrão PIX)"""
    rid = reserva_para_checkout(conn)
    fazer_checkout(conn, rid, GRANDE, saida(conn), forma)
    assert _pagamentos(conn, rid)[0][1] == esperado


@pytest.mark.parametrize("forma", ["CHEQUE", None])
def test_ct_u112_forma_de_pagamento_invalida(conn, forma):
    """When a forma é inválida ou nula
    Then o banco recusa com HOTEL-001"""
    rid = reserva_para_checkout(conn)
    assert codigo_negocio(conn, "CALL fazer_checkout(%s,%s,%s,%s)", (rid, GRANDE, saida(conn), forma))[0] == "HOTEL-001"


@pytest.mark.parametrize("valor", [None, Decimal("-1")])
def test_ct_u113_valor_pago_nulo_ou_negativo(conn, valor):
    """When o valor pago é nulo ou negativo
    Then o banco recusa com HOTEL-001"""
    assert codigo_negocio(conn, "CALL fazer_checkout(10,%s)", (valor,))[0] == "HOTEL-001"


@pytest.mark.parametrize("rid,codigo", [(1, "HOTEL-007"), (11, "HOTEL-007"), (999999, "HOTEL-006"), (None, "HOTEL-001")])
def test_ct_u114_so_reserva_em_checkin_faz_checkout(conn, rid, codigo):
    """When chamo fazer_checkout para reserva CHECK-OUT, CONFIRMADA, inexistente ou nula
    Then o erro de negócio é HOTEL-007, HOTEL-006 ou HOTEL-001"""
    assert codigo_negocio(conn, "CALL fazer_checkout(%s,%s)", (rid, GRANDE))[0] == codigo


def test_ct_u115_checkout_altera_duas_tabelas(conn):
    """When faço um check-out válido
    Then reserva muda para CHECK-OUT com data, desconto e valor final preenchidos, e pagamento recebe a quitação"""
    rid = reserva_para_checkout(conn)
    fazer_checkout(conn, rid, GRANDE, saida(conn))
    r = reserva(conn, rid)
    assert r["status_reserva"] == "CHECK-OUT"
    assert r["data_checkout_real"] and r["valor_final_pago"] is not None and r["percentual_desconto"] is not None
    assert len(_pagamentos(conn, rid)) == 1


def test_ct_u115_checkout_libera_o_quarto_para_nova_reserva(conn):
    """Given a reserva 10 (quarto 5) em CHECK-IN até D+2
    When o check-out é feito
    Then o quarto aceita nova reserva ativa no período restante (a reserva deixou de ser ativa)"""
    sql = ("INSERT INTO reserva (id_hospede,id_quarto,data_entrada_prevista,data_saida_prevista,status_reserva,"
           "valor_total_bruto) VALUES (1,5,CURRENT_DATE,CURRENT_DATE+2,'CONFIRMADA',600)")
    assert codigo_negocio(conn, sql)[0] == "HOTEL-005"
    fazer_checkout(conn, 10, GRANDE, saida(conn, dias=0, hora="11:00:00"))
    conn.execute(sql)


# ------------------------------------------------------------------ D-02: quarto em LIMPEZA (CT-U107)
def _status_quarto(conn, id_quarto):
    return um(conn, "SELECT status_quarto FROM quarto WHERE id_quarto=%s", (id_quarto,))[0]


def _todos_os_quartos(conn):
    return dict(todos(conn, "SELECT id_quarto, status_quarto FROM quarto ORDER BY id_quarto"))


@pytest.mark.parametrize("antes", ["OCUPADO", "DISPONIVEL", "LIMPEZA"])
def test_ct_u107_checkout_leva_o_quarto_para_limpeza(conn, antes):
    """Given uma reserva CHECK-IN no quarto 7, que está OCUPADO (ciclo normal), DISPONIVEL ou já em LIMPEZA
    When o check-out é feito
    Then o quarto fica em LIMPEZA (sem fazer_checkin, o quarto pode não ter sido marcado OCUPADO)"""
    rid = reserva_para_checkout(conn, quarto=7)
    conn.execute("UPDATE quarto SET status_quarto=%s WHERE id_quarto=7", (antes,))
    fazer_checkout(conn, rid, GRANDE, saida(conn))
    assert _status_quarto(conn, 7) == "LIMPEZA"


def test_ct_u107_checkout_da_reserva_10_muda_so_o_quarto_202(conn):
    """Given os dados de exemplo (reserva 10 em CHECK-IN no quarto 5 = 202, OCUPADO)
    When o check-out da reserva 10 é feito
    Then só o quarto 5 muda (OCUPADO -> LIMPEZA); os outros seis quartos continuam como estavam"""
    antes = _todos_os_quartos(conn)
    assert antes[5] == "OCUPADO"
    fazer_checkout(conn, 10, GRANDE, saida(conn, dias=0, hora="11:00:00"))
    depois = _todos_os_quartos(conn)
    assert depois[5] == "LIMPEZA"
    assert {k: v for k, v in depois.items() if k != 5} == {k: v for k, v in antes.items() if k != 5}


def test_ct_u107_quarto_em_manutencao_nao_e_sobrescrito(conn):
    """Given um quarto que entrou em MANUTENCAO com o hóspede ainda hospedado
    When o check-out é feito
    Then a reserva finaliza, mas o quarto continua em MANUTENCAO (não vira LIMPEZA)"""
    rid = reserva_para_checkout(conn, quarto=7)
    conn.execute("UPDATE quarto SET status_quarto='MANUTENCAO' WHERE id_quarto=7")
    fazer_checkout(conn, rid, GRANDE, saida(conn))
    assert reserva(conn, rid)["status_reserva"] == "CHECK-OUT"
    assert _status_quarto(conn, 7) == "MANUTENCAO"


def test_ct_u107_checkout_recusado_nao_mexe_no_quarto(conn):
    """Given um quarto OCUPADO e um valor pago 1 centavo abaixo do saldo
    When o check-out é tentado
    Then o banco recusa com HOTEL-009 e o quarto continua OCUPADO (a chamada é atômica)"""
    rid = reserva_para_checkout(conn, quarto=7)
    conn.execute("UPDATE quarto SET status_quarto='OCUPADO' WHERE id_quarto=7")
    codigo, _ = codigo_negocio(conn, "CALL fazer_checkout(%s,%s,%s)", (rid, Decimal("599.99"), saida(conn)))
    assert codigo == "HOTEL-009"
    assert _status_quarto(conn, 7) == "OCUPADO"


def test_ct_u107_rollback_devolve_o_status_do_quarto(conn):
    """Given um check-out feito dentro de uma transação
    When a transação é desfeita
    Then o quarto 5 volta a OCUPADO (a procedure não faz COMMIT)"""
    fazer_checkout(conn, 10, GRANDE, saida(conn, dias=0, hora="11:00:00"))
    assert _status_quarto(conn, 5) == "LIMPEZA"
    conn.rollback()
    assert _status_quarto(conn, 5) == "OCUPADO"


def test_ct_u107_governanca_devolve_o_quarto_a_disponivel(conn):
    """Given um quarto em LIMPEZA depois do check-out
    When a governança faz UPDATE para DISPONIVEL
    Then o ciclo fecha: OCUPADO -> LIMPEZA -> DISPONIVEL"""
    fazer_checkout(conn, 10, GRANDE, saida(conn, dias=0, hora="11:00:00"))
    conn.execute("UPDATE quarto SET status_quarto='DISPONIVEL' WHERE id_quarto=5")
    assert _status_quarto(conn, 5) == "DISPONIVEL"


# ------------------------------------------------------------------ seção 13.2: taxa em coluna própria (CT-U108)
@pytest.mark.parametrize("hora,taxa", [
    ("08:00:00", "0.00"), ("12:00:00", "0.00"), ("12:00:01", "100.00"),
    ("18:00:00", "100.00"), ("18:00:01", "200.00"), ("23:59:59", "200.00"),
])
def test_ct_u108_taxa_de_late_checkout_fica_gravada_na_reserva(conn, hora, taxa):
    """Given uma reserva de bruto R$ 600,00 (D = 200,00), sem desconto
    When o check-out é feito em cada horário do dia previsto
    Then reserva.taxa_checkout guarda 0, 50% ou 100% da diária, e valor_final_pago = 600 + taxa"""
    rid = reserva_para_checkout(conn)
    fazer_checkout(conn, rid, GRANDE, saida(conn, hora=hora))
    r = reserva(conn, rid)
    assert r["taxa_checkout"] == Decimal(taxa)
    assert r["valor_final_pago"] == Decimal("600.00") + Decimal(taxa)


def test_ct_u108_taxa_usa_a_diaria_cheia_mesmo_com_desconto(conn):
    """Given 10 estadias anteriores (10%) e saída às 12:00:01
    When o check-out é feito
    Then taxa_checkout = 100,00 (50% da diária cheia de 200, sem desconto) e percentual_desconto = 10"""
    rid = reserva_para_checkout(conn, estadias_anteriores=10)
    fazer_checkout(conn, rid, GRANDE, saida(conn, hora="12:00:01"))
    r = reserva(conn, rid)
    assert r["taxa_checkout"] == Decimal("100.00")
    assert r["percentual_desconto"] == Decimal("10")


def test_ct_u108_valor_final_e_a_soma_das_colunas_gravadas(conn):
    """Given desconto de 5%, um consumo de R$ 100,00 e late check-out às 15:00
    When o check-out é feito
    Then valor_final_pago = ROUND(bruto x (1 - desconto/100) + consumos + taxa_checkout, 2) = 770,00,
         conferido só com colunas da reserva (é isso que Q03, Q05 e Q10 usam, sem recalcular)"""
    rid = reserva_para_checkout(conn, estadias_anteriores=5)
    _consumo(conn, rid, Decimal("100.00"))
    fazer_checkout(conn, rid, GRANDE, saida(conn, hora="15:00:00"))
    r = reserva(conn, rid)
    esperado = (r["valor_total_bruto"] * (1 - r["percentual_desconto"] / 100) + Decimal("100.00")
                + r["taxa_checkout"]).quantize(Decimal("0.01"))
    assert r["taxa_checkout"] == Decimal("100.00")
    assert r["valor_final_pago"] == esperado == Decimal("770.00")


def test_ct_u108_reserva_ativa_tem_taxa_zero_e_sem_valor_final(conn):
    """Given uma reserva que ainda não fez check-out
    Then taxa_checkout é 0 (DEFAULT) e valor_final_pago é nulo até o check-out acontecer"""
    rid = reserva_para_checkout(conn)
    r = reserva(conn, rid)
    assert r["taxa_checkout"] == 0 and r["valor_final_pago"] is None


def test_ct_u108_checkout_recusado_nao_grava_taxa(conn):
    """Given um check-out às 18:00:01 (taxa de 200,00) com pagamento insuficiente
    When o banco recusa com HOTEL-009
    Then taxa_checkout continua 0 e a reserva continua em CHECK-IN"""
    rid = reserva_para_checkout(conn)
    codigo, _ = codigo_negocio(conn, "CALL fazer_checkout(%s,%s,%s)",
                               (rid, Decimal("700.00"), saida(conn, hora="18:00:01")))
    assert codigo == "HOTEL-009"
    r = reserva(conn, rid)
    assert r["taxa_checkout"] == 0 and r["status_reserva"] == "CHECK-IN"
