-- Hotel Host - PostgreSQL 17 - performance/medir_antes_depois.sql
-- Gera performance/explain_antes_depois.txt com o texto REAL do EXPLAIN (ANALYZE, BUFFERS), antes e depois dos 3 indices.
-- Nenhum numero deste arquivo e inventado: tudo sai da execucao no PostgreSQL 17 do compose.
-- So ASCII de proposito. Pre-requisito: performance/carga_massa.sql ja executado.
--
-- Rodar a partir da raiz do repositorio (funciona em PowerShell, cmd e bash):
--   docker compose cp performance/medir_antes_depois.sql postgres:/tmp/medir.sql
--   docker compose exec postgres psql -U hotel -d hotel -v ON_ERROR_STOP=1 -f /tmp/medir.sql
--   docker compose cp postgres:/tmp/explain_antes_depois.txt performance/explain_antes_depois.txt
--
-- Cada consulta roda 5 vezes antes e 5 vezes depois. A primeira de cada serie e a mais fria (cache); no README use a mediana
-- dos Execution Time de cada serie e diga as condicoes da medicao (maquina, conteiner, linhas, repeticoes).

\set ON_ERROR_STOP on
\pset pager off
\o /tmp/explain_antes_depois.txt
SET search_path TO perf_test;

\qecho ==================================================================
\qecho Hotel Host - planos de execucao antes e depois dos indices
\qecho ==================================================================
SELECT version() AS versao, now() AS executado_em;
SELECT 'hospede' AS tabela, COUNT(*) AS linhas FROM hospede
UNION ALL SELECT 'servico', COUNT(*) FROM servico
UNION ALL SELECT 'reserva', COUNT(*) FROM reserva
UNION ALL SELECT 'consumo_reserva', COUNT(*) FROM consumo_reserva;
\qecho Indices existentes ANTES (so as PKs):
SELECT tablename, indexname FROM pg_indexes WHERE schemaname = 'perf_test' ORDER BY tablename, indexname;

\qecho
\qecho ##################################################################
\qecho ANTES DOS INDICES
\qecho ##################################################################
\qecho
\qecho ------ ANTES | consulta A | FK reserva.hospede_id (JOIN): reservas de um hospede | execucao 1 de 5 ------
EXPLAIN (ANALYZE, BUFFERS)
SELECT h.nome, r.reserva_id, r.data_entrada, r.status
  FROM reserva r
  JOIN hospede h ON h.hospede_id = r.hospede_id
 WHERE r.hospede_id = 4242
 ORDER BY r.data_entrada;

\qecho
\qecho ------ ANTES | consulta A | FK reserva.hospede_id (JOIN): reservas de um hospede | execucao 2 de 5 ------
EXPLAIN (ANALYZE, BUFFERS)
SELECT h.nome, r.reserva_id, r.data_entrada, r.status
  FROM reserva r
  JOIN hospede h ON h.hospede_id = r.hospede_id
 WHERE r.hospede_id = 4242
 ORDER BY r.data_entrada;

\qecho
\qecho ------ ANTES | consulta A | FK reserva.hospede_id (JOIN): reservas de um hospede | execucao 3 de 5 ------
EXPLAIN (ANALYZE, BUFFERS)
SELECT h.nome, r.reserva_id, r.data_entrada, r.status
  FROM reserva r
  JOIN hospede h ON h.hospede_id = r.hospede_id
 WHERE r.hospede_id = 4242
 ORDER BY r.data_entrada;

\qecho
\qecho ------ ANTES | consulta A | FK reserva.hospede_id (JOIN): reservas de um hospede | execucao 4 de 5 ------
EXPLAIN (ANALYZE, BUFFERS)
SELECT h.nome, r.reserva_id, r.data_entrada, r.status
  FROM reserva r
  JOIN hospede h ON h.hospede_id = r.hospede_id
 WHERE r.hospede_id = 4242
 ORDER BY r.data_entrada;

\qecho
\qecho ------ ANTES | consulta A | FK reserva.hospede_id (JOIN): reservas de um hospede | execucao 5 de 5 ------
EXPLAIN (ANALYZE, BUFFERS)
SELECT h.nome, r.reserva_id, r.data_entrada, r.status
  FROM reserva r
  JOIN hospede h ON h.hospede_id = r.hospede_id
 WHERE r.hospede_id = 4242
 ORDER BY r.data_entrada;

