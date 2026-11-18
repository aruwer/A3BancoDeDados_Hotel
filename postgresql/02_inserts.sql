-- 02_inserts.sql
-- Banco de Dados: PostgreSQL 17
-- Carga de dados fictícia para fins acadêmicos (LGPD): os hóspedes são inventados e não
-- representam pessoas reais.
-- Todas as datas são RELATIVAS a CURRENT_DATE / CURRENT_TIMESTAMP, então as consultas
-- dão o mesmo resultado em qualquer dia de execução.
-- Execução (banco vazio, logo após o 01_ddl.sql):
--   psql -v ON_ERROR_STOP=1 -f postgresql/01_ddl.sql
--   psql -v ON_ERROR_STOP=1 -f postgresql/02_inserts.sql
--
-- DADOS DE FRONTEIRA
--   F1 (empate no RANK): Mariana (hósp. 5) e Ricardo (hósp. 6) gastaram exatamente R$ 800,00
--      (reservas 7 e 8) => posição 5 repetida; Luciana fica em 7º. Ana e Carlos têm 2 estadias cada.
--   F2 (limite da multa de cancelamento, regras.md seção 4.1; D = diária; antecedência em dias
--      contada a partir de hoje, data do cancelamento):
--        reserva 13: 7 dias => sem multa (limite inferior da faixa sem multa)
--        reserva 14: 6 dias => 50% de D (limite superior da faixa de 50%)
--        reserva 15: 2 dias => 50% de D (limite inferior da faixa de 50%)
--        reserva 16: 1 dia  => 100% de D (primeiro dia da faixa de 100%)
--        reserva 17: NO-SHOW (entrada já passou sem check-in) => 100% de D
--   F3 (NOT EXISTS): o quarto 302 (ativo) e o quarto 103 (em manutenção) não têm nenhuma reserva.
--
-- Totais gastos (diárias + consumos) das reservas CHECK-OUT, para conferir o ranking:
--  João Pedro 2420,00 | Carlos Eduardo 2250,00 | Ana Beatriz 1550,00 | Fernanda 1200,00 | Mariana 800,00 = Ricardo 800,00 | Luciana 400,00

BEGIN;

-- 1) Categorias de quarto
INSERT INTO categoria_quarto (id_categoria, nome_categoria,capacidade_maxima, valor_diaria_base) VALUES
    (1, 'Standard', 2, 200.00),
    (2, 'Superior', 3, 300.00),
    (3, 'Suíte',    4, 500.00);

-- 2) Quartos (103 em manutenção; 302 sem nenhuma reserva)
INSERT INTO quarto (id_quarto, id_categoria, numero_quarto, andar, status_manutencao) VALUES
    (1, 1, '101', 1, FALSE),
    (2, 1, '102', 1, FALSE),
    (3, 1, '103', 1, TRUE),
    (4, 2, '201', 2, FALSE),
    (5, 2, '202', 2, FALSE),
    (6, 3, '301', 3, FALSE),
    (7, 3, '302', 3, FALSE);

-- 3) Hóspedes (todos fictícios)
INSERT INTO hospede (id_hospede, cpf, nome_completo, email, telefone, data_cadastro) VALUES
    (1, '12345678909', 'Ana Beatriz Souza Lima', 'ana.lima@gmail.com', '(51) 99123-4567', CURRENT_DATE - 90),
    (2, '11144477735', 'Carlos Eduardo Menezes', 'carlos.menezes@hotmail.com','(11) 98765-4321', CURRENT_DATE - 85),
    (3, '52998224725', 'Fernanda Rocha Almeida', 'fernanda.almeida@gmail.com','(21) 97654-3210', CURRENT_DATE - 80),
    (4, '98765432100', 'João Pedro Vasconcelos', 'joao.vasconcelos@hotmail.com','(31) 99876-5432', CURRENT_DATE - 75),
    (5, '24681357928', 'Mariana Costa Ferreira', 'mariana.ferreira@gmail.com','(41) 98234-5678', CURRENT_DATE - 70),
    (6, '13579246828', 'Ricardo Alves Teixeira', 'ricardo.teixeira@hotmail.com','(51) 99345-6789', CURRENT_DATE - 65),
    (7, '11223344517', 'Luciana Prado Nogueira', 'luciana.nogueira@gmail.com','(85) 98456-7890', CURRENT_DATE - 60),
    (8, '31415926590', 'Gabriel Santos Oliveira', 'gabriel.oliveira@hotmail.com','(62) 99567-8901', CURRENT_DATE - 55);

