-- GERADO por python/gerar_consultas_pgadmin.py a partir de postgresql/03_consultas.sql. NAO EDITE A MAO.
-- Copie TUDO, cole no Query Tool do pgAdmin e execute uma vez (F5): as consultas saem numa grade so.
-- Cada consulta tem uma linha 'linhas: N' (ordem 0) e depois uma linha por resultado (texto JSON, na ordem da consulta).
-- Compare com os 'Resultado esperado' dos comentarios de 03_consultas.sql.
-- Consulta que devolve 0 linhas aparece so com 'linhas: 0'.

SELECT consulta, ordem, linha
  FROM (
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
