-- test_procedures.sql
-- Testa cancelar_reserva e fazer_checkout (RN-04, RN-05, RN-08, RN-09) com valores de fronteira.
-- Pré-requisito: 01_ddl.sql, 02_inserts.sql e procedures/postgresql_procedures.sql carregados,
-- com os dados de exemplo ORIGINAIS (o teste usa as reservas 1, 10, 12, 13, 17 e 18).
-- Tudo roda numa transação desfeita no final. Se alguma procedure tivesse COMMIT/ROLLBACK, a
-- chamada dentro das funções auxiliares abaixo falharia (e o banco não voltaria ao estado original).
--
--   psql -h localhost -U hotel -d hotel -v ON_ERROR_STOP=1 -f tests/test_procedures.sql
-- Sucesso = sem ERROR e a última linha "TODOS OS TESTES DAS PROCEDURES PASSARAM".
--
-- Convenções do teste: quarto 7 (302) não tem reservas nos dados de exemplo; hóspede 1 é o padrão.
-- Reserva de teste: 3 noites, bruto 600,00 => D = 200,00.
\set ON_ERROR_STOP on
BEGIN;

-- ------------------------------ auxiliares ------------------------------
CREATE FUNCTION pg_temp.verifica(p_nome TEXT, p_ok BOOLEAN) RETURNS VOID AS $$
BEGIN
    IF p_ok IS NOT TRUE THEN
        RAISE EXCEPTION 'FALHA: %', p_nome;
    END IF;
    RAISE NOTICE 'OK    %', p_nome;
END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION pg_temp.esperar_erro(p_sql TEXT, p_prefixo TEXT) RETURNS VOID AS $$
DECLARE v_msg TEXT;
BEGIN
    BEGIN
        EXECUTE p_sql;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        IF v_msg LIKE p_prefixo || '%' THEN
            RAISE NOTICE 'OK    barrou (%): %', p_prefixo, regexp_replace(p_sql, '\s+', ' ', 'g');
            RETURN;
        END IF;
        RAISE EXCEPTION 'FALHA: erro inesperado "%" em: %', v_msg, p_sql;
    END;
    RAISE EXCEPTION 'FALHA: deveria ter sido barrado: %', p_sql;
END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION pg_temp.nova_reserva(p_hospede INT, p_quarto INT, p_ent INT, p_sai INT,
                                     p_status TEXT, p_bruto NUMERIC) RETURNS INT AS $$
DECLARE v_id INT;
BEGIN
    INSERT INTO reserva (id_hospede, id_quarto, data_entrada_prevista, data_saida_prevista,
                         data_checkin_real, status_reserva, valor_total_bruto)
    VALUES (p_hospede, p_quarto, CURRENT_DATE + p_ent, CURRENT_DATE + p_sai,
            CASE WHEN p_status = 'CHECK-IN' THEN (CURRENT_DATE + p_ent) + TIME '14:00' END,
            p_status, p_bruto)
    RETURNING id_reserva INTO v_id;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

-- Hóspede novo, com p_n estadias CHECK-OUT anteriores (no quarto 7, em datas antigas).
CREATE FUNCTION pg_temp.hospede_com(p_n INT) RETURNS INT AS $$
DECLARE v_k INT; v_id INT;
BEGIN
    SELECT COALESCE(MAX(id_hospede), 0) + 1 INTO v_k FROM hospede;
    INSERT INTO hospede (cpf, nome_completo, email)
    VALUES (lpad(v_k::TEXT, 11, '0'), 'Hospede Teste ' || v_k, 'teste' || v_k || '@teste.local')
    RETURNING id_hospede INTO v_id;
    INSERT INTO reserva (id_hospede, id_quarto, data_entrada_prevista, data_saida_prevista,
                         status_reserva, valor_total_bruto)
    SELECT v_id, 7, CURRENT_DATE - 300 + 3 * i, CURRENT_DATE - 300 + 3 * i + 1, 'CHECK-OUT', 200
    FROM generate_series(1, p_n) AS i;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

-- Cria reserva CONFIRMADA (3 noites, D=200) a 100 dias, cancela simulando "hoje" = entrada - p_dias.
CREATE FUNCTION pg_temp.cancela_ok(p_dias INT, p_multa NUMERIC, p_status TEXT) RETURNS VOID AS $$
DECLARE v_id INT; v_st TEXT; v_m NUMERIC; v_n INT;
BEGIN
    v_id := pg_temp.nova_reserva(1, 7, 100, 103, 'CONFIRMADA', 600);
    CALL cancelar_reserva(v_id, CURRENT_DATE + 100 - p_dias);
    SELECT status_reserva INTO v_st FROM reserva WHERE id_reserva = v_id;
    SELECT COUNT(*), MAX(taxa_multa_aplicada) INTO v_n, v_m FROM cancelamento WHERE id_reserva = v_id;
    PERFORM pg_temp.verifica(
        format('cancelar a %s dia(s) da entrada: status %s, multa %s, 1 lançamento', p_dias, p_status, p_multa),
        v_st = p_status AND v_m = p_multa AND v_n = 1);
