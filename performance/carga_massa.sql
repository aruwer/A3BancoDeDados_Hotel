-- performance/carga_massa.sql
-- Gera massa de dados volumosa no schema perf_test para medir planos de execução reais.
-- Requisito: dezenas de milhares de linhas para evitar Seq Scan por tabela pequena.
-- Rodar APÓS o banco estar no ar (01_ddl e 02_inserts já carregados pelo init). Rodar da raiz do repositório:
--   docker compose cp performance/carga_massa.sql postgres:/tmp/carga_massa.sql
--   docker compose exec postgres psql -U hotel -d hotel -v ON_ERROR_STOP=1 -f /tmp/carga_massa.sql
-- Este script cria o schema perf_test, clona as tabelas (sem dados) e popula com generate_series.

\set ON_ERROR_STOP on

-- 1. Criar schema de performance e clonar estrutura (sem dados, SEM índices e SEM FK).
-- ATENÇÃO: LIKE ... INCLUDING ALL copiaria também os índices do schema public (inclusive os 3 índices do projeto,
-- criados pelo 04_indices.sql), e o plano "antes" já usaria índice. Por isso usamos DEFAULTS + CONSTRAINTS (CHECK e NOT NULL)
-- e criamos só as PKs/UNIQUEs na seção 1b. Efeito colateral conhecido: os DEFAULTs SERIAL continuam apontando para as sequences do
-- public, então esta carga avança os ids do schema public. Rode a medição por último ou recrie o volume depois (docker compose down -v).
CREATE SCHEMA perf_test;   -- falha se já existir: para rodar de novo, recrie o volume (docker compose down -v)

-- Tabelas base (dimensões) — poucas linhas, mas necessárias para FKs
CREATE TABLE perf_test.Categoria_Quarto (LIKE public.Categoria_Quarto INCLUDING DEFAULTS INCLUDING CONSTRAINTS);
CREATE TABLE perf_test.Hospede (LIKE public.Hospede INCLUDING DEFAULTS INCLUDING CONSTRAINTS);
CREATE TABLE perf_test.Servico (LIKE public.Servico INCLUDING DEFAULTS INCLUDING CONSTRAINTS);

-- Tabelas de fato — muitas linhas
CREATE TABLE perf_test.Quarto (LIKE public.Quarto INCLUDING DEFAULTS INCLUDING CONSTRAINTS);
CREATE TABLE perf_test.Reserva (LIKE public.Reserva INCLUDING DEFAULTS INCLUDING CONSTRAINTS);
CREATE TABLE perf_test.Consumo_Servico (LIKE public.Consumo_Servico INCLUDING DEFAULTS INCLUDING CONSTRAINTS);
CREATE TABLE perf_test.Cancelamento (LIKE public.Cancelamento INCLUDING DEFAULTS INCLUDING CONSTRAINTS);

-- 1b. Só as PKs e UNIQUEs (o schema real também tem). Nenhum dos 3 índices do projeto existe ainda.
ALTER TABLE perf_test.Categoria_Quarto ADD CONSTRAINT pk_categoria_quarto PRIMARY KEY (id_categoria);
ALTER TABLE perf_test.Hospede          ADD CONSTRAINT pk_hospede          PRIMARY KEY (id_hospede),
                                       ADD CONSTRAINT uk_hospede_cpf      UNIQUE (cpf),
                                       ADD CONSTRAINT uk_hospede_email    UNIQUE (email);
ALTER TABLE perf_test.Servico          ADD CONSTRAINT pk_servico          PRIMARY KEY (id_servico);
ALTER TABLE perf_test.Quarto           ADD CONSTRAINT pk_quarto           PRIMARY KEY (id_quarto);
ALTER TABLE perf_test.Reserva          ADD CONSTRAINT pk_reserva          PRIMARY KEY (id_reserva);
ALTER TABLE perf_test.Consumo_Servico  ADD CONSTRAINT pk_consumo_servico  PRIMARY KEY (id_consumo);
ALTER TABLE perf_test.Cancelamento     ADD CONSTRAINT pk_cancelamento     PRIMARY KEY (id_cancelamento);

