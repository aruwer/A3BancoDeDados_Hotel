"""CT-U170 a CT-U181 · as 10 consultas de postgresql/03_consultas.sql, conferidas contra valores
calculados À MÃO a partir de 02_inserts.sql (não copiados da saída do banco).

O arquivo 03_consultas.sql tem um bloco por consulta, marcado por '-- @Qnn' e com o
'Resultado esperado' em comentário; cada bloco é executado isolado.
"""
import json
import re
from collections import defaultdict
from datetime import date, timedelta
from decimal import Decimal
from pathlib import Path

import pytest

RAIZ = Path(__file__).resolve().parents[2]
ARQUIVO = RAIZ / "postgresql" / "03_consultas.sql"


def _blocos_das_consultas():
    """Texto SQL de cada Qnn: do comentário '-- @Qnn' até a próxima linha '-- -----'."""
    sql = ARQUIVO.read_text(encoding="utf-8")
    return {m.group(1): m.group(2) for m in re.finditer(
        r"^-- @(Q\d\d)\b.*?\n(.*?)(?=^-- -{10,}|\Z)", sql, re.S | re.M)}


@pytest.fixture(scope="module")
def resultados():
    """Executa cada consulta isoladamente (uma quebrada não derruba as outras).

    Devolve ({'Q01': [linhas em dict], ...}, {'Q08': 'erro do banco', ...}, data de hoje do banco).
    """
    import psycopg
    import psycopg.rows
    from conftest import DSN
    por_consulta, erros = {}, {}
    with psycopg.connect(DSN) as c:
        hoje = c.execute("SELECT CURRENT_DATE").fetchone()[0]
        for nome, sql in _blocos_das_consultas().items():
            try:
                with c.transaction():
                    por_consulta[nome] = c.cursor(row_factory=psycopg.rows.dict_row).execute(sql).fetchall()
            except psycopg.Error as e:
                erros[nome] = f"{e.sqlstate}: {e.diag.message_primary}"
    return por_consulta, erros, hoje


def _q(resultados, nome):
    por_consulta, erros, _ = resultados
    assert nome not in erros, f"{nome} não executa: {erros[nome]}"
    return por_consulta[nome]


def test_ct_u170_q01_receita_por_categoria(resultados):
    """Given estadias CHECK-OUT sem desconto (Standard 5 estadias, Superior 3, Suíte 2)
    When executo Q01
    Then a receita de diárias por categoria é Suíte 3500, Superior 2700 e Standard 2200, em ordem decrescente"""
    esperado = [("Suíte", 2, Decimal("3500.00")), ("Superior", 3, Decimal("2700.00")), ("Standard", 5, Decimal("2200.00"))]
    obtido = [(l["nome_categoria"], l["estadias_concluidas"], Decimal(str(l["receita_diarias"]))) for l in _q(resultados, "Q01")]
    assert obtido == esperado


def test_ct_u171_q02_chegadas_dos_proximos_7_dias(resultados):
    """Given as reservas CONFIRMADA 12 (D+5), 19 (D+7), 20 (D+8) e 11 (D+10)
    When executo Q02
    Then só as reservas 12 e 19 aparecem (D+7 é o último dia da janela; D+8 e D+10 ficam fora; as CANCELADAS não entram)"""
    q02 = _q(resultados, "Q02")
    assert [(l["id_reserva"], l["nome_nome"] if "nome_nome" in l else l["nome_completo"], l["numero_quarto"],
             l["nome_categoria"], l["noites"]) for l in q02] == [(12, "Carlos Eduardo Menezes", "201", "Superior", 3),
                                                      (19, "Fernanda Rocha Almeida", "102", "Standard", 1)]


def test_ct_u172_q03_ranking_com_empate_na_5a_posicao(resultados):
    """Given os gastos CHECK-OUT por hóspede: João 2420, Carlos 2250, Ana 1550, Fernanda 1200, Mariana 800, Ricardo 800, Luciana 400
    When executo Q03
    Then o ranking tem 6 linhas, o empate de R$ 800,00 divide a posição 5 e Luciana (posição 7) fica de fora"""
    esperado = [
        (1, "João Pedro Vasconcelos", Decimal("2420.00"), 1),
        (2, "Carlos Eduardo Menezes", Decimal("2250.00"), 2),
        (3, "Ana Beatriz Souza Lima", Decimal("1550.00"), 2),
        (4, "Fernanda Rocha Almeida", Decimal("1200.00"), 1),
        (5, "Mariana Costa Ferreira", Decimal("800.00"), 1),
        (5, "Ricardo Alves Teixeira", Decimal("800.00"), 1),
    ]
    obtido = [(l["posicao"], l["nome_completo"], Decimal(str(l["total_gasto"])), l["estadias"]) for l in _q(resultados, "Q03")]
    assert obtido == esperado


