-- Hotel Host - PostgreSQL 17 - performance/medir_antes_depois.sql
-- SQL puro (sem comandos do psql): copie TUDO, cole no Query Tool do pgAdmin e execute uma vez (F5).
-- Tambem roda no psql (-f) e pode ser lido por uma aplicacao. So ASCII de proposito.
--
-- O que faz, na ordem: mede 3 consultas ANTES dos indices (5 execucoes cada), cria os 3 indices de
-- postgresql/04_indices.sql no schema perf_test, atualiza as estatisticas e mede DEPOIS (5 execucoes cada).
-- O resultado e UMA grade (coluna "texto"): resumo com a mediana do Execution Time, e logo abaixo o texto REAL de cada plano.
-- Para o performance/explain_antes_depois.txt: clique na coluna, Ctrl+A, Ctrl+C e cole no arquivo.
-- Nada aqui e inventado: tudo sai do EXPLAIN (ANALYZE, BUFFERS) executado neste banco.
--
-- PRE-REQUISITO: performance/carga_massa.sql ja executado (cria e popula o schema perf_test).
-- Roda UMA vez por carga: se rodar de novo, o CREATE INDEX falha (indice ja existe) e tudo e desfeito.
-- Para medir do zero outra vez: recrie o banco (docker compose down -v e up) e rode carga_massa.sql de novo.

-- 0) Confere o pre-requisito.
DO $$
BEGIN
    IF to_regclass('perf_test.reserva') IS NULL OR to_regclass('perf_test.consumo_servico') IS NULL THEN
        RAISE EXCEPTION 'Rode antes o performance/carga_massa.sql (schema perf_test nao encontrado).';
    END IF;
END
$$;

-- 1) Tabela de resultados e funcao que mede (guarda cada linha do plano).
CREATE TABLE IF NOT EXISTS perf_test.explain_resultados (
    id          SERIAL PRIMARY KEY,
    fase        TEXT    NOT NULL,
    consulta    TEXT    NOT NULL,
    execucao    INTEGER NOT NULL,
    linha_plano TEXT    NOT NULL
);

CREATE OR REPLACE FUNCTION perf_test.medir_plano(p_fase TEXT, p_consulta TEXT, p_sql TEXT, p_repeticoes INTEGER DEFAULT 5)
RETURNS VOID
LANGUAGE plpgsql AS $fn$
DECLARE
    i INTEGER;
    r RECORD;
BEGIN
    FOR i IN 1..p_repeticoes LOOP
        FOR r IN EXECUTE 'EXPLAIN (ANALYZE, BUFFERS) ' || p_sql LOOP
            INSERT INTO perf_test.explain_resultados (fase, consulta, execucao, linha_plano)
            VALUES (p_fase, p_consulta, i, r."QUERY PLAN");
        END LOOP;
    END LOOP;
END;
$fn$;

-- 2) ANTES dos indices (so as PKs e UNIQUEs existem).
-- A: FK reserva.id_hospede (JOIN): reservas de um hospede.
SELECT perf_test.medir_plano('ANTES', 'A', $q$
SELECT h.nome_completo, r.id_reserva, r.data_entrada_prevista, r.status_reserva
  FROM perf_test.reserva r
  JOIN perf_test.hospede h ON h.id_hospede = r.id_hospede
 WHERE r.id_hospede = 4242
 ORDER BY r.data_entrada_prevista
$q$);

-- B: FK consumo_servico.id_reserva (JOIN): consumos de uma reserva (a mesma reserva antes e depois).
SELECT perf_test.medir_plano('ANTES', 'B', format($q$
SELECT s.nome_servico, c.quantidade, c.valor_total_item
  FROM perf_test.consumo_servico c
  JOIN perf_test.servico s ON s.id_servico = c.id_servico
 WHERE c.id_reserva = %s
$q$, (SELECT id_reserva FROM perf_test.consumo_servico ORDER BY id_consumo OFFSET 100000 LIMIT 1)));

-- C: busca por status e data de entrada: chegadas dos proximos 7 dias.
SELECT perf_test.medir_plano('ANTES', 'C', $q$
SELECT r.id_reserva, r.id_hospede, r.id_quarto, r.data_entrada_prevista
  FROM perf_test.reserva r
 WHERE r.status_reserva = 'CONFIRMADA'
   AND r.data_entrada_prevista BETWEEN CURRENT_DATE AND CURRENT_DATE + 7
 ORDER BY r.data_entrada_prevista
$q$);

