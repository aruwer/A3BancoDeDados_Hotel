"""CT-U170 a CT-U181 · as 10 consultas de postgresql/03_consultas.sql, conferidas contra valores
calculados À MÃO a partir de 02_inserts.sql (não copiados da saída do banco).

O arquivo 03_consultas.sql é uma única instrução que devolve (consulta, ordem, linha):
ordem 0 = 'linhas: N' e as demais = uma linha por resultado, em JSON.
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
    """Texto da consulta de cada Qnn (a parte que devolve 'linhas: N')."""
    sql = ARQUIVO.read_text(encoding="utf-8")
    return {m.group(1): m.group(2) for m in re.finditer(
        r"SELECT '(Q\d\d)' AS consulta, 0::bigint AS ordem.*?\n\s*FROM \(\n(.*?)\n\s*\) c\n", sql, re.S)}


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
    """Given estadias CHECK-OUT sem desconto (Standard 4 estadias, Superior 3, Suíte 2)
    When executo Q01
    Then a receita de diárias por categoria é Suíte 3500, Superior 2700 e Standard 2000, em ordem decrescente"""
    esperado = [("Suíte", 2, Decimal("3500.00")), ("Superior", 3, Decimal("2700.00")), ("Standard", 4, Decimal("2000.00"))]
    obtido = [(l["nome_categoria"], l["estadias_concluidas"], Decimal(str(l["receita_diarias"]))) for l in _q(resultados, "Q01")]
    assert obtido == esperado


def test_ct_u171_q02_chegadas_dos_proximos_7_dias(resultados):
    """Given as reservas CONFIRMADA 11 (D+10) e 12 (D+5)
    When executo Q02
    Then só a reserva 12 aparece (D+10 fica fora da janela; as CANCELADAS dentro da janela não entram)"""
    q02 = _q(resultados, "Q02")
    assert [(l["id_reserva"], l["nome_nome"] if "nome_nome" in l else l["nome_completo"], l["numero_quarto"],
             l["nome_categoria"], l["noites"]) for l in q02] == [(12, "Carlos Eduardo Menezes", "201", "Superior", 3)]


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
    """Given o período D+8 a D+10, a reserva 12 termina em D+8 e a reserva 11 começa em D+10 (as duas encostam)
    When executo Q04
    Then nenhuma bloqueia, o quarto 103 (manutenção) fica de fora e os outros 6 quartos aparecem"""
    obtido = [(l["numero_quarto"], l["nome_categoria"], l["andar"]) for l in _q(resultados, "Q04")]
    assert obtido == [("101", "Standard", 1), ("102", "Standard", 1), ("201", "Superior", 2),
                      ("202", "Superior", 2), ("301", "Suíte", 3), ("302", "Suíte", 3)]


def test_ct_u174_q05_receita_acumulada_mes_a_mes(resultados):
    """Given os valores finais das estadias CHECK-OUT e suas datas de saída (relativas a hoje)
    When executo Q05
    Then a receita de cada mês é a soma das saídas do mês e o acumulado reinicia a cada ano"""
    hoje = resultados[2]
    saidas = [(-37, 1080), (-18, 470), (-27, 1650), (-56, 2420), (-12, 600), (-21, 1200), (-7, 800), (-10, 800), (-4, 400)]
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
    assert sum(r[1] for r in obtido) == Decimal("9420")


def test_ct_u175_q06_cancelamento_acima_de_20_por_cento(resultados):
    """Given Standard com 2 de 8 canceladas (25%), Superior com 1 de 7 (14,3%) e Suíte com 1 de 3 (33,3%)
    When executo Q06
    Then só Suíte e Standard aparecem, em ordem decrescente de taxa"""
    obtido = [(l["nome_categoria"], l["total_reservas"], l["canceladas"], Decimal(str(l["taxa_cancelamento"]))) for l in _q(resultados, "Q06")]
    assert obtido == [("Suíte", 3, 1, Decimal("33.3")), ("Standard", 8, 2, Decimal("25.0"))]


def test_ct_u176_q07_participacao_de_cada_servico(resultados):
    """Given consumos: Jantar 540, Spa 450, Café 210, Frigobar 50, Lavanderia 45, Estacionamento 40 (total 1335)
    When executo Q07
    Then os percentuais são 40,4 / 33,7 / 15,7 / 3,7 / 3,4 / 3,0 e somam ~100%"""
    esperado = [("Jantar", Decimal("540.00"), Decimal("40.4")), ("Spa", Decimal("450.00"), Decimal("33.7")),
                ("Café da manhã", Decimal("210.00"), Decimal("15.7")), ("Frigobar", Decimal("50.00"), Decimal("3.7")),
                ("Lavanderia", Decimal("45.00"), Decimal("3.4")), ("Estacionamento", Decimal("40.00"), Decimal("3.0"))]
    q07 = _q(resultados, "Q07")
    assert [(l["nome_servico"], Decimal(str(l["receita"])), Decimal(str(l["percentual"]))) for l in q07] == esperado
    assert abs(sum(Decimal(str(l["percentual"])) for l in q07) - 100) <= Decimal("0.3")


@pytest.mark.bug
@pytest.mark.xfail(strict=True, reason="BUG-01: Q08 referencia r.* fora do escopo (alias da subconsulta é t)")
def test_ct_u177_q08_ultima_estadia_de_cada_hospede(resultados):
    """Given as estadias CHECK-OUT; Ana e Carlos têm duas (vale a mais recente) e Gabriel não tem nenhuma
    When executo Q08
    Then há 7 linhas, ordenadas da saída mais recente para a mais antiga, sem o Gabriel"""
    esperado = [("Luciana Prado Nogueira", "101", 4), ("Mariana Costa Ferreira", "102", 7),
                ("Ricardo Alves Teixeira", "201", 10), ("Carlos Eduardo Menezes", "102", 12),
                ("Ana Beatriz Souza Lima", "101", 18), ("Fernanda Rocha Almeida", "202", 21),
                ("João Pedro Vasconcelos", "301", 56)]
    obtido = [(l["nome_completo"], l["numero_quarto"], l["dias_desde_fim"]) for l in _q(resultados, "Q08")]
    assert obtido == esperado


def test_ct_u178_q09_ninguem_usou_todos_os_servicos(resultados):
    """Given nenhum hóspede consumiu os 6 serviços do catálogo
    When executo Q09
    Then o resultado é vazio (resultado vazio é válido)"""
    assert _q(resultados, "Q09") == []


def test_ct_u178_q09_hospede_que_usa_todos_aparece(conn):
    """Given um hóspede que consumiu todos os 6 serviços numa reserva
    When executo a divisão relacional de Q09
    Then só ele aparece, e quem usou todos menos um não aparece"""
    sql = ARQUIVO.read_text(encoding="utf-8")
    bloco = re.search(r"SELECT 'Q09', row_number\(\) OVER \(\), to_json\(q\)::text\s+FROM \((.*?)\) q\s+UNION ALL", sql, re.S).group(1)
    for sid in range(1, 7):
        conn.execute("INSERT INTO consumo_servico (id_reserva,id_servico,quantidade,valor_total_item) VALUES (4,%s,1,1)", (sid,))
    for sid in range(1, 6):   # hóspede 8 (reserva 10) usou 1 e 3; completa até faltar só o 6
        if sid not in (1, 3):
            conn.execute("INSERT INTO consumo_servico (id_reserva,id_servico,quantidade,valor_total_item) VALUES (10,%s,1,1)", (sid,))
    nomes = [r[1] for r in conn.execute(bloco).fetchall()]
    assert nomes == ["João Pedro Vasconcelos"]


def test_ct_u179_q10_subtotais_e_total_geral(resultados):
    """Given as reservas CHECK-OUT, CANCELADA e NO-SHOW por categoria
    When executo Q10 (ROLLUP)
    Then cada categoria tem linhas por situação e subtotal, e o total geral é 14 reservas e R$ 10.070,00"""
    linhas = {(l["categoria_quarto"], l["situacao"]): (l["reservas"], Decimal(str(l["receita"]))) for l in _q(resultados, "Q10")}
    esperado = {
        ("Standard", "CANCELADA"): (2, Decimal("300")), ("Standard", "CHECK-OUT"): (4, Decimal("2270")),
        ("Standard", "NO-SHOW"): (1, Decimal("200")), ("Standard", "SUBTOTAL"): (7, Decimal("2770")),
        ("Superior", "CANCELADA"): (1, Decimal("150")), ("Superior", "CHECK-OUT"): (3, Decimal("3080")),
        ("Superior", "SUBTOTAL"): (4, Decimal("3230")),
        ("Suíte", "CANCELADA"): (1, Decimal("0")), ("Suíte", "CHECK-OUT"): (2, Decimal("4070")),
        ("Suíte", "SUBTOTAL"): (3, Decimal("4070")),
        ("TOTAL GERAL", ""): (14, Decimal("10070")),
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


@pytest.mark.bug
@pytest.mark.xfail(strict=True, reason="BUG-02: 03_consultas.sql gerado perdeu os comentários -- @Qnn com o objetivo")
def test_ct_u181_cada_consulta_tem_objetivo_em_comentario():
    """Given o arquivo 03_consultas.sql
    Then cada consulta Q01 a Q10 tem um comentário '-- @Qnn' com o objetivo (exigência do enunciado)"""
    sql = ARQUIVO.read_text(encoding="utf-8")
    ausentes = [f"Q{i:02d}" for i in range(1, 11) if not re.search(rf"--\s*@Q{i:02d}\b", sql)]
    assert ausentes == []