END;
$$ LANGUAGE plpgsql;

-- Reserva CHECK-IN (3 noites, saída prevista = hoje, D=200) de hóspede com p_prev estadias; faz o check-out.
CREATE FUNCTION pg_temp.checkout_ok(p_prev INT, p_saida TIMESTAMP, p_consumo NUMERIC,
                                    p_final NUMERIC, p_desc NUMERIC) RETURNS VOID AS $$
DECLARE v_h INT; v_id INT; r RECORD;
BEGIN
    v_h := pg_temp.hospede_com(p_prev);
    v_id := pg_temp.nova_reserva(v_h, 7, -3, 0, 'CHECK-IN', 600);
    IF p_consumo > 0 THEN
        INSERT INTO consumo_servico (id_reserva, id_servico, quantidade, valor_total_item)
        VALUES (v_id, 2, 1, p_consumo);
    END IF;
    CALL fazer_checkout(v_id, p_final, p_saida);          -- paga exatamente o valor final esperado
    SELECT status_reserva, valor_final_pago, percentual_desconto, data_checkout_real INTO r
    FROM reserva WHERE id_reserva = v_id;
    PERFORM pg_temp.verifica(
        format('check-out (%s estadias prévias, saída %s, consumo %s): final %s, desconto %s%%',
               p_prev, p_saida, p_consumo, p_final, p_desc),
        r.status_reserva = 'CHECK-OUT' AND r.valor_final_pago = p_final
        AND r.percentual_desconto = p_desc AND r.data_checkout_real = p_saida);
END;
$$ LANGUAGE plpgsql;

-- Tenta um check-out que deve falhar; confere o código e que a reserva continua CHECK-IN; limpa.
CREATE FUNCTION pg_temp.checkout_erro(p_saida TIMESTAMP, p_pago NUMERIC, p_codigo TEXT) RETURNS VOID AS $$
DECLARE v_id INT; v_st TEXT;
BEGIN
    v_id := pg_temp.nova_reserva(pg_temp.hospede_com(0), 7, -3, 0, 'CHECK-IN', 600);
    PERFORM pg_temp.esperar_erro(format('CALL fazer_checkout(%s, %s, %L)', v_id, p_pago, p_saida), p_codigo);
    SELECT status_reserva INTO v_st FROM reserva WHERE id_reserva = v_id;
    PERFORM pg_temp.verifica('após ' || p_codigo || ' a reserva continua em CHECK-IN', v_st = 'CHECK-IN');
    DELETE FROM reserva WHERE id_reserva = v_id;
END;
$$ LANGUAGE plpgsql;

-- ------------------------------ 0) procedures existem ------------------------------
SELECT pg_temp.verifica('procedures cancelar_reserva e fazer_checkout existem',
    (SELECT COUNT(*) FROM pg_proc WHERE proname IN ('cancelar_reserva', 'fazer_checkout') AND prokind = 'p') = 2);

-- ------------------------------ 1) cancelar_reserva: faixas da RN-04 ------------------------------
SELECT pg_temp.cancela_ok( 7,   0.00, 'CANCELADA');   -- 7 dias: sem multa
SELECT pg_temp.cancela_ok(20,   0.00, 'CANCELADA');   -- bem antes: sem multa
SELECT pg_temp.cancela_ok( 6, 100.00, 'CANCELADA');   -- 6 dias: 50% de 200
SELECT pg_temp.cancela_ok( 2, 100.00, 'CANCELADA');   -- 2 dias: 50%
SELECT pg_temp.cancela_ok( 1, 200.00, 'CANCELADA');   -- 1 dia: 100%
SELECT pg_temp.cancela_ok( 0, 200.00, 'CANCELADA');   -- no dia da entrada: 100%
SELECT pg_temp.cancela_ok(-1, 200.00, 'NO-SHOW');     -- entrada ontem: NO-SHOW, 100%

-- Seed: D = 300 (reserva 12 = 3 noites, bruto 900) a 5 dias => 50% de 300 = 150
DO $$
DECLARE v_st TEXT; v_m NUMERIC;
BEGIN
    CALL cancelar_reserva(12);
    SELECT status_reserva INTO v_st FROM reserva WHERE id_reserva = 12;
    SELECT taxa_multa_aplicada INTO v_m FROM cancelamento WHERE id_reserva = 12;
    PERFORM pg_temp.verifica('reserva 12 (entrada hoje+5, D=300) cancelada hoje: CANCELADA, multa 150.00',
                             v_st = 'CANCELADA' AND v_m = 150.00);
