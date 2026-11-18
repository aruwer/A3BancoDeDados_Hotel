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

-- ---------------------------------------------------------------------------
-- @Q06 · Tipos de quarto com cancelamento acima de 20% (JOIN + GROUP BY/HAVING)
-- Pergunta: Quais categorias de quarto têm taxa de cancelamento acima de 20%
--   das reservas feitas?
-- Taxa = reservas CANCELADA / todas as reservas da categoria (qualquer status).
-- NO-SHOW não conta como cancelamento.
-- Fronteira: categoria com taxa EXATAMENTE 20% (não entra) e categoria com 0 cancelamentos.
-- Resultado esperado (calculado à mão com 02_inserts.sql):
--   Standard | 5 | 1 | 20.0   (reserva 15 cancelada de 5 total) -> NÃO entra (igual a 20%)
--   Superior | 4 | 1 | 25.0   (reserva 14 cancelada de 4 total) -> ENTRA
--   Suíte    | 2 | 1 | 50.0   (reserva 13 cancelada de 2 total) -> ENTRA
SELECT c.nome_categoria,
       COUNT(*) AS total_reservas,
       COUNT(*) FILTER (WHERE r.status_reserva = 'CANCELADA') AS canceladas,
       ROUND(100.0 * COUNT(*) FILTER (WHERE r.status_reserva = 'CANCELADA') / COUNT(*), 1) AS taxa_cancelamento
FROM Reserva r
JOIN Quarto q ON q.id_quarto = r.id_quarto
JOIN Categoria_Quarto c ON c.id_categoria = q.id_categoria
GROUP BY c.id_categoria, c.nome_categoria
HAVING 100.0 * COUNT(*) FILTER (WHERE r.status_reserva = 'CANCELADA') / COUNT(*) > 20
ORDER BY taxa_cancelamento DESC, c.nome_categoria;

-- ---------------------------------------------------------------------------
-- @Q07 · Participação de cada serviço na receita de consumo (LEFT JOIN + window sobre agregação)
-- Pergunta: Que percentual da receita de consumos vem de cada serviço?
-- Serviço nunca consumido aparece com 0 (LEFT JOIN). Percentual = receita_servico / SUM(receita) OVER ().
-- Fronteira: dois serviços com mesmo total e um serviço nunca consumido.
-- Receita de consumo = soma de valor_total_item (quantidade x preço copiado no lançamento).
-- Resultado esperado (calculado à mão com 02_inserts.sql):
--   Jantar        | 540.00 | 25.0
--   Spa           | 450.00 | 20.8
--   Café da manhã | 280.00 | 13.0
--   Estacionamento |  40.00 |  1.9
--   Frigobar      |  50.00 |  2.3
--   Lavanderia    |  45.00 |  2.1
-- Total = 2155.00
WITH receita_servico AS (
    SELECT s.id_servico,
           s.nome_servico,
           COALESCE(SUM(cs.valor_total_item), 0) AS receita
    FROM Servico s
    LEFT JOIN Consumo_Servico cs ON cs.id_servico = s.id_servico
    GROUP BY s.id_servico, s.nome_servico
)
SELECT nome_servico,
       receita,
       ROUND(100.0 * receita / NULLIF(SUM(receita) OVER (), 0), 1) AS percentual
FROM receita_servico
ORDER BY receita DESC, nome_servico;

-- ---------------------------------------------------------------------------
-- @Q08 · Última estadia concluída de cada hóspede (JOIN + ROW_NUMBER)
-- Pergunta: Para cada hóspede, qual foi a estadia concluída mais recente
--   (quarto, datas e valor) e há quantos dias ela terminou?
-- Desempate: maior id_reserva. Hóspede sem CHECK-OUT não aparece.
-- Fronteira: hóspede com uma estadia; duas estadias no mesmo dia de saída; sem estadia.
-- Resultado esperado (calculado à mão com 02_inserts.sql):
--   João Pedro Vasconcelos | 201 | 2026-09-24 | 2026-09-28 | 2420.00 | X dias
--   Carlos Eduardo Menezes | 102 | 2026-10-09 | 2026-10-12 |  600.00 | X dias
--   Ana Beatriz Souza Lima | 101 | 2026-10-15 | 2026-10-18 |  470.00 | X dias
--   Fernanda Rocha Almeida | 202 | 2026-10-05 | 2026-10-09 | 1200.00 | X dias
--   Mariana Costa Ferreira | 102 | 2026-10-26 | 2026-10-29 |  800.00 | X dias
--   Ricardo Alves Teixeira | 201 | 2026-10-22 | 2026-10-24 |  800.00 | X dias
--   Luciana Prado Nogueira | 101 | 2026-11-10 | 2026-11-12 |  400.00 | X dias
SELECT t.nome_completo,
       q.numero_quarto,
       c.nome_categoria,
       r.data_entrada_prevista,
       r.data_saida_prevista,
       r.valor_final_pago,
       (CURRENT_DATE - r.data_saida_prevista) AS dias_desde_fim