def test_ct_u173_q04_quartos_livres_no_periodo(resultados):
    """Given o período D+8 a D+10, a reserva 12 termina em D+8, a 11 começa em D+10 (as duas encostam) e a 20 (D+8 a D+9) cai dentro
    When executo Q04
    Then a 12 e a 11 não bloqueiam, a 20 bloqueia o quarto 202, o 103 (manutenção) fica de fora e os outros 5 quartos aparecem"""
    obtido = [(l["numero_quarto"], l["nome_categoria"], l["andar"]) for l in _q(resultados, "Q04")]
    assert obtido == [("101", "Standard", 1), ("102", "Standard", 1), ("201", "Superior", 2),
                      ("301", "Suíte", 3), ("302", "Suíte", 3)]


def test_ct_u174_q05_receita_acumulada_mes_a_mes(resultados):
    """Given os valores finais das estadias CHECK-OUT e suas datas de saída (relativas a hoje)
    When executo Q05
    Then a receita de cada mês é a soma das saídas do mês e o acumulado reinicia a cada ano"""
    hoje = resultados[2]
    saidas = [(-37, 1080), (-18, 470), (-27, 1650), (-56, 2420), (-12, 600), (-21, 1200), (-7, 800), (-10, 800), (-4, 400), (-119, 675)]
    por_mes = defaultdict(Decimal)
    for dias, valor in saidas:
        d = hoje + timedelta(days=dias)
        por_mes[(d.year, d.month)] += Decimal(valor)
    esperado, acumulado = [], defaultdict(Decimal)
    for (ano, mes) in sorted(por_mes):
        acumulado[ano] += por_mes[(ano, mes)]
        esperado.append((f"{ano}-{mes:02d}", por_mes[(ano, mes)], acumulado[ano]))
    obtido = [(l["mes"], Decimal(str(l["receita_mes"])), Decimal(str(l["receita_acumulada"]))) for l in _q(resultados, "Q05")]
    assert obtido == esperado
    assert sum(r[1] for r in obtido) == Decimal("10095")


def test_ct_u175_q06_cancelamento_acima_de_20_por_cento(resultados):
    """Given Standard com 2 de 10 canceladas (20% exato), Superior com 1 de 8 (12,5%) e Suíte com 1 de 3 (33,3%)
    When executo Q06
    Then só a Suíte aparece: a Standard, com exatos 20%, fica de fora ("acima de 20%")"""
    obtido = [(l["nome_categoria"], l["total_reservas"], l["canceladas"], Decimal(str(l["taxa_cancelamento"]))) for l in _q(resultados, "Q06")]
    assert obtido == [("Suíte", 3, 1, Decimal("33.3"))]


def test_ct_u176_q07_participacao_de_cada_servico(resultados):
    """Given consumos: Jantar 630, Spa 600, Café 245, Lavanderia 90, Translado 90, Estacionamento 80, Frigobar 75, Passeio 0 (total 1810)
    When executo Q07
    Then os percentuais são 34,8 / 33,1 / 13,5 / 5,0 / 5,0 / 4,4 / 4,1 / 0,0 e somam ~100% (o serviço nunca consumido aparece com 0)"""
    esperado = [("Jantar", Decimal("630.00"), Decimal("34.8")), ("Spa", Decimal("600.00"), Decimal("33.1")),
                ("Café da manhã", Decimal("245.00"), Decimal("13.5")), ("Lavanderia", Decimal("90.00"), Decimal("5.0")),
                ("Translado aeroporto", Decimal("90.00"), Decimal("5.0")), ("Estacionamento", Decimal("80.00"), Decimal("4.4")),
                ("Frigobar", Decimal("75.00"), Decimal("4.1")), ("Passeio turístico", Decimal("0.00"), Decimal("0.0"))]
    q07 = _q(resultados, "Q07")
    assert [(l["nome_servico"], Decimal(str(l["receita"])), Decimal(str(l["percentual"]))) for l in q07] == esperado
    assert abs(sum(Decimal(str(l["percentual"])) for l in q07) - 100) <= Decimal("0.3")


def test_ct_u177_q08_ultima_estadia_de_cada_hospede(resultados):
    """Given as estadias CHECK-OUT; Ana e Carlos têm duas (vale a mais recente) e Gabriel não tem nenhuma
    When executo Q08
    Then há 8 linhas, ordenadas da saída mais recente para a mais antiga, sem o Gabriel"""
    esperado = [("Luciana Prado Nogueira", "101", 4), ("Mariana Costa Ferreira", "102", 7),
                ("Ricardo Alves Teixeira", "201", 10), ("Carlos Eduardo Menezes", "102", 12),
                ("Ana Beatriz Souza Lima", "101", 18), ("Fernanda Rocha Almeida", "202", 21),
                ("João Pedro Vasconcelos", "301", 56), ("Larissa Mendes Carvalho", "101", 119)]
    obtido = [(l["nome_completo"], l["numero_quarto"], l["dias_desde_fim"]) for l in _q(resultados, "Q08")]
    assert obtido == esperado


