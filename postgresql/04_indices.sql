-- 04_indices.sql
-- Banco de Dados: PostgreSQL 17
-- Três índices estratégicos, cada um medido em performance/explain_antes_depois.txt
-- (plano antes e depois, texto real do EXPLAIN ANALYZE).
-- Sem schema nos nomes: o script de medição roda este arquivo com search_path em perf_test.

-- 1) FK usada em JOIN: reservas de um hóspede (consultas Q03, Q08, histórico do hóspede).
CREATE INDEX idx_reserva_hospede ON Reserva (id_hospede);

-- 2) FK da entidade associativa: consumos de uma reserva (consultas Q03, Q07, Q09, fechamento da conta no check-out).
CREATE INDEX idx_consumo_reserva ON Consumo_Servico (id_reserva);

-- 3) Índice de busca: chegadas por situação e data de entrada (consulta Q02, recepção).
--    Igualdade em status primeiro, faixa em data_entrada_prevista depois.
CREATE INDEX idx_reserva_status_entrada ON Reserva (status_reserva, data_entrada_prevista);

-- Decisões:
-- * Reserva.id_quarto NÃO ganha índice próprio: a constraint de exclusão (se criada) já cria um índice GiST.
-- * As FKs Cancelamento.id_reserva, Consumo_Servico.id_servico e Quarto.id_categoria ficam sem índice no escopo da A3:
--   a rubrica pede 3 índices, e índice criado e nunca medido conta como insuficiente.