-- 3) Os 3 indices do projeto (mesmos de postgresql/04_indices.sql), aplicados ao schema perf_test.
CREATE INDEX idx_reserva_hospede        ON perf_test.reserva (id_hospede);
CREATE INDEX idx_consumo_reserva        ON perf_test.consumo_servico (id_reserva);
CREATE INDEX idx_reserva_status_entrada ON perf_test.reserva (status_reserva, data_entrada_prevista);

ANALYZE perf_test.reserva;
ANALYZE perf_test.consumo_servico;

-- 4) DEPOIS dos indices (mesmas consultas).
SELECT perf_test.medir_plano('DEPOIS', 'A', $q$
SELECT h.nome_completo, r.id_reserva, r.data_entrada_prevista, r.status_reserva
  FROM perf_test.reserva r
  JOIN perf_test.hospede h ON h.id_hospede = r.id_hospede
 WHERE r.id_hospede = 4242
 ORDER BY r.data_entrada_prevista
$q$);

SELECT perf_test.medir_plano('DEPOIS', 'B', format($q$
SELECT s.nome_servico, c.quantidade, c.valor_total_item
  FROM perf_test.consumo_servico c
  JOIN perf_test.servico s ON s.id_servico = c.id_servico
 WHERE c.id_reserva = %s
$q$, (SELECT id_reserva FROM perf_test.consumo_servico ORDER BY id_consumo OFFSET 100000 LIMIT 1)));

SELECT perf_test.medir_plano('DEPOIS', 'C', $q$
SELECT r.id_reserva, r.id_hospede, r.id_quarto, r.data_entrada_prevista
  FROM perf_test.reserva r
 WHERE r.status_reserva = 'CONFIRMADA'
   AND r.data_entrada_prevista BETWEEN CURRENT_DATE AND CURRENT_DATE + 7
 ORDER BY r.data_entrada_prevista
$q$);

-- 5) RESULTADO (esta e a unica grade que o pgAdmin mostra): ambiente, resumo com medianas e o texto dos planos.
WITH tempos AS (
    SELECT fase, consulta,
           substring(linha_plano FROM 'Execution Time: ([0-9.]+) ms')::numeric AS ms
      FROM perf_test.explain_resultados
     WHERE linha_plano LIKE 'Execution Time:%'
),
resumo AS (
    SELECT consulta,
           percentile_cont(0.5) WITHIN GROUP (ORDER BY ms) FILTER (WHERE fase = 'ANTES')  AS ms_antes,
           percentile_cont(0.5) WITHIN GROUP (ORDER BY ms) FILTER (WHERE fase = 'DEPOIS') AS ms_depois
      FROM tempos
     GROUP BY consulta
)
SELECT texto
  FROM (
        SELECT 0 AS grp, 0 AS ord, 'AMBIENTE: ' || version() AS texto
        UNION ALL
        SELECT 0, 1, 'LINHAS: reserva=' || (SELECT count(*) FROM perf_test.reserva)
                  || ' | consumo_servico=' || (SELECT count(*) FROM perf_test.consumo_servico)
                  || ' | hospede=' || (SELECT count(*) FROM perf_test.hospede)
        UNION ALL
        SELECT 0, 2, 'INDICES EM perf_test: '
                  || (SELECT string_agg(indexname, ', ' ORDER BY indexname) FROM pg_indexes WHERE schemaname = 'perf_test')
        UNION ALL
        SELECT 1, row_number() OVER (ORDER BY consulta),
               'RESUMO consulta ' || consulta
               || ' | mediana ANTES ' || round(ms_antes::numeric, 3) || ' ms'
               || ' | mediana DEPOIS ' || round(ms_depois::numeric, 3) || ' ms'
               || ' | ganho ' || round((ms_antes / NULLIF(ms_depois, 0))::numeric, 1) || 'x'
          FROM resumo
        UNION ALL
        SELECT 2, id, fase || ' | consulta ' || consulta || ' | execucao ' || execucao || ' | ' || linha_plano
          FROM perf_test.explain_resultados
       ) saida
 ORDER BY grp, ord;