\qecho
\qecho ------ ANTES | consulta B | FK consumo_reserva.reserva_id (JOIN): consumos de uma reserva | execucao 1 de 5 ------
EXPLAIN (ANALYZE, BUFFERS)
SELECT s.nome, c.quantidade, c.preco_unitario
  FROM consumo_reserva c
  JOIN servico s ON s.servico_id = c.servico_id
 WHERE c.reserva_id = 123456;

\qecho
\qecho ------ ANTES | consulta B | FK consumo_reserva.reserva_id (JOIN): consumos de uma reserva | execucao 2 de 5 ------
EXPLAIN (ANALYZE, BUFFERS)
SELECT s.nome, c.quantidade, c.preco_unitario
  FROM consumo_reserva c
  JOIN servico s ON s.servico_id = c.servico_id
 WHERE c.reserva_id = 123456;

\qecho
\qecho ------ ANTES | consulta B | FK consumo_reserva.reserva_id (JOIN): consumos de uma reserva | execucao 3 de 5 ------
EXPLAIN (ANALYZE, BUFFERS)
SELECT s.nome, c.quantidade, c.preco_unitario
  FROM consumo_reserva c
  JOIN servico s ON s.servico_id = c.servico_id
 WHERE c.reserva_id = 123456;

\qecho
\qecho ------ ANTES | consulta B | FK consumo_reserva.reserva_id (JOIN): consumos de uma reserva | execucao 4 de 5 ------
EXPLAIN (ANALYZE, BUFFERS)
SELECT s.nome, c.quantidade, c.preco_unitario
  FROM consumo_reserva c
  JOIN servico s ON s.servico_id = c.servico_id
 WHERE c.reserva_id = 123456;

\qecho
\qecho ------ ANTES | consulta B | FK consumo_reserva.reserva_id (JOIN): consumos de uma reserva | execucao 5 de 5 ------
EXPLAIN (ANALYZE, BUFFERS)
SELECT s.nome, c.quantidade, c.preco_unitario
  FROM consumo_reserva c
  JOIN servico s ON s.servico_id = c.servico_id
 WHERE c.reserva_id = 123456;

\qecho
\qecho ------ ANTES | consulta C | Busca por status e data de entrada: chegadas dos proximos 7 dias | execucao 1 de 5 ------
EXPLAIN (ANALYZE, BUFFERS)
SELECT r.reserva_id, r.hospede_id, r.quarto_id, r.data_entrada
  FROM reserva r
 WHERE r.status = 'CONFIRMADA'
   AND r.data_entrada BETWEEN CURRENT_DATE AND CURRENT_DATE + 7
 ORDER BY r.data_entrada;

\qecho
\qecho ------ ANTES | consulta C | Busca por status e data de entrada: chegadas dos proximos 7 dias | execucao 2 de 5 ------
EXPLAIN (ANALYZE, BUFFERS)
SELECT r.reserva_id, r.hospede_id, r.quarto_id, r.data_entrada
  FROM reserva r
 WHERE r.status = 'CONFIRMADA'
   AND r.data_entrada BETWEEN CURRENT_DATE AND CURRENT_DATE + 7
 ORDER BY r.data_entrada;

\qecho
\qecho ------ ANTES | consulta C | Busca por status e data de entrada: chegadas dos proximos 7 dias | execucao 3 de 5 ------
EXPLAIN (ANALYZE, BUFFERS)
SELECT r.reserva_id, r.hospede_id, r.quarto_id, r.data_entrada
  FROM reserva r
 WHERE r.status = 'CONFIRMADA'
   AND r.data_entrada BETWEEN CURRENT_DATE AND CURRENT_DATE + 7
 ORDER BY r.data_entrada;

\qecho
\qecho ------ ANTES | consulta C | Busca por status e data de entrada: chegadas dos proximos 7 dias | execucao 4 de 5 ------
EXPLAIN (ANALYZE, BUFFERS)
SELECT r.reserva_id, r.hospede_id, r.quarto_id, r.data_entrada
  FROM reserva r
 WHERE r.status = 'CONFIRMADA'
   AND r.data_entrada BETWEEN CURRENT_DATE AND CURRENT_DATE + 7
 ORDER BY r.data_entrada;