def test_ct_u178_q09_ninguem_usou_todos_os_servicos(resultados):
    """Given nenhum hóspede consumiu os 8 serviços do catálogo (a Larissa usou 7)
    When executo Q09
    Then o resultado é vazio (resultado vazio é válido)"""
    assert _q(resultados, "Q09") == []


def test_ct_u178_q09_hospede_que_usa_todos_aparece(conn):
    """Given um hóspede que consumiu todos os 8 serviços numa reserva
    When executo a divisão relacional de Q09
    Then só ele aparece, e quem usou todos menos um (Larissa, Gabriel) não aparece"""
    bloco = _blocos_das_consultas()["Q09"].rstrip().rstrip(";")
    for sid in range(1, 9):
        conn.execute("INSERT INTO consumo_servico (id_reserva,id_servico,quantidade,valor_total_item) VALUES (4,%s,1,1)", (sid,))
    for sid in range(1, 8):   # hóspede 8 (reserva 10) usou 1 e 3; completa até faltar só o 8
        if sid not in (1, 3):
            conn.execute("INSERT INTO consumo_servico (id_reserva,id_servico,quantidade,valor_total_item) VALUES (10,%s,1,1)", (sid,))
    nomes = [r[1] for r in conn.execute(bloco).fetchall()]
    assert nomes == ["João Pedro Vasconcelos"]


def test_ct_u179_q10_subtotais_e_total_geral(resultados):
    """Given as reservas CHECK-OUT, CANCELADA e NO-SHOW por categoria
    When executo Q10 (ROLLUP)
    Then cada categoria tem linhas por situação e subtotal, e o total geral é 15 reservas e R$ 10.745,00"""
    linhas = {(l["categoria_quarto"], l["situacao"]): (l["reservas"], Decimal(str(l["receita"]))) for l in _q(resultados, "Q10")}
    esperado = {
        ("Standard", "CANCELADA"): (2, Decimal("300")), ("Standard", "CHECK-OUT"): (5, Decimal("2945")),
        ("Standard", "NO-SHOW"): (1, Decimal("200")), ("Standard", "SUBTOTAL"): (8, Decimal("3445")),
        ("Superior", "CANCELADA"): (1, Decimal("150")), ("Superior", "CHECK-OUT"): (3, Decimal("3080")),
        ("Superior", "SUBTOTAL"): (4, Decimal("3230")),
        ("Suíte", "CANCELADA"): (1, Decimal("0")), ("Suíte", "CHECK-OUT"): (2, Decimal("4070")),
        ("Suíte", "SUBTOTAL"): (3, Decimal("4070")),
        ("TOTAL GERAL", ""): (15, Decimal("10745")),
    }
    assert linhas == esperado
    subtotais = [v for (c, s), v in linhas.items() if s == "SUBTOTAL"]
    assert linhas[("TOTAL GERAL", "")] == (sum(v[0] for v in subtotais), sum(v[1] for v in subtotais))


def test_ct_u180_rubrica_tecnicas_exigidas():
    """Given as 10 consultas
    Then há 10 consultas, 2+ com JOIN, 2+ com window function, 2+ com agregação e 1+ com NOT EXISTS"""
    blocos = _blocos_das_consultas()
    assert sorted(blocos) == [f"Q{i:02d}" for i in range(1, 11)]
    join = [q for q, b in blocos.items() if re.search(r"\bJOIN\b", b, re.I)]
    window = [q for q, b in blocos.items() if re.search(r"\bOVER\s*\(", b, re.I)]
    agregacao = [q for q, b in blocos.items() if re.search(r"\bGROUP BY\b", b, re.I)]
    anti_join = [q for q, b in blocos.items() if re.search(r"NOT EXISTS", b, re.I)]
    assert len(join) >= 2 and len(window) >= 2 and len(agregacao) >= 2 and len(anti_join) >= 1


def test_ct_u181_cada_consulta_tem_objetivo_em_comentario():
    """Given o arquivo 03_consultas.sql
    Then cada consulta Q01 a Q10 tem um comentário '-- @Qnn' com o objetivo (exigência do enunciado)"""
    sql = ARQUIVO.read_text(encoding="utf-8")
    ausentes = [f"Q{i:02d}" for i in range(1, 11) if not re.search(rf"--\s*@Q{i:02d}\b", sql)]
    assert ausentes == []