FROM (
    SELECT h.nome_completo,
           r.id_reserva,
           r.id_quarto,
           r.data_entrada_prevista,
           r.data_saida_prevista,
           r.valor_final_pago,
           ROW_NUMBER() OVER (PARTITION BY h.id_hospede
                              ORDER BY r.data_saida_prevista DESC, r.id_reserva DESC) AS rn
    FROM Hospede h
    JOIN Reserva r ON r.id_hospede = h.id_hospede
    WHERE r.status_reserva = 'CHECK-OUT'
) t
JOIN Quarto q ON q.id_quarto = t.id_quarto
JOIN Categoria_Quarto c ON c.id_categoria = q.id_categoria
WHERE t.rn = 1
ORDER BY t.data_saida_prevista DESC, t.nome_completo;

-- ---------------------------------------------------------------------------
-- @Q09 · Hóspedes que consumiram TODOS os serviços (divisão relacional / NOT EXISTS duplo)
-- Pergunta: Quais hóspedes já consumiram todos os serviços do catálogo?
-- Como não há coluna 'categoria' em Servico, considera-se TODOS os serviços cadastrados.
-- Fronteira: hóspede que usou todos menos um (não entra); serviço nunca consumido (resultado vazio).
-- Resultado esperado (calculado à mão com 02_inserts.sql): 0 linhas (ninguém usou todos os 6 serviços)
SELECT h.id_hospede, h.nome_completo
FROM Hospede h
WHERE EXISTS (SELECT 1 FROM Servico)
  AND NOT EXISTS (
      SELECT 1
      FROM Servico s
      WHERE NOT EXISTS (
          SELECT 1
          FROM Consumo_Servico cs
          JOIN Reserva r ON r.id_reserva = cs.id_reserva
          WHERE r.id_hospede = h.id_hospede
            AND cs.id_servico = s.id_servico
      )
  )
ORDER BY h.nome_completo;

-- ---------------------------------------------------------------------------
-- @Q10 · Reservas e receita por categoria e situação, com subtotais (JOIN + ROLLUP)
-- Pergunta: Quantas reservas e quanta receita por categoria de quarto e situação
--   (CHECK-OUT, CANCELADA, NO-SHOW), com subtotal por categoria e total geral?
-- Receita: CHECK-OUT = valor_final_pago; CANCELADA/NO-SHOW = taxa_multa_aplicada de Cancelamento.
-- GROUPING() distingue subtotal (por categoria) e total geral.
-- Fronteira: categoria sem canceladas (linha some, subtotal certo); total = soma dos subtotais.
-- Resultado esperado (calculado à mão com 02_inserts.sql):
--   Standard    | CHECK-OUT    | 4 |  2000.00
--   Standard    | CANCELADA    | 1 |   100.00
--   Standard    | NO-SHOW      | 0 |     0.00
--   Standard    | SUBTOTAL     | 5 |  2100.00
--   Superior    | CHECK-OUT    | 3 |  2700.00
--   Superior    | CANCELADA    | 1 |   150.00
--   Superior    | NO-SHOW      | 0 |     0.00
--   Superior    | SUBTOTAL     | 4 |  2850.00
--   Suíte       | CHECK-OUT    | 2 |  3500.00
--   Suíte       | CANCELADA    | 1 |   750.00
--   Suíte       | NO-SHOW      | 0 |     0.00
--   Suíte       | SUBTOTAL     | 3 |  4250.00
--   TOTAL GERAL |              |12 |  9200.00
SELECT CASE WHEN GROUPING(c.nome_categoria) = 1 THEN 'TOTAL GERAL' ELSE c.nome_categoria END AS categoria_quarto,
       CASE
           WHEN GROUPING(c.nome_categoria) = 1 THEN ''
           WHEN GROUPING(r.status_reserva) = 1 THEN 'SUBTOTAL'
           ELSE r.status_reserva
       END AS situacao,
       COUNT(*) AS reservas,
       SUM(
           CASE r.status_reserva
               WHEN 'CHECK-OUT' THEN r.valor_final_pago
               WHEN 'CANCELADA' THEN COALESCE(can.taxa_multa_aplicada, 0)
               WHEN 'NO-SHOW'   THEN COALESCE(can.taxa_multa_aplicada, 0)
               ELSE 0
           END
       ) AS receita
FROM Reserva r
JOIN Quarto q ON q.id_quarto = r.id_quarto
JOIN Categoria_Quarto c ON c.id_categoria = q.id_categoria
LEFT JOIN Cancelamento can ON can.id_reserva = r.id_reserva
WHERE r.status_reserva IN ('CHECK-OUT', 'CANCELADA', 'NO-SHOW')
GROUP BY ROLLUP (c.nome_categoria, r.status_reserva)
ORDER BY GROUPING(c.nome_categoria), c.nome_categoria, GROUPING(r.status_reserva), r.status_reserva;