-- 4) Serviços
INSERT INTO servico (id_servico, nome_servico, valor_unitario) VALUES
    (1, 'Café da manhã',  35.00),
    (2, 'Jantar',         90.00),
    (3, 'Lavanderia',     45.00),
    (4, 'Spa',           150.00),
    (5, 'Frigobar',       25.00),
    (6, 'Estacionamento', 40.00);

-- 5) Reservas
-- valor_total_bruto = noites x diária da categoria; percentual_desconto = 0 em todas
-- (desconto de fidelidade exige 5+ estadias, ninguém chega lá nesta carga).
-- valor_final_pago = bruto + consumos, preenchido só nas reservas CHECK-OUT.

-- 5a) Estadias concluídas (CHECK-OUT): entrada às 14:00, saída às 11:00
INSERT INTO reserva (
    id_reserva, id_hospede, id_quarto, data_reserva,
    data_entrada_prevista, data_saida_prevista,
    data_checkin_real, data_checkout_real,
    status_reserva, valor_total_bruto, percentual_desconto, valor_final_pago
) VALUES
    (1, 1, 4, CURRENT_TIMESTAMP - INTERVAL '50 days',
        CURRENT_DATE - 40, CURRENT_DATE - 37,
        CURRENT_DATE - 40 + TIME '14:00', CURRENT_DATE - 37 + TIME '11:00',
        'CHECK-OUT', 900.00, 0, 1080.00),
    (2, 1, 1, CURRENT_TIMESTAMP - INTERVAL '30 days',
        CURRENT_DATE - 20, CURRENT_DATE - 18,
        CURRENT_DATE - 20 + TIME '14:00', CURRENT_DATE - 18 + TIME '11:00',
        'CHECK-OUT', 400.00, 0, 470.00),
    (3, 2, 6, CURRENT_TIMESTAMP - INTERVAL '40 days',
        CURRENT_DATE - 30, CURRENT_DATE - 27,
        CURRENT_DATE - 30 + TIME '14:00', CURRENT_DATE - 27 + TIME '11:00',
        'CHECK-OUT', 1500.00, 0, 1650.00),
    (4, 4, 6, CURRENT_TIMESTAMP - INTERVAL '70 days',
        CURRENT_DATE - 60, CURRENT_DATE - 56,
        CURRENT_DATE - 60 + TIME '14:00', CURRENT_DATE - 56 + TIME '11:00',
        'CHECK-OUT', 2000.00, 0, 2420.00),
    (5, 2, 2, CURRENT_TIMESTAMP - INTERVAL '25 days',
        CURRENT_DATE - 15, CURRENT_DATE - 12,
        CURRENT_DATE - 15 + TIME '14:00', CURRENT_DATE - 12 + TIME '11:00',
        'CHECK-OUT', 600.00, 0, 600.00),
    (6, 3, 5, CURRENT_TIMESTAMP - INTERVAL '35 days',
        CURRENT_DATE - 25, CURRENT_DATE - 21,
        CURRENT_DATE - 25 + TIME '14:00', CURRENT_DATE - 21 + TIME '11:00',
        'CHECK-OUT', 1200.00, 0, 1200.00),
    (7, 5, 2, CURRENT_TIMESTAMP - INTERVAL '20 days',
        CURRENT_DATE - 10, CURRENT_DATE - 7,
        CURRENT_DATE - 10 + TIME '14:00', CURRENT_DATE - 7 + TIME '11:00',
        'CHECK-OUT', 600.00, 0, 800.00),
    (8, 6, 4, CURRENT_TIMESTAMP - INTERVAL '22 days',
        CURRENT_DATE - 12, CURRENT_DATE - 10,
        CURRENT_DATE - 12 + TIME '14:00', CURRENT_DATE - 10 + TIME '11:00',
        'CHECK-OUT', 600.00, 0, 800.00),
    (9, 7, 1, CURRENT_TIMESTAMP - INTERVAL '16 days',
        CURRENT_DATE - 6, CURRENT_DATE - 4,
        CURRENT_DATE - 6 + TIME '14:00', CURRENT_DATE - 4 + TIME '11:00',
        'CHECK-OUT', 400.00, 0, 400.00);