\qecho
\qecho ------ ANTES | consulta C | Busca por status e data de entrada: chegadas dos proximos 7 dias | execucao 5 de 5 ------
EXPLAIN (ANALYZE, BUFFERS)
SELECT r.reserva_id, r.hospede_id, r.quarto_id, r.data_entrada
  FROM reserva r
 WHERE r.status = 'CONFIRMADA'
   AND r.data_entrada BETWEEN CURRENT_DATE AND CURRENT_DATE + 7
 ORDER BY r.data_entrada;

-- Cria os 3 indices de postgresql/04_indices.sql no schema perf_test (search_path) e atualiza as estatisticas.
\qecho
\qecho ##################################################################
\qecho CRIANDO OS 3 INDICES (postgresql/04_indices.sql)
\qecho ##################################################################
\i /scripts/postgresql/04_indices.sql
ANALYZE reserva;
ANALYZE consumo_reserva;
\qecho Indices existentes DEPOIS:
SELECT tablename, indexname FROM pg_indexes WHERE schemaname = 'perf_test' ORDER BY tablename, indexname;
\qecho
\qecho ##################################################################
\qecho DEPOIS DOS INDICES
\qecho ##################################################################
\qecho
\qecho ------ DEPOIS | consulta A | FK reserva.hospede_id (JOIN): reservas de um hospede | execucao 1 de 5 ------
EXPLAIN (ANALYZE, BUFFERS)
SELECT h.nome, r.reserva_id, r.data_entrada, r.status
  FROM reserva r
  JOIN hospede h ON h.hospede_id = r.hospede_id
 WHERE r.hospede_id = 4242
 ORDER BY r.data_entrada;

\qecho
\qecho ------ DEPOIS | consulta A | FK reserva.hospede_id (JOIN): reservas de um hospede | execucao 2 de 5 ------
EXPLAIN (ANALYZE, BUFFERS)
SELECT h.nome, r.reserva_id, r.data_entrada, r.status
  FROM reserva r
  JOIN hospede h ON h.hospede_id = r.hospede_id
 WHERE r.hospede_id = 4242
 ORDER BY r.data_entrada;

\qecho
\qecho ------ DEPOIS | consulta A | FK reserva.hospede_id (JOIN): reservas de um hospede | execucao 3 de 5 ------
EXPLAIN (ANALYZE, BUFFERS)
SELECT h.nome, r.reserva_id, r.data_entrada, r.status
  FROM reserva r
  JOIN hospede h ON h.hospede_id = r.hospede_id
 WHERE r.hospede_id = 4242
 ORDER BY r.data_entrada;

\qecho
\qecho ------ DEPOIS | consulta A | FK reserva.hospede_id (JOIN): reservas de um hospede | execucao 4 de 5 ------
EXPLAIN (ANALYZE, BUFFERS)
SELECT h.nome, r.reserva_id, r.data_entrada, r.status
  FROM reserva r
  JOIN hospede h ON h.hospede_id = r.hospede_id
 WHERE r.hospede_id = 4242
 ORDER BY r.data_entrada;

\qecho
\qecho ------ DEPOIS | consulta A | FK reserva.hospede_id (JOIN): reservas de um hospede | execucao 5 de 5 ------
EXPLAIN (ANALYZE, BUFFERS)
SELECT h.nome, r.reserva_id, r.data_entrada, r.status
  FROM reserva r
  JOIN hospede h ON h.hospede_id = r.hospede_id
 WHERE r.hospede_id = 4242
 ORDER BY r.data_entrada;

\qecho
\qecho ------ DEPOIS | consulta B | FK consumo_reserva.reserva_id (JOIN): consumos de uma reserva | execucao 1 de 5 ------
EXPLAIN (ANALYZE, BUFFERS)
SELECT s.nome, c.quantidade, c.preco_unitario
  FROM consumo_reserva c
  JOIN servico s ON s.servico_id = c.servico_id
 WHERE c.reserva_id = 123456;

\qecho
\qecho ------ DEPOIS | consulta B | FK consumo_reserva.reserva_id (JOIN): consumos de uma reserva | execucao 2 de 5 ------
EXPLAIN (ANALYZE, BUFFERS)
SELECT s.nome, c.quantidade, c.preco_unitario
  FROM consumo_reserva c
  JOIN servico s ON s.servico_id = c.servico_id
 WHERE c.reserva_id = 123456;

