-- test_trigger_sobreposicao.sql
-- Testa trg_reserva_sobreposicao com INSERT/UPDATE DIRETO na tabela (sem procedure).
-- Pré-requisito: 01_ddl.sql, 02_inserts.sql e procedures/postgresql_procedures.sql já carregados.
-- Tudo roda dentro de uma transação desfeita no final (o banco volta ao estado original).
--
-- Com Docker (container do docker-compose.yml):
--   docker exec -i hotelhost-postgres psql -U hotel -d hotel -v ON_ERROR_STOP=1 < tests/test_trigger_sobreposicao.sql
-- Sucesso = termina sem ERROR e imprime "TODOS OS TESTES PASSARAM".
--
-- Quarto 7 (302) não tem reservas nos dados de exemplo e é usado nos cenários novos.
-- Os cenários com quartos 1 e 4 usam as reservas 11 (+10..+13) e 18 (+20..+22) do 02_inserts.sql.
\set ON_ERROR_STOP on
BEGIN;

CREATE FUNCTION pg_temp.sql_reserva(p_quarto INT, p_ent INT, p_sai INT, p_status TEXT) RETURNS TEXT AS $$
    SELECT format('INSERT INTO reserva (id_hospede, id_quarto, data_entrada_prevista, data_saida_prevista, status_reserva, valor_total_bruto)
                   VALUES (1, %s, CURRENT_DATE + (%s), CURRENT_DATE + (%s), %L, 100.00)',
                  p_quarto, p_ent, p_sai, p_status)
$$ LANGUAGE sql;

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

CREATE FUNCTION pg_temp.esperar_ok(p_sql TEXT) RETURNS VOID AS $$
BEGIN
    EXECUTE p_sql;
    RAISE NOTICE 'OK    aceitou: %', regexp_replace(p_sql, '\s+', ' ', 'g');
END;
$$ LANGUAGE plpgsql;

-- 0) O trigger existe e está habilitado
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger
                   WHERE tgname = 'trg_reserva_sobreposicao'
                     AND tgrelid = 'reserva'::regclass
                     AND tgenabled <> 'D' AND NOT tgisinternal) THEN
        RAISE EXCEPTION 'FALHA: trg_reserva_sobreposicao não existe ou está desabilitado';
    END IF;
    RAISE NOTICE 'OK    trigger trg_reserva_sobreposicao presente';
END $$;

-- 1) Caminho feliz e sobreposições no quarto 7 (INSERT direto)
SELECT pg_temp.esperar_ok  (pg_temp.sql_reserva(7, 30, 33, 'CONFIRMADA'));              -- base [30,33)
SELECT pg_temp.esperar_erro(pg_temp.sql_reserva(7, 30, 33, 'CONFIRMADA'), 'HOTEL-005'); -- idêntica
SELECT pg_temp.esperar_erro(pg_temp.sql_reserva(7, 32, 35, 'CONFIRMADA'), 'HOTEL-005'); -- 1 noite de sobreposição
SELECT pg_temp.esperar_erro(pg_temp.sql_reserva(7, 28, 31, 'CONFIRMADA'), 'HOTEL-005'); -- 1 noite, pelo outro lado
SELECT pg_temp.esperar_erro(pg_temp.sql_reserva(7, 31, 32, 'CONFIRMADA'), 'HOTEL-005'); -- contida na base
SELECT pg_temp.esperar_erro(pg_temp.sql_reserva(7, 29, 34, 'CONFIRMADA'), 'HOTEL-005'); -- contém a base
SELECT pg_temp.esperar_erro(pg_temp.sql_reserva(7, 31, 34, 'PENDENTE'),   'HOTEL-005'); -- PENDENTE também é checada
SELECT pg_temp.esperar_erro(pg_temp.sql_reserva(7, 31, 34, 'CHECK-IN'),   'HOTEL-005'); -- CHECK-IN também

-- 2) Fronteira: sair e entrar no mesmo dia é permitido
SELECT pg_temp.esperar_ok(pg_temp.sql_reserva(7, 33, 36, 'CONFIRMADA'));  -- entra no dia em que a base sai
SELECT pg_temp.esperar_ok(pg_temp.sql_reserva(7, 27, 30, 'CONFIRMADA'));  -- sai no dia em que a base entra

-- 3) Outro quarto, mesmas datas: permitido
SELECT pg_temp.esperar_ok(pg_temp.sql_reserva(6, 30, 33, 'CONFIRMADA'));

-- 4) CANCELADA e NO-SHOW não bloqueiam (mesmas datas da base)
SELECT pg_temp.esperar_ok(pg_temp.sql_reserva(7, 30, 33, 'CANCELADA'));
SELECT pg_temp.esperar_ok(pg_temp.sql_reserva(7, 30, 33, 'NO-SHOW'));