-- 5b) Hóspede hospedado hoje (CHECK-IN), 4 noites: entrou há 2 dias e sai daqui a 2
INSERT INTO reserva (
    id_reserva, id_hospede, id_quarto, data_reserva,
    data_entrada_prevista, data_saida_prevista, data_checkin_real,
    status_reserva, valor_total_bruto, percentual_desconto
) VALUES
    (10, 8, 5, CURRENT_TIMESTAMP - INTERVAL '12 days',
        CURRENT_DATE - 2, CURRENT_DATE + 2, CURRENT_DATE - 2 + TIME '14:00',
        'CHECK-IN', 1200.00, 0);

-- 5c) Reservas futuras (CONFIRMADA e PENDENTE)
INSERT INTO reserva (
    id_reserva, id_hospede, id_quarto, data_reserva,
    data_entrada_prevista, data_saida_prevista,
    status_reserva, valor_total_bruto, percentual_desconto
) VALUES
    (11, 7, 1, CURRENT_TIMESTAMP - INTERVAL '5 days',
        CURRENT_DATE + 10, CURRENT_DATE + 13,
        'CONFIRMADA', 600.00, 0),
    (12, 2, 4, CURRENT_TIMESTAMP - INTERVAL '4 days',
        CURRENT_DATE + 5, CURRENT_DATE + 8,
        'CONFIRMADA', 900.00, 0),
    (18, 7, 4, CURRENT_TIMESTAMP - INTERVAL '1 days',
        CURRENT_DATE + 20, CURRENT_DATE + 22,
        'PENDENTE', 600.00, 0);

-- 5d) Fronteira F2: cancelamentos (data_cancelamento = agora) e no-show
INSERT INTO reserva (
    id_reserva, id_hospede, id_quarto, data_reserva,
    data_entrada_prevista, data_saida_prevista,
    status_reserva, valor_total_bruto, percentual_desconto
) VALUES
    (13, 1, 6, CURRENT_TIMESTAMP - INTERVAL '10 days',
        CURRENT_DATE + 7, CURRENT_DATE + 10,
        'CANCELADA', 1500.00, 0),
    (14, 3, 5, CURRENT_TIMESTAMP - INTERVAL '9 days',
        CURRENT_DATE + 6, CURRENT_DATE + 8,
        'CANCELADA', 600.00, 0),
    (15, 4, 2, CURRENT_TIMESTAMP - INTERVAL '8 days',
        CURRENT_DATE + 2, CURRENT_DATE + 4,
        'CANCELADA', 400.00, 0),
    (16, 6, 1, CURRENT_TIMESTAMP - INTERVAL '7 days',
        CURRENT_DATE + 1, CURRENT_DATE + 3,
        'CANCELADA', 400.00, 0),
    (17, 6, 2, CURRENT_TIMESTAMP - INTERVAL '10 days',
        CURRENT_DATE - 3, CURRENT_DATE - 1,
        'NO-SHOW', 400.00, 0);

-- 6) Cancelamentos e multas (regras.md 4.1: 0% / 50% / 100% da primeira diária D)
INSERT INTO cancelamento (id_cancelamento, id_reserva, data_cancelamento,
                          taxa_multa_aplicada, motivo_cancelamento) VALUES
    (1, 13, CURRENT_TIMESTAMP, 0.00,
        'Cancelado com 7 dias de antecedência: sem multa'),
    (2, 14, CURRENT_TIMESTAMP, 150.00,
        'Cancelado com 6 dias de antecedência: 50% da primeira diária (D = 300,00)'),
    (3, 15, CURRENT_TIMESTAMP, 100.00,
        'Cancelado com 2 dias de antecedência: 50% da primeira diária (D = 200,00)'),
    (4, 16, CURRENT_TIMESTAMP, 200.00,
        'Cancelado com 1 dia de antecedência: 100% da primeira diária (D = 200,00)'),
    (5, 17, CURRENT_TIMESTAMP, 200.00,
        'No-show: entrada já passou sem check-in, 100% da primeira diária (D = 200,00)');