END $$;

-- Reserva PENDENTE também cancela (reserva 18, entrada hoje+20 => sem multa)
DO $$
DECLARE v_st TEXT; v_m NUMERIC;
BEGIN
    CALL cancelar_reserva(18, NULL, 'Hospede desistiu');
    SELECT status_reserva INTO v_st FROM reserva WHERE id_reserva = 18;
    SELECT taxa_multa_aplicada INTO v_m FROM cancelamento WHERE id_reserva = 18 AND motivo_cancelamento = 'Hospede desistiu';
    PERFORM pg_temp.verifica('reserva 18 PENDENTE cancelada com motivo informado: multa 0.00', v_st = 'CANCELADA' AND v_m = 0.00);
END $$;

-- Quarto liberado: cancelada a reserva 12 (quarto 4, +5..+8), o mesmo período pode ser reservado de novo
SELECT pg_temp.verifica('quarto 4 liberado depois do cancelamento: nova reserva em hoje+5..hoje+8 é aceita',
    pg_temp.nova_reserva(1, 4, 5, 8, 'CONFIRMADA', 900) IS NOT NULL);

-- ------------------------------ 2) cancelar_reserva: erros ------------------------------
SELECT pg_temp.esperar_erro('CALL cancelar_reserva(NULL)',        'HOTEL-001');
SELECT pg_temp.esperar_erro('CALL cancelar_reserva(999999)',      'HOTEL-006');
SELECT pg_temp.esperar_erro('CALL cancelar_reserva(13)',          'HOTEL-007');  -- já CANCELADA
SELECT pg_temp.esperar_erro('CALL cancelar_reserva(17)',          'HOTEL-007');  -- NO-SHOW
SELECT pg_temp.esperar_erro('CALL cancelar_reserva(1)',           'HOTEL-007');  -- CHECK-OUT
SELECT pg_temp.esperar_erro('CALL cancelar_reserva(10)',          'HOTEL-007');  -- CHECK-IN
SELECT pg_temp.esperar_erro('CALL cancelar_reserva(12)',          'HOTEL-007');  -- cancelar duas vezes
SELECT pg_temp.verifica('cancelar duas vezes não duplica a multa',
    (SELECT COUNT(*) FROM cancelamento WHERE id_reserva = 12) = 1);

-- ------------------------------ 3) fazer_checkout: late check-out (RN-08) ------------------------------
-- D = 200; saída prevista = hoje; diárias 600; sem consumo; sem fidelidade
SELECT pg_temp.checkout_ok(0, CURRENT_DATE + TIME '12:00:00', 0, 600, 0);   -- limite: sem taxa
SELECT pg_temp.checkout_ok(0, CURRENT_DATE + TIME '12:00:01', 0, 700, 0);   -- 1 segundo depois: 50% = 100
SELECT pg_temp.checkout_ok(0, CURRENT_DATE + TIME '18:00:00', 0, 700, 0);   -- limite: ainda 50%
SELECT pg_temp.checkout_ok(0, CURRENT_DATE + TIME '18:00:01', 0, 800, 0);   -- 1 segundo depois: 100% = 200
SELECT pg_temp.checkout_ok(0, (CURRENT_DATE - 1) + TIME '15:00', 0, 600, 0); -- saída antecipada: sem taxa, sem estorno
SELECT pg_temp.checkout_ok(0, CURRENT_DATE + TIME '11:00', 180, 780, 0);    -- consumo de 180 entra no total

-- ------------------------------ 4) fazer_checkout: fidelidade (RN-05) ------------------------------
SELECT pg_temp.checkout_ok( 4, CURRENT_DATE + TIME '11:00', 0, 600,  0);    -- 4 estadias: sem desconto
SELECT pg_temp.checkout_ok( 5, CURRENT_DATE + TIME '11:00', 0, 570,  5);    -- 5: 5%  (600 - 30)
SELECT pg_temp.checkout_ok( 9, CURRENT_DATE + TIME '11:00', 0, 570,  5);    -- 9: 5%
SELECT pg_temp.checkout_ok(10, CURRENT_DATE + TIME '11:00', 0, 540, 10);    -- 10: 10% (600 - 60)
SELECT pg_temp.checkout_ok(10, CURRENT_DATE + TIME '12:00:01', 0, 640, 10); -- taxa usa a diária cheia: 540 + 100
SELECT pg_temp.checkout_ok( 5, CURRENT_DATE + TIME '11:00', 100, 670,  5);  -- desconto só nas diárias: 570 + 100