-- 2. Popular dimensões (copiar do public + alguns extras)
INSERT INTO perf_test.Categoria_Quarto SELECT * FROM public.Categoria_Quarto;
INSERT INTO perf_test.Hospede SELECT * FROM public.Hospede;
INSERT INTO perf_test.Servico SELECT * FROM public.Servico;

-- Adicionar mais hóspedes e serviços para variedade
INSERT INTO perf_test.Hospede (cpf, nome_completo, email, telefone, data_cadastro)
SELECT
    lpad((10000000000 + gs)::text, 11, '0'),
    'Hospede Perf ' || gs,
    'perf' || gs || '@example.com',
    '(11) 9' || lpad((gs % 10000)::text, 4, '0') || '-' || lpad((gs % 10000)::text, 4, '0'),
    CURRENT_DATE - (gs % 365)
FROM generate_series(1, 5000) gs
ON CONFLICT (cpf) DO NOTHING;

INSERT INTO perf_test.Servico (nome_servico, valor_unitario)
SELECT 'Servico Perf ' || gs, (10 + (gs % 200))::numeric(10,2)
FROM generate_series(1, 50) gs
ON CONFLICT DO NOTHING;

-- 3. Popular Quarto (~200 quartos)
INSERT INTO perf_test.Quarto (id_categoria, numero_quarto, andar, status_quarto)
SELECT
    1 + (gs % 3),
    'P' || lpad(gs::text, 4, '0'),
    1 + (gs % 10),
    CASE WHEN gs % 20 = 0 THEN 'MANUTENCAO' ELSE 'DISPONIVEL' END  -- ~5% em manutenção
FROM generate_series(1, 200) gs;

-- 4. Popular Reserva (~200.000 reservas)
-- Distribuídas ao longo de ~2 anos, com status variados
INSERT INTO perf_test.Reserva (
    id_hospede, id_quarto, data_reserva,
    data_entrada_prevista, data_saida_prevista,
    data_checkin_real, data_checkout_real,
    status_reserva, valor_total_bruto, percentual_desconto, valor_final_pago
)
SELECT
    1 + (gs % 5008)::int,           -- id_hospede (inclui os novos)
    1 + (gs % 200)::int,            -- id_quarto
    CURRENT_TIMESTAMP - INTERVAL '1 day' * (gs % 730),  -- data_reserva até 2 anos atrás
    CURRENT_DATE - INTERVAL '1 day' * (730 - gs % 730) + INTERVAL '1 day' * (gs % 30),  -- entrada
    CURRENT_DATE - INTERVAL '1 day' * (730 - gs % 730) + INTERVAL '1 day' * (gs % 30 + 1 + (gs % 7)),  -- saída (1-7 noites)
    CASE WHEN gs % 5 = 0 THEN CURRENT_DATE - INTERVAL '1 day' * (730 - gs % 730) + INTERVAL '1 day' * (gs % 30) + TIME '14:00' END,
    CASE WHEN gs % 5 = 0 THEN CURRENT_DATE - INTERVAL '1 day' * (730 - gs % 730) + INTERVAL '1 day' * (gs % 30 + 1 + (gs % 7)) + TIME '11:00' END,
    CASE (gs % 10)
        WHEN 0 THEN 'CANCELADA'
        WHEN 1 THEN 'NO-SHOW'
        WHEN 2 THEN 'PENDENTE'
        WHEN 3 THEN 'CONFIRMADA'
        WHEN 4 THEN 'CHECK-IN'
        ELSE 'CHECK-OUT'
    END,
    (100 + (gs % 500))::numeric(10,2) * (1 + (gs % 7)),  -- valor_total_bruto
    CASE WHEN gs % 20 = 0 THEN 5 WHEN gs % 20 = 1 THEN 10 ELSE 0 END,  -- desconto 0/5/10%
    CASE WHEN gs % 5 = 0 THEN NULL ELSE (100 + (gs % 500))::numeric(10,2) * (1 + (gs % 7)) * (1 - CASE WHEN gs % 20 = 0 THEN 0.05 WHEN gs % 20 = 1 THEN 0.10 ELSE 0 END) + (gs % 100)::numeric(10,2) END
FROM generate_series(1, 200000) gs;