\qecho
\qecho ------ DEPOIS | consulta B | FK consumo_reserva.reserva_id (JOIN): consumos de uma reserva | execucao 3 de 5 ------
EXPLAIN (ANALYZE, BUFFERS)
SELECT s.nome, c.quantidade, c.preco_unitario
  FROM consumo_reserva c
  JOIN servico s ON s.servico_id = c.servico_id
 WHERE c.reserva_id = 123456;

\qecho
\qecho ------ DEPOIS | consulta B | FK consumo_reserva.reserva_id (JOIN): consumos de uma reserva | execucao 4 de 5 ------
EXPLAIN (ANALYZE, BUFFERS)
SELECT s.nome, c.quantidade, c.preco_unitario
  FROM consumo_reserva c
  JOIN servico s ON s.servico_id = c.servico_id
 WHERE c.reserva_id = 123456;

\qecho
\qecho ------ DEPOIS | consulta B | FK consumo_reserva.reserva_id (JOIN): consumos de uma reserva | execucao 5 de 5 ------
EXPLAIN (ANALYZE, BUFFERS)
SELECT s.nome, c.quantidade, c.preco_unitario
  FROM consumo_reserva c
  JOIN servico s ON s.servico_id = c.servico_id
 WHERE c.reserva_id = 123456;

\qecho
\qecho ------ DEPOIS | consulta C | Busca por status e data de entrada: chegadas dos proximos 7 dias | execucao 1 de 5 ------
EXPLAIN (ANALYZE, BUFFERS)
SELECT r.reserva_id, r.hospede_id, r.quarto_id, r.data_entrada
  FROM reserva r
 WHERE r.status = 'CONFIRMADA'
   AND r.data_entrada BETWEEN CURRENT_DATE AND CURRENT_DATE + 7
 ORDER BY r.data_entrada;

\qecho
\qecho ------ DEPOIS | consulta C | Busca por status e data de entrada: chegadas dos proximos 7 dias | execucao 2 de 5 ------
EXPLAIN (ANALYZE, BUFFERS)
SELECT r.reserva_id, r.hospede_id, r.quarto_id, r.data_entrada
  FROM reserva r
 WHERE r.status = 'CONFIRMADA'
   AND r.data_entrada BETWEEN CURRENT_DATE AND CURRENT_DATE + 7
 ORDER BY r.data_entrada;

\qecho
\qecho ------ DEPOIS | consulta C | Busca por status e data de entrada: chegadas dos proximos 7 dias | execucao 3 de 5 ------
EXPLAIN (ANALYZE, BUFFERS)
SELECT r.reserva_id, r.hospede_id, r.quarto_id, r.data_entrada
  FROM reserva r
 WHERE r.status = 'CONFIRMADA'
   AND r.data_entrada BETWEEN CURRENT_DATE AND CURRENT_DATE + 7
 ORDER BY r.data_entrada;

\qecho
\qecho ------ DEPOIS | consulta C | Busca por status e data de entrada: chegadas dos proximos 7 dias | execucao 4 de 5 ------
EXPLAIN (ANALYZE, BUFFERS)
SELECT r.reserva_id, r.hospede_id, r.quarto_id, r.data_entrada
  FROM reserva r
 WHERE r.status = 'CONFIRMADA'
   AND r.data_entrada BETWEEN CURRENT_DATE AND CURRENT_DATE + 7
 ORDER BY r.data_entrada;

\qecho
\qecho ------ DEPOIS | consulta C | Busca por status e data de entrada: chegadas dos proximos 7 dias | execucao 5 de 5 ------
EXPLAIN (ANALYZE, BUFFERS)
SELECT r.reserva_id, r.hospede_id, r.quarto_id, r.data_entrada
  FROM reserva r
 WHERE r.status = 'CONFIRMADA'
   AND r.data_entrada BETWEEN CURRENT_DATE AND CURRENT_DATE + 7
 ORDER BY r.data_entrada;

\o
\echo Pronto: copie /tmp/explain_antes_depois.txt com docker compose cp (veja o cabecalho deste arquivo).