-- 5) UPDATE direto: mover datas para cima de outra reserva ativa
SELECT pg_temp.esperar_erro(
    'UPDATE reserva SET data_entrada_prevista = CURRENT_DATE + 32, data_saida_prevista = CURRENT_DATE + 35
      WHERE id_quarto = 7 AND data_entrada_prevista = CURRENT_DATE + 33 AND status_reserva = ''CONFIRMADA''',
    'HOTEL-005');

-- 6) UPDATE direto: reativar reserva CANCELADA sobre período ocupado
SELECT pg_temp.esperar_erro(
    'UPDATE reserva SET status_reserva = ''CONFIRMADA''
      WHERE id_quarto = 7 AND status_reserva = ''CANCELADA'' AND data_entrada_prevista = CURRENT_DATE + 30',
    'HOTEL-005');

-- 7) UPDATE direto: trocar o quarto para um quarto ocupado no período
SELECT pg_temp.esperar_erro(
    'UPDATE reserva SET id_quarto = 7
      WHERE id_quarto = 6 AND data_entrada_prevista = CURRENT_DATE + 30 AND status_reserva = ''CONFIRMADA''',
    'HOTEL-005');

-- 8) UPDATE legítimos não podem ser barrados (a própria linha é ignorada)
SELECT pg_temp.esperar_ok('UPDATE reserva SET valor_total_bruto = valor_total_bruto WHERE id_reserva = 10');             -- CHECK-IN em andamento
SELECT pg_temp.esperar_ok('UPDATE reserva SET data_saida_prevista = CURRENT_DATE + 12 WHERE id_reserva = 11');            -- encurta a própria reserva
SELECT pg_temp.esperar_ok('UPDATE reserva SET status_reserva = ''CHECK-IN'' WHERE id_reserva = 12');                      -- CONFIRMADA -> CHECK-IN, mesmas datas
SELECT pg_temp.esperar_ok('UPDATE reserva SET status_reserva = ''CANCELADA'' WHERE id_quarto = 7 AND data_entrada_prevista = CURRENT_DATE + 33');

-- 9) Fronteiras sobre os dados de exemplo
--    quarto 1, reserva 11: [+10,+13)  (encurtada para [+10,+12) no passo 8)
SELECT pg_temp.esperar_ok  (pg_temp.sql_reserva(1, 12, 14, 'CONFIRMADA'));              -- começa quando a 11 (encurtada) termina
SELECT pg_temp.esperar_erro(pg_temp.sql_reserva(1, 11, 13, 'CONFIRMADA'), 'HOTEL-005');
--    quarto 4, reserva 18 PENDENTE: [+20,+22)
SELECT pg_temp.esperar_erro(pg_temp.sql_reserva(4, 21, 23, 'CONFIRMADA'), 'HOTEL-005');
SELECT pg_temp.esperar_ok  (pg_temp.sql_reserva(4, 22, 25, 'CONFIRMADA'));
--    quarto 5, reserva 10 CHECK-IN hoje-2..hoje+2: hóspede em casa bloqueia
SELECT pg_temp.esperar_erro(pg_temp.sql_reserva(5, 1, 4, 'CONFIRMADA'), 'HOTEL-005');

-- 10) Invariante global: nenhum par de reservas ativas sobrepostas no mesmo quarto
DO $$
DECLARE n INT;
BEGIN
    SELECT COUNT(*) INTO n
    FROM reserva a
    JOIN reserva b ON b.id_quarto = a.id_quarto AND a.id_reserva < b.id_reserva
    WHERE a.status_reserva IN ('PENDENTE', 'CONFIRMADA', 'CHECK-IN')
      AND b.status_reserva IN ('PENDENTE', 'CONFIRMADA', 'CHECK-IN')
      AND a.data_entrada_prevista < b.data_saida_prevista
      AND a.data_saida_prevista   > b.data_entrada_prevista;
    IF n > 0 THEN
        RAISE EXCEPTION 'FALHA: % par(es) de reservas ativas sobrepostas', n;
    END IF;
    RAISE NOTICE 'OK    invariante: nenhuma sobreposição de reservas ativas';
    RAISE NOTICE 'TODOS OS TESTES PASSARAM';
END $$;

ROLLBACK;

-- ---------------------------------------------------------------------------------------------
-- Teste manual de concorrência (duas sessões, psql A e psql B):
--   A: BEGIN;
--      INSERT INTO reserva (id_hospede,id_quarto,data_entrada_prevista,data_saida_prevista,status_reserva,valor_total_bruto)
--      VALUES (1,7,CURRENT_DATE+50,CURRENT_DATE+53,'CONFIRMADA',100);      -- ainda NÃO dá COMMIT
--   B: BEGIN;
--      INSERT ... mesmo quarto 7, mesmas datas;                            -- fica ESPERANDO o lock do quarto
--   A: COMMIT;
--   B: recebe ERROR: HOTEL-005: conflito de datas ...   -> só uma reserva foi gravada.
--   Limpeza: DELETE FROM reserva WHERE id_quarto = 7 AND data_entrada_prevista = CURRENT_DATE + 50;
-- Mutação sugerida: remova o "FOR UPDATE" da função e repita; B passa a gravar as duas reservas.
-- ---------------------------------------------------------------------------------------------