-- 5. Popular Consumo_Servico (~400.000 linhas)
-- Apenas para reservas CHECK-OUT ou CHECK-IN (em andamento)
INSERT INTO perf_test.Consumo_Servico (id_reserva, id_servico, quantidade, data_consumo, valor_total_item)
SELECT
    r.id_reserva,
    1 + (gs % 56)::int,  -- id_servico (originais + novos)
    1 + (gs % 5)::int,   -- quantidade 1-5
    r.data_entrada_prevista + INTERVAL '1 day' * (gs % 7) + TIME '12:00',
    (10 + (gs % 200))::numeric(10,2) * (1 + (gs % 5))
FROM perf_test.Reserva r
JOIN generate_series(1, 2) gs ON true  -- 2 consumos por reserva em média
WHERE r.status_reserva IN ('CHECK-OUT', 'CHECK-IN')
LIMIT 400000;

-- 6. Popular Cancelamento (para reservas CANCELADA e NO-SHOW)
INSERT INTO perf_test.Cancelamento (id_reserva, data_cancelamento, taxa_multa_aplicada, motivo_cancelamento)
SELECT
    r.id_reserva,
    CURRENT_TIMESTAMP - INTERVAL '1 day' * (r.id_reserva % 30),
    CASE
        WHEN r.data_entrada_prevista - CURRENT_DATE >= 7 THEN 0
        WHEN r.data_entrada_prevista - CURRENT_DATE >= 2 THEN (r.valor_total_bruto / (r.data_saida_prevista - r.data_entrada_prevista)) * 0.5
        ELSE r.valor_total_bruto / (r.data_saida_prevista - r.data_entrada_prevista)
    END,
    'Cancelamento em massa para teste de performance'
FROM perf_test.Reserva r
WHERE r.status_reserva IN ('CANCELADA', 'NO-SHOW');

-- 7. Atualizar sequences
SELECT setval(pg_get_serial_sequence('perf_test.categoria_quarto', 'id_categoria'), (SELECT MAX(id_categoria) FROM perf_test.Categoria_Quarto));
SELECT setval(pg_get_serial_sequence('perf_test.hospede', 'id_hospede'), (SELECT MAX(id_hospede) FROM perf_test.Hospede));
SELECT setval(pg_get_serial_sequence('perf_test.servico', 'id_servico'), (SELECT MAX(id_servico) FROM perf_test.Servico));
SELECT setval(pg_get_serial_sequence('perf_test.quarto', 'id_quarto'), (SELECT MAX(id_quarto) FROM perf_test.Quarto));
SELECT setval(pg_get_serial_sequence('perf_test.reserva', 'id_reserva'), (SELECT MAX(id_reserva) FROM perf_test.Reserva));
SELECT setval(pg_get_serial_sequence('perf_test.cancelamento', 'id_cancelamento'), (SELECT MAX(id_cancelamento) FROM perf_test.Cancelamento));
SELECT setval(pg_get_serial_sequence('perf_test.consumo_servico', 'id_consumo'), (SELECT MAX(id_consumo) FROM perf_test.Consumo_Servico));

-- 8. Estatísticas para o planner
ANALYZE perf_test.Categoria_Quarto;
ANALYZE perf_test.Hospede;
ANALYZE perf_test.Servico;
ANALYZE perf_test.Quarto;
ANALYZE perf_test.Reserva;
ANALYZE perf_test.Consumo_Servico;
ANALYZE perf_test.Cancelamento;

-- Resumo de linhas
SELECT 'perf_test.Categoria_Quarto' AS tabela, COUNT(*) AS linhas FROM perf_test.Categoria_Quarto
UNION ALL SELECT 'perf_test.Hospede', COUNT(*) FROM perf_test.Hospede
UNION ALL SELECT 'perf_test.Servico', COUNT(*) FROM perf_test.Servico
UNION ALL SELECT 'perf_test.Quarto', COUNT(*) FROM perf_test.Quarto
UNION ALL SELECT 'perf_test.Reserva', COUNT(*) FROM perf_test.Reserva
UNION ALL SELECT 'perf_test.Consumo_Servico', COUNT(*) FROM perf_test.Consumo_Servico
UNION ALL SELECT 'perf_test.Cancelamento', COUNT(*) FROM perf_test.Cancelamento;
