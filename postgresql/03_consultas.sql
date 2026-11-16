-- 03_consultas.sql
-- Banco de Dados: PostgreSQL 17
-- Consultas de negócio Q01 a Q05 (perguntas em perguntas_de_negocio.md).
-- Rodar depois do 01_ddl.sql e do 02_inserts.sql:
--   psql -U hotel -d hotel -f postgresql/03_consultas.sql
--
-- Mapeamento para o modelo atual (o texto das perguntas usa nomes do modelo antigo):
--   estadia concluída = status_reserva 'CHECK-OUT' (FINALIZADA no regras.md)
--   reserva ativa     = qualquer status exceto 'CANCELADA' e 'NO-SHOW'
--   tipo de quarto    = Categoria_Quarto
--   gasto/receita da estadia = valor_final_pago (diárias + consumos)
-- Os resultados esperados foram calculados à mão a partir do 02_inserts.sql.
-- Valores monetários em R$; "hoje" = CURRENT_DATE.

-- ---------------------------------------------------------------------------
-- @Q01 · Receita por categoria de quarto (JOIN de 3 tabelas + GROUP BY/HAVING)
-- Pergunta: Quanto cada categoria de quarto faturou com diárias nas estadias
--   concluídas, mostrando só as categorias que faturaram mais de zero?
-- Receita de diárias = valor_total_bruto x (1 - percentual_desconto/100), sem consumos.
-- Resultado esperado (3 linhas, nesta ordem):
--   Suíte    | 2 estadias | 3500.00   (reservas 3 e 4: 1500 + 2000)
--   Superior | 3 estadias | 2700.00   (reservas 1, 6 e 8: 900 + 1200 + 600)
--   Standard | 4 estadias | 2000.00   (reservas 2, 5, 7 e 9: 400 + 600 + 600 + 400)
-- A reserva 10 (CHECK-IN, Superior) não entra: a estadia ainda não foi concluída.
SELECT c.nome_categoria,
       COUNT(*) AS estadias_concluidas,
       ROUND(SUM(r.valor_total_bruto * (1 - COALESCE(r.percentual_desconto, 0) / 100)), 2) AS receita_diarias
FROM Reserva r
JOIN Quarto q ON q.id_quarto = r.id_quarto
JOIN Categoria_Quarto c ON c.id_categoria = q.id_categoria
WHERE r.status_reserva = 'CHECK-OUT'
GROUP BY c.id_categoria, c.nome_categoria
HAVING SUM(r.valor_total_bruto * (1 - COALESCE(r.percentual_desconto, 0) / 100)) > 0
ORDER BY receita_diarias DESC;

-- ---------------------------------------------------------------------------
-- @Q02 · Chegadas dos próximos 7 dias (JOIN de 4 tabelas)
-- Pergunta: Quais reservas confirmadas têm check-in nos próximos 7 dias, com o nome
--   do hóspede, o quarto, a categoria e o número de noites, em ordem de chegada?
-- Janela: de hoje até hoje + 7, inclusive nos dois extremos.
-- Resultado esperado (1 linha):
--   reserva 12 | Carlos Eduardo Menezes | quarto 201 | Superior | entrada hoje + 5 | 3 noites
-- Ficam de fora: a reserva 11 (CONFIRMADA, entrada hoje + 10, depois da janela) e as
--   reservas 13 a 16 (CANCELADAS, entradas em hoje + 7, + 6, + 2 e + 1, dentro da janela).
SELECT r.id_reserva,
       h.nome_completo,
       q.numero_quarto,
       c.nome_categoria,
       r.data_entrada_prevista,
       (r.data_saida_prevista - r.data_entrada_prevista) AS noites
FROM Reserva r
JOIN Hospede h ON h.id_hospede = r.id_hospede
JOIN Quarto q ON q.id_quarto = r.id_quarto
JOIN Categoria_Quarto c ON c.id_categoria = q.id_categoria
WHERE r.status_reserva = 'CONFIRMADA'
  AND r.data_entrada_prevista BETWEEN CURRENT_DATE AND CURRENT_DATE + 7
ORDER BY r.data_entrada_prevista, q.numero_quarto;