-- ------------------------------ 5) fazer_checkout: erros ------------------------------
SELECT pg_temp.checkout_erro(CURRENT_DATE + TIME '11:00',        599.99, 'HOTEL-009');  -- 1 centavo a menos
SELECT pg_temp.checkout_erro(CURRENT_DATE + TIME '12:00:01',     699.99, 'HOTEL-009');  -- com taxa, 1 centavo a menos
SELECT pg_temp.checkout_erro((CURRENT_DATE + 1) + TIME '08:00',  600,    'HOTEL-012');  -- dia posterior ao previsto
SELECT pg_temp.checkout_erro((CURRENT_DATE - 4) + TIME '08:00',  600,    'HOTEL-001');  -- saída antes do check-in
SELECT pg_temp.esperar_erro('CALL fazer_checkout(NULL, 100)',               'HOTEL-001');
SELECT pg_temp.esperar_erro('CALL fazer_checkout(10, NULL)',                'HOTEL-001');
SELECT pg_temp.esperar_erro('CALL fazer_checkout(10, -1)',                  'HOTEL-001');
SELECT pg_temp.esperar_erro('CALL fazer_checkout(999999, 100)',             'HOTEL-006');
SELECT pg_temp.esperar_erro('CALL fazer_checkout(1, 5000)',                 'HOTEL-007');  -- já CHECK-OUT
SELECT pg_temp.esperar_erro('CALL fazer_checkout(11, 5000)',                'HOTEL-007');  -- CONFIRMADA

-- Dados de exemplo: reserva 10 (CHECK-IN, 4 noites, bruto 1200, consumos 70 + 45 = 115) => final 1315,00
SELECT pg_temp.esperar_erro('CALL fazer_checkout(10, 1314.99, LOCALTIMESTAMP)', 'HOTEL-009');
DO $$
DECLARE r RECORD;
BEGIN
    CALL fazer_checkout(10, 1315.00, CURRENT_DATE + TIME '10:00');
    SELECT status_reserva, valor_final_pago, percentual_desconto INTO r FROM reserva WHERE id_reserva = 10;
    PERFORM pg_temp.verifica('reserva 10: check-out com valor exato (1315,00) aceito',
                             r.status_reserva = 'CHECK-OUT' AND r.valor_final_pago = 1315.00 AND r.percentual_desconto = 0);
END $$;
SELECT pg_temp.esperar_erro('CALL fazer_checkout(10, 5000)', 'HOTEL-007');          -- segundo check-out da mesma reserva

ROLLBACK;

-- ------------------------------ 6) nada vazou (as procedures não fazem COMMIT) ------------------------------
DO $$
BEGIN
    IF (SELECT COUNT(*) FROM reserva) <> 18
       OR (SELECT COUNT(*) FROM cancelamento) <> 5
       OR (SELECT status_reserva FROM reserva WHERE id_reserva = 12) <> 'CONFIRMADA'
       OR (SELECT status_reserva FROM reserva WHERE id_reserva = 10) <> 'CHECK-IN' THEN
        RAISE EXCEPTION 'FALHA: o ROLLBACK não restaurou os dados de exemplo (alguma rotina fez COMMIT?)';
    END IF;
    RAISE NOTICE 'OK    ROLLBACK restaurou os dados de exemplo';
    RAISE NOTICE 'TODOS OS TESTES DAS PROCEDURES PASSARAM';
END $$;

-- ---------------------------------------------------------------------------------------------
-- Concorrência (manual, duas sessões psql A e B), com a reserva 12 (CONFIRMADA):
--   A: BEGIN;  CALL cancelar_reserva(12);                   -- ainda NÃO dá COMMIT
--   B: BEGIN;  CALL cancelar_reserva(12);                   -- fica ESPERANDO o lock da reserva
--   A: COMMIT;
--   B: ERROR: HOTEL-007: a reserva 12 está CANCELADA ...    -- B então: ROLLBACK;
--   Confira: SELECT COUNT(*) FROM cancelamento WHERE id_reserva = 12;   -- 1 (uma multa só)
--   Desfazer o experimento:
--      DELETE FROM cancelamento WHERE id_reserva = 12;
--      UPDATE reserva SET status_reserva = 'CONFIRMADA' WHERE id_reserva = 12;
-- Mutação sugerida: remova "FOR UPDATE" de cancelar_reserva e repita: B passa a gravar uma 2ª multa
-- (ou estoura uk_cancelamento_reserva), provando que a trava é o que serializa.
-- Mesmo roteiro vale para fazer_checkout com uma reserva em CHECK-IN.
-- ---------------------------------------------------------------------------------------------
