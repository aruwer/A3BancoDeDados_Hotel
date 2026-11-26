-- Hotel Host | PostgreSQL 17 | as 10 consultas de negócio (perguntas_de_negocio.md).
-- Este arquivo é UMA instrução SQL: pode ser colada inteira no Query Tool do pgAdmin (F5).
-- Cada consulta devolve uma linha 'linhas: N' (ordem 0) e depois uma linha por resultado,
-- em JSON (colunas: consulta, ordem, linha). Cada Qnn aparece duas vezes: a primeira só conta
-- as linhas, a segunda traz o conteúdo; o corpo da consulta é idêntico nas duas.
-- Datas relativas a CURRENT_DATE. Os resultados esperados (calculados à mão a partir de
-- 02_inserts.sql) estão em tests/unit/test_ct_u_consultas.py.
-- Técnicas exigidas: JOIN (Q01,Q02,Q03,Q06,Q07,Q08,Q10), window (Q03,Q05,Q07,Q08),
-- agregação (Q01,Q03,Q06,Q07,Q10), NOT EXISTS (Q04,Q09); extras: ROLLUP (Q10), divisão relacional (Q09).

SELECT consulta, ordem, linha
  FROM (
-- @Q01 Objetivo: Receita de diárias por tipo de quarto nas estadias concluídas (CHECK-OUT), já com o desconto de fidelidade, só tipos com receita > 0.
-- @Q01 Técnica: JOIN + GROUP BY + HAVING
SELECT 'Q01' AS consulta, 0::bigint AS ordem, 'linhas: ' || count(*) AS linha
  FROM (
SELECT c.nome_categoria,
       COUNT(*) AS estadias_concluidas,
       ROUND(
           SUM(r.valor_total_bruto * (1 - COALESCE(r.percentual_desconto, 0) / 100)),
           2
       ) AS receita_diarias
FROM reserva r
JOIN quarto q ON q.id_quarto = r.id_quarto
JOIN categoria_quarto c ON c.id_categoria = q.id_categoria
WHERE r.status_reserva = 'CHECK-OUT'
GROUP BY c.id_categoria, c.nome_categoria
HAVING SUM(r.valor_total_bruto * (1 - COALESCE(r.percentual_desconto, 0) / 100)) > 0
ORDER BY receita_diarias DESC
  ) c
  UNION ALL
SELECT 'Q01', row_number() OVER (), to_json(q)::text
  FROM (
SELECT c.nome_categoria,
       COUNT(*) AS estadias_concluidas,
       ROUND(
           SUM(r.valor_total_bruto * (1 - COALESCE(r.percentual_desconto, 0) / 100)),
           2
       ) AS receita_diarias
FROM reserva r
JOIN quarto q ON q.id_quarto = r.id_quarto
JOIN categoria_quarto c ON c.id_categoria = q.id_categoria
WHERE r.status_reserva = 'CHECK-OUT'
GROUP BY c.id_categoria, c.nome_categoria
HAVING SUM(r.valor_total_bruto * (1 - COALESCE(r.percentual_desconto, 0) / 100)) > 0
ORDER BY receita_diarias DESC
  ) q
  UNION ALL
-- @Q02 Objetivo: Chegadas dos próximos 7 dias: reservas CONFIRMADAS com entrada de hoje até hoje+7, com hóspede, quarto e noites.
-- @Q02 Técnica: JOIN (reserva, hóspede, quarto, categoria)
SELECT 'Q02' AS consulta, 0::bigint AS ordem, 'linhas: ' || count(*) AS linha
  FROM (
SELECT r.id_reserva,
       h.nome_completo,
       q.numero_quarto,
       c.nome_categoria,
       r.data_entrada_prevista,
       (r.data_saida_prevista - r.data_entrada_prevista) AS noites
FROM reserva r
JOIN hospede h ON h.id_hospede = r.id_hospede
JOIN quarto q ON q.id_quarto = r.id_quarto
JOIN categoria_quarto c ON c.id_categoria = q.id_categoria
WHERE r.status_reserva = 'CONFIRMADA'
  AND r.data_entrada_prevista BETWEEN CURRENT_DATE AND CURRENT_DATE + 7
ORDER BY r.data_entrada_prevista, q.numero_quarto
  ) c
  UNION ALL
SELECT 'Q02', row_number() OVER (), to_json(q)::text
  FROM (
SELECT r.id_reserva,
       h.nome_completo,
       q.numero_quarto,
       c.nome_categoria,
       r.data_entrada_prevista,
       (r.data_saida_prevista - r.data_entrada_prevista) AS noites
FROM reserva r
JOIN hospede h ON h.id_hospede = r.id_hospede
JOIN quarto q ON q.id_quarto = r.id_quarto
JOIN categoria_quarto c ON c.id_categoria = q.id_categoria
WHERE r.status_reserva = 'CONFIRMADA'
  AND r.data_entrada_prevista BETWEEN CURRENT_DATE AND CURRENT_DATE + 7
ORDER BY r.data_entrada_prevista, q.numero_quarto
  ) q
  UNION ALL
-- @Q03 Objetivo: Ranking dos hóspedes que mais gastaram, somando o valor final das estadias CHECK-OUT.
-- @Q03 Técnica: JOIN + agregação + window RANK()
SELECT 'Q03' AS consulta, 0::bigint AS ordem, 'linhas: ' || count(*) AS linha
  FROM (
SELECT posicao,
       nome_completo,
       total_gasto,
       estadias
FROM (
    SELECT h.nome_completo,
           SUM(r.valor_final_pago) AS total_gasto,
           COUNT(*) AS estadias,
           RANK() OVER (ORDER BY SUM(r.valor_final_pago) DESC) AS posicao
    FROM hospede h
    JOIN reserva r ON r.id_hospede = h.id_hospede
    WHERE r.status_reserva = 'CHECK-OUT'
    GROUP BY h.id_hospede, h.nome_completo
    HAVING SUM(r.valor_final_pago) > 0
) ranking
WHERE posicao <= 5
ORDER BY posicao, nome_completo
  ) c
  UNION ALL
SELECT 'Q03', row_number() OVER (), to_json(q)::text
  FROM (
SELECT posicao,
       nome_completo,
       total_gasto,
       estadias
FROM (
    SELECT h.nome_completo,
           SUM(r.valor_final_pago) AS total_gasto,
           COUNT(*) AS estadias,
           RANK() OVER (ORDER BY SUM(r.valor_final_pago) DESC) AS posicao
    FROM hospede h
    JOIN reserva r ON r.id_hospede = h.id_hospede
    WHERE r.status_reserva = 'CHECK-OUT'
    GROUP BY h.id_hospede, h.nome_completo
    HAVING SUM(r.valor_final_pago) > 0
) ranking
WHERE posicao <= 5
ORDER BY posicao, nome_completo
  ) q
  UNION ALL
-- @Q04 Objetivo: Quartos disponíveis no período hoje+8 a hoje+10: sem manutenção e sem reserva que se sobreponha ([entrada, saída); CANCELADA e NO-SHOW não bloqueiam).
-- @Q04 Técnica: NOT EXISTS (anti-join)
SELECT 'Q04' AS consulta, 0::bigint AS ordem, 'linhas: ' || count(*) AS linha
  FROM (
WITH periodo AS (
    SELECT CURRENT_DATE + 8  AS x,
           CURRENT_DATE + 10 AS y
)
SELECT q.numero_quarto,
       c.nome_categoria,
       q.andar
FROM quarto q
JOIN categoria_quarto c ON c.id_categoria = q.id_categoria
CROSS JOIN periodo p
WHERE q.status_quarto <> 'MANUTENCAO'
  AND NOT EXISTS (
      SELECT 1
      FROM reserva r
      WHERE r.id_quarto = q.id_quarto
        AND r.status_reserva NOT IN ('CANCELADA', 'NO-SHOW')
        AND r.data_entrada_prevista < p.y
        AND r.data_saida_prevista > p.x
  )
ORDER BY q.numero_quarto
  ) c
  UNION ALL
SELECT 'Q04', row_number() OVER (), to_json(q)::text
  FROM (
WITH periodo AS (
    SELECT CURRENT_DATE + 8  AS x,
           CURRENT_DATE + 10 AS y
)
SELECT q.numero_quarto,
       c.nome_categoria,
       q.andar
FROM quarto q
JOIN categoria_quarto c ON c.id_categoria = q.id_categoria
CROSS JOIN periodo p
WHERE q.status_quarto <> 'MANUTENCAO'
  AND NOT EXISTS (
      SELECT 1
      FROM reserva r
      WHERE r.id_quarto = q.id_quarto
        AND r.status_reserva NOT IN ('CANCELADA', 'NO-SHOW')
        AND r.data_entrada_prevista < p.y
        AND r.data_saida_prevista > p.x
  )
ORDER BY q.numero_quarto
  ) q
  UNION ALL
-- @Q05 Objetivo: Receita acumulada mês a mês (mês da saída), reiniciando a cada ano.
-- @Q05 Técnica: window SUM() OVER (PARTITION BY ano ORDER BY mês)
SELECT 'Q05' AS consulta, 0::bigint AS ordem, 'linhas: ' || count(*) AS linha
  FROM (
SELECT TO_CHAR(mes, 'YYYY-MM') AS mes,
       receita_mes,
       SUM(receita_mes) OVER (
           PARTITION BY EXTRACT(YEAR FROM mes)
           ORDER BY mes
       ) AS receita_acumulada
FROM (
    SELECT DATE_TRUNC('month', r.data_saida_prevista)::date AS mes,
           SUM(r.valor_final_pago) AS receita_mes
    FROM reserva r
    WHERE r.status_reserva = 'CHECK-OUT'
    GROUP BY DATE_TRUNC('month', r.data_saida_prevista)::date
    HAVING SUM(r.valor_final_pago) > 0
) mensal
ORDER BY mes
  ) c
  UNION ALL
SELECT 'Q05', row_number() OVER (), to_json(q)::text
  FROM (
SELECT TO_CHAR(mes, 'YYYY-MM') AS mes,
       receita_mes,
       SUM(receita_mes) OVER (
           PARTITION BY EXTRACT(YEAR FROM mes)
           ORDER BY mes
       ) AS receita_acumulada
FROM (
    SELECT DATE_TRUNC('month', r.data_saida_prevista)::date AS mes,
           SUM(r.valor_final_pago) AS receita_mes
    FROM reserva r
    WHERE r.status_reserva = 'CHECK-OUT'
    GROUP BY DATE_TRUNC('month', r.data_saida_prevista)::date
    HAVING SUM(r.valor_final_pago) > 0
) mensal
ORDER BY mes
  ) q
  UNION ALL
-- @Q06 Objetivo: Tipos de quarto com taxa de cancelamento acima de 20% (CANCELADA sobre todas as reservas do tipo; NO-SHOW não conta como cancelamento).
-- @Q06 Técnica: JOIN + GROUP BY + HAVING + FILTER
SELECT 'Q06' AS consulta, 0::bigint AS ordem, 'linhas: ' || count(*) AS linha
  FROM (
SELECT c.nome_categoria,
       COUNT(*) AS total_reservas,
       COUNT(*) FILTER (WHERE r.status_reserva = 'CANCELADA') AS canceladas,
       ROUND(100.0 * COUNT(*) FILTER (WHERE r.status_reserva = 'CANCELADA') / COUNT(*), 1) AS taxa_cancelamento
FROM Reserva r
JOIN Quarto q ON q.id_quarto = r.id_quarto
JOIN Categoria_Quarto c ON c.id_categoria = q.id_categoria
GROUP BY c.id_categoria, c.nome_categoria
HAVING 100.0 * COUNT(*) FILTER (WHERE r.status_reserva = 'CANCELADA') / COUNT(*) > 20
ORDER BY taxa_cancelamento DESC, c.nome_categoria
  ) c
  UNION ALL
SELECT 'Q06', row_number() OVER (), to_json(q)::text
  FROM (
SELECT c.nome_categoria,
       COUNT(*) AS total_reservas,
       COUNT(*) FILTER (WHERE r.status_reserva = 'CANCELADA') AS canceladas,
       ROUND(100.0 * COUNT(*) FILTER (WHERE r.status_reserva = 'CANCELADA') / COUNT(*), 1) AS taxa_cancelamento
FROM Reserva r
JOIN Quarto q ON q.id_quarto = r.id_quarto
JOIN Categoria_Quarto c ON c.id_categoria = q.id_categoria
GROUP BY c.id_categoria, c.nome_categoria
HAVING 100.0 * COUNT(*) FILTER (WHERE r.status_reserva = 'CANCELADA') / COUNT(*) > 20
ORDER BY taxa_cancelamento DESC, c.nome_categoria
  ) q
  UNION ALL
-- @Q07 Objetivo: Participação de cada serviço na receita de consumo, em percentual do total.
-- @Q07 Técnica: JOIN + window SUM() OVER () sobre agregação
SELECT 'Q07' AS consulta, 0::bigint AS ordem, 'linhas: ' || count(*) AS linha
  FROM (
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
ORDER BY receita DESC, nome_servico
  ) c
  UNION ALL
SELECT 'Q07', row_number() OVER (), to_json(q)::text
  FROM (
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
ORDER BY receita DESC, nome_servico
  ) q
  UNION ALL
-- @Q08 Objetivo: Última estadia concluída (CHECK-OUT) de cada hóspede, com os dias desde a saída; hóspede sem estadia concluída não aparece.
-- @Q08 Técnica: JOIN + window ROW_NUMBER() OVER (PARTITION BY hóspede)
SELECT 'Q08' AS consulta, 0::bigint AS ordem, 'linhas: ' || count(*) AS linha
  FROM (
SELECT t.nome_completo,
       q.numero_quarto,
       c.nome_categoria,
       t.data_entrada_prevista,
       t.data_saida_prevista,
       t.valor_final_pago,
       (CURRENT_DATE - t.data_saida_prevista) AS dias_desde_fim
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
ORDER BY t.data_saida_prevista DESC, t.nome_completo
  ) c
  UNION ALL
SELECT 'Q08', row_number() OVER (), to_json(q)::text
  FROM (
SELECT t.nome_completo,
       q.numero_quarto,
       c.nome_categoria,
       t.data_entrada_prevista,
       t.data_saida_prevista,
       t.valor_final_pago,
       (CURRENT_DATE - t.data_saida_prevista) AS dias_desde_fim
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
ORDER BY t.data_saida_prevista DESC, t.nome_completo
  ) q
  UNION ALL
-- @Q09 Objetivo: Hóspedes que já consumiram todos os serviços cadastrados (divisão relacional). Hoje considera todos os serviços: o DDL não tem SERVICO.categoria para filtrar só os Extras.
-- @Q09 Técnica: NOT EXISTS duplo (divisão relacional)
SELECT 'Q09' AS consulta, 0::bigint AS ordem, 'linhas: ' || count(*) AS linha
  FROM (
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
ORDER BY h.nome_completo
  ) c
  UNION ALL
SELECT 'Q09', row_number() OVER (), to_json(q)::text
  FROM (
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
ORDER BY h.nome_completo
  ) q
  UNION ALL
-- @Q10 Objetivo: Reservas e receita por tipo de quarto e situação (CHECK-OUT, CANCELADA, NO-SHOW), com subtotais por tipo e total geral. Receita: valor final nas CHECK-OUT e multa nas demais.
-- @Q10 Técnica: JOIN + GROUP BY ROLLUP
SELECT 'Q10' AS consulta, 0::bigint AS ordem, 'linhas: ' || count(*) AS linha
  FROM (
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
ORDER BY GROUPING(c.nome_categoria), c.nome_categoria, GROUPING(r.status_reserva), r.status_reserva
  ) c
  UNION ALL
SELECT 'Q10', row_number() OVER (), to_json(q)::text
  FROM (
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
ORDER BY GROUPING(c.nome_categoria), c.nome_categoria, GROUPING(r.status_reserva), r.status_reserva
  ) q
  ) todas
 ORDER BY consulta, ordem;