-- ---------------------------------------------------------------------------
-- @Q03 · Ranking dos 5 hóspedes que mais gastaram (JOIN + GROUP BY/HAVING + RANK)
-- Pergunta: Quais são os 5 hóspedes que mais gastaram no hotel, somando diárias e
--   consumos, e em que posição ficou cada um (empates na mesma posição)?
-- Gasto total = soma do valor_final_pago das estadias concluídas.
-- Resultado esperado (6 linhas, porque há empate na 5ª posição):
--   1 | João Pedro Vasconcelos | 2420.00 | 1 estadia
--   2 | Carlos Eduardo Menezes | 2250.00 | 2 estadias
--   3 | Ana Beatriz Souza Lima | 1550.00 | 2 estadias
--   4 | Fernanda Rocha Almeida | 1200.00 | 1 estadia  (sem nenhum consumo extra)
--   5 | Mariana Costa Ferreira |  800.00 | 1 estadia  (empate)
--   5 | Ricardo Alves Teixeira |  800.00 | 1 estadia  (empate)
-- Luciana Prado Nogueira (400.00) fica na 7ª posição e não entra. Gabriel Santos Oliveira
--   está hospedado hoje (CHECK-IN) e não tem estadia concluída, então não aparece.
SELECT posicao, nome_completo, total_gasto, estadias
FROM (
    SELECT h.nome_completo,
           SUM(r.valor_final_pago) AS total_gasto,
           COUNT(*) AS estadias,
           RANK() OVER (ORDER BY SUM(r.valor_final_pago) DESC) AS posicao
    FROM Hospede h
    JOIN Reserva r ON r.id_hospede = h.id_hospede
    WHERE r.status_reserva = 'CHECK-OUT'
    GROUP BY h.id_hospede, h.nome_completo
    HAVING SUM(r.valor_final_pago) > 0
) ranking
WHERE posicao <= 5
ORDER BY posicao, nome_completo;

-- ---------------------------------------------------------------------------
-- @Q04 · Quartos disponíveis no período (NOT EXISTS)
-- Pergunta: Quais quartos estão livres para quem quer entrar no dia X e sair no dia Y,
--   ou seja, não têm nenhuma reserva ativa que se sobreponha a esse período?
-- Período testado: X = hoje + 8 e Y = hoje + 10. Quarto em manutenção fica fora.
-- Sobreposição: entrada_existente < Y e saida_existente > X (intervalo [entrada, saída)).
-- Resultado esperado (6 linhas):
--   101 Standard (andar 1) | 102 Standard (1) | 201 Superior (2) |
--   202 Superior (2) | 301 Suíte (3) | 302 Suíte (3)
-- O quarto 103 não aparece (manutenção). Os limites ficam provados assim:
--   quarto 201: a reserva 12 sai exatamente em X (hoje + 8) e não bloqueia;
--   quarto 101: a reserva 11 entra exatamente em Y (hoje + 10) e não bloqueia;
--   quarto 301: a reserva 13 se sobrepõe ao período, mas está CANCELADA e não bloqueia.
-- Para ver um quarto bloqueado, use X = hoje + 6 e Y = hoje + 9: o 201 sai da lista.
WITH periodo AS (
    SELECT CURRENT_DATE + 8 AS x, CURRENT_DATE + 10 AS y
)
SELECT q.numero_quarto, c.nome_categoria, q.andar
FROM Quarto q
JOIN Categoria_Quarto c ON c.id_categoria = q.id_categoria
CROSS JOIN periodo p
WHERE q.status_manutencao IS NOT TRUE
  AND NOT EXISTS (
      SELECT 1
      FROM Reserva r
      WHERE r.id_quarto = q.id_quarto
        AND r.status_reserva NOT IN ('CANCELADA', 'NO-SHOW')
        AND r.data_entrada_prevista < p.y
        AND r.data_saida_prevista > p.x
  )
ORDER BY q.numero_quarto;

-- ---------------------------------------------------------------------------
-- @Q05 · Receita acumulada mês a mês (window SUM OVER + HAVING)
-- Pergunta: Em cada mês do ano, quanto o hotel faturou e quanto já tinha acumulado
--   desde janeiro?
-- A receita de uma estadia conta no mês da data_saida_prevista; só aparecem meses com
--   receita. O acumulado reinicia a cada ano.
-- Resultado esperado: a divisão por mês depende do dia em que a consulta roda, porque as
--   datas do 02_inserts.sql são relativas a hoje. Para uma execução em 16/11/2026:
--   2026-09 |  2420.00 |  2420.00   (reserva 4)
--   2026-10 |  4400.00 |  6820.00   (reservas 1, 2, 3 e 6: 1080 + 470 + 1650 + 1200)
--   2026-11 |  2600.00 |  9420.00   (reservas 5, 7, 8 e 9: 600 + 800 + 800 + 400)
-- Em qualquer dia, a soma de receita_mes é 9420.00 e o último acumulado do ano chega a
--   9420.00 (se as estadias não cruzarem a virada do ano).
SELECT TO_CHAR(mes, 'YYYY-MM') AS mes,
       receita_mes,
       SUM(receita_mes) OVER (PARTITION BY EXTRACT(YEAR FROM mes) ORDER BY mes) AS receita_acumulada
FROM (
    SELECT DATE_TRUNC('month', r.data_saida_prevista)::date AS mes,
           SUM(r.valor_final_pago) AS receita_mes
    FROM Reserva r
    WHERE r.status_reserva = 'CHECK-OUT'
    GROUP BY DATE_TRUNC('month', r.data_saida_prevista)::date
    HAVING SUM(r.valor_final_pago) > 0
) mensal
ORDER BY mes;