-- 7) Consumos (valor_total_item = quantidade x valor_unitario do serviço)
INSERT INTO consumo_servico (id_consumo, id_reserva, id_servico, quantidade,
                             data_consumo, valor_total_item) VALUES
    ( 1,  1, 2, 2, CURRENT_DATE - 39 + TIME '20:00', 180.00),
    ( 2,  2, 1, 2, CURRENT_DATE - 19 + TIME '08:00',  70.00),
    ( 3,  3, 4, 1, CURRENT_DATE - 29 + TIME '16:00', 150.00),
    ( 4,  4, 2, 3, CURRENT_DATE - 58 + TIME '20:00', 270.00),
    ( 5,  4, 4, 1, CURRENT_DATE - 57 + TIME '16:00', 150.00),
    ( 6,  7, 4, 1, CURRENT_DATE -  9 + TIME '16:00', 150.00),
    ( 7,  7, 5, 2, CURRENT_DATE -  8 + TIME '22:00',  50.00),
    ( 8,  8, 1, 2, CURRENT_DATE - 11 + TIME '08:00',  70.00),
    ( 9,  8, 2, 1, CURRENT_DATE - 11 + TIME '20:00',  90.00),
    (10,  8, 6, 1, CURRENT_DATE - 12 + TIME '15:00',  40.00),
    (11, 10, 1, 2, CURRENT_DATE -  1 + TIME '08:00',  70.00),
    (12, 10, 3, 1, CURRENT_DATE -  1 + TIME '18:00',  45.00);

-- 8) Pagamentos (valor sempre positivo; o tipo indica o sentido: PAGAMENTO ou ESTORNO)
-- Todo sinal é de exatamente 30% das diárias (limite da RN-10). A reserva 18 (PENDENTE) fica
-- sem nenhum pagamento, porque o sinal ainda não foi pago.
--   Estadias concluídas: sinal + quitação no check-out = valor_final_pago.
--   Cancelamentos e no-show: pagamentos - estornos = multa aplicada.
--     reserva 13: multa 0      => estorno de todo o sinal (450)
--     reserva 14: multa 150    => estorno de 30 (sinal 180 - multa 150)
--     reserva 15: multa 100    => estorno de 20 (sinal 120 - multa 100)
--     reserva 16: multa 200    => sinal 120 + cobrança de 80 (a multa passa do sinal)
--     reserva 17: multa 200    => sinal 120 + cobrança de 80 (no-show)
INSERT INTO Pagamento (id_pagamento, id_reserva, tipo, forma, valor, data_hora) VALUES
    ( 1,  1, 'PAGAMENTO', 'PIX',            270.00, CURRENT_TIMESTAMP - INTERVAL '50 days'),
    ( 2,  1, 'PAGAMENTO', 'CARTAO_CREDITO', 810.00, CURRENT_DATE - 37 + TIME '11:00'),
    ( 3,  2, 'PAGAMENTO', 'DINHEIRO',       120.00, CURRENT_TIMESTAMP - INTERVAL '30 days'),
    ( 4,  2, 'PAGAMENTO', 'PIX',            350.00, CURRENT_DATE - 18 + TIME '11:00'),
    ( 5,  3, 'PAGAMENTO', 'CARTAO_CREDITO', 450.00, CURRENT_TIMESTAMP - INTERVAL '40 days'),
    ( 6,  3, 'PAGAMENTO', 'PIX',           1200.00, CURRENT_DATE - 27 + TIME '11:00'),
    ( 7,  4, 'PAGAMENTO', 'PIX',            600.00, CURRENT_TIMESTAMP - INTERVAL '70 days'),
    ( 8,  4, 'PAGAMENTO', 'CARTAO_CREDITO', 1820.00, CURRENT_DATE - 56 + TIME '11:00'),
    ( 9,  5, 'PAGAMENTO', 'PIX',            180.00, CURRENT_TIMESTAMP - INTERVAL '25 days'),
    (10,  5, 'PAGAMENTO', 'CARTAO_DEBITO',  420.00, CURRENT_DATE - 12 + TIME '11:00'),
    (11,  6, 'PAGAMENTO', 'CARTAO_CREDITO', 360.00, CURRENT_TIMESTAMP - INTERVAL '35 days'),
    (12,  6, 'PAGAMENTO', 'CARTAO_CREDITO', 840.00, CURRENT_DATE - 21 + TIME '11:00'),
    (13,  7, 'PAGAMENTO', 'DINHEIRO',       180.00, CURRENT_TIMESTAMP - INTERVAL '20 days'),
    (14,  7, 'PAGAMENTO', 'PIX',            620.00, CURRENT_DATE -  7 + TIME '11:00'),
    (15,  8, 'PAGAMENTO', 'PIX',            180.00, CURRENT_TIMESTAMP - INTERVAL '22 days'),
    (16,  8, 'PAGAMENTO', 'CARTAO_DEBITO',  620.00, CURRENT_DATE - 10 + TIME '11:00'),
    (17,  9, 'PAGAMENTO', 'PIX',            120.00, CURRENT_TIMESTAMP - INTERVAL '16 days'),
    (18,  9, 'PAGAMENTO', 'DINHEIRO',       280.00, CURRENT_DATE -  4 + TIME '11:00'),
    (19, 10, 'PAGAMENTO', 'CARTAO_CREDITO', 360.00, CURRENT_TIMESTAMP - INTERVAL '12 days'),
    (20, 11, 'PAGAMENTO', 'PIX',            180.00, CURRENT_TIMESTAMP - INTERVAL '5 days'),
    (21, 12, 'PAGAMENTO', 'CARTAO_CREDITO', 270.00, CURRENT_TIMESTAMP - INTERVAL '4 days'),
    (22, 13, 'PAGAMENTO', 'PIX',            450.00, CURRENT_TIMESTAMP - INTERVAL '10 days'),
    (23, 13, 'ESTORNO',   'PIX',            450.00, CURRENT_TIMESTAMP),
    (24, 14, 'PAGAMENTO', 'PIX',            180.00, CURRENT_TIMESTAMP - INTERVAL '9 days'),
    (25, 14, 'ESTORNO',   'PIX',             30.00, CURRENT_TIMESTAMP),
    (26, 15, 'PAGAMENTO', 'PIX',            120.00, CURRENT_TIMESTAMP - INTERVAL '8 days'),
    (27, 15, 'ESTORNO',   'PIX',             20.00, CURRENT_TIMESTAMP),
    (28, 16, 'PAGAMENTO', 'PIX',            120.00, CURRENT_TIMESTAMP - INTERVAL '7 days'),
    (29, 16, 'PAGAMENTO', 'CARTAO_CREDITO',  80.00, CURRENT_TIMESTAMP),
    (30, 17, 'PAGAMENTO', 'CARTAO_CREDITO', 120.00, CURRENT_TIMESTAMP - INTERVAL '10 days'),
    (31, 17, 'PAGAMENTO', 'CARTAO_CREDITO',  80.00, CURRENT_TIMESTAMP);

-- 9) Alinha as sequências SERIAL com os ids inseridos explicitamente
SELECT setval(pg_get_serial_sequence('categoria_quarto', 'id_categoria'),  (SELECT MAX(id_categoria)   FROM Categoria_Quarto));
SELECT setval(pg_get_serial_sequence('quarto',           'id_quarto'),     (SELECT MAX(id_quarto)      FROM Quarto));
SELECT setval(pg_get_serial_sequence('hospede',          'id_hospede'),    (SELECT MAX(id_hospede)     FROM Hospede));
SELECT setval(pg_get_serial_sequence('servico',          'id_servico'),    (SELECT MAX(id_servico)     FROM Servico));
SELECT setval(pg_get_serial_sequence('reserva',          'id_reserva'),    (SELECT MAX(id_reserva)     FROM Reserva));
SELECT setval(pg_get_serial_sequence('cancelamento',     'id_cancelamento'), (SELECT MAX(id_cancelamento) FROM Cancelamento));
SELECT setval(pg_get_serial_sequence('consumo_servico',  'id_consumo'),    (SELECT MAX(id_consumo)     FROM Consumo_Servico));
SELECT setval(pg_get_serial_sequence('pagamento',        'id_pagamento'),  (SELECT MAX(id_pagamento)   FROM Pagamento));

COMMIT;

