-- postgresql_procedures.sql
-- Hotel Host · PostgreSQL 17 · procedures e triggers (PL/pgSQL)
--
-- Ordem de carga: 01_ddl.sql -> 02_inserts.sql -> este arquivo -> 04_indices.sql
--   psql -v ON_ERROR_STOP=1 -f procedures/postgresql_procedures.sql
-- O arquivo é idempotente (CREATE OR REPLACE / DROP TRIGGER IF EXISTS).
--
-- Conteúdo:
--   1) cancelar_reserva(...)  procedure  RN-04 (multa por faixa de dias; NO-SHOW)   altera RESERVA e CANCELAMENTO
--   2) fazer_checkout(...)    procedure  RN-05, RN-08, RN-09 (fidelidade, late check-out, pagamento) altera RESERVA
--   3) trg_reserva_sobreposicao  trigger  RN-02 (anti-overbooking, vale para INSERT/UPDATE direto)
--
-- Códigos de erro de negócio (formato do projeto, regras.md seção 6; todos com ERRCODE 'P0001'):
--   HOTEL-001 parâmetro inválido (nulo, negativo)        HOTEL-007 transição de status inválida
--   HOTEL-005 conflito de datas com outra reserva        HOTEL-009 pagamento insuficiente no check-out
--   HOTEL-006 reserva não encontrada                     HOTEL-012 check-out depois do dia previsto de saída
--
-- REGRA CRÍTICA: nenhuma rotina deste arquivo faz COMMIT nem ROLLBACK; quem chama decide a transação.
-- Um erro de negócio (RAISE EXCEPTION) desfaz tudo o que a chamada já tinha feito.
--
-- Limitações do modelo atual (01_ddl.sql), documentadas de propósito:
--   * Não existe tabela PAGAMENTO: o sinal de 30% (RN-10) e o estorno não são modelados; o saldo do
--     check-out é o valor final inteiro.
--   * QUARTO só tem status_manutencao (booleano): não há status OCUPADO/LIMPEZA. "Liberar o quarto"
--     acontece porque a reserva deixa de ser ativa (CANCELADA, NO-SHOW, CHECK-OUT) e o trigger
--     trg_reserva_sobreposicao só considera PENDENTE, CONFIRMADA e CHECK-IN como ocupando o quarto.
--   * RESERVA não guarda a diária: D = valor_total_bruto / noites (os dados de exemplo seguem isso).

-- ---------------------------------------------------------------------------------------------
-- Procedure 1: cancelar_reserva
--
-- Regra implementada (RN-04, multa de cancelamento por faixa de antecedência):
--   Só reserva PENDENTE ou CONFIRMADA pode ser cancelada (CHECK-IN, CHECK-OUT, CANCELADA e
--   NO-SHOW são recusadas com HOTEL-007). Dias até a entrada = data_entrada_prevista - hoje.
--       7 dias ou mais .......... sem multa                  -> CANCELADA
--       de 2 a 6 dias ........... 50% da primeira diária     -> CANCELADA
--       0 ou 1 dia .............. 100% da primeira diária    -> CANCELADA
--       entrada já passou ....... 100% da primeira diária    -> NO-SHOW (hóspede não apareceu)
--   Primeira diária D = valor_total_bruto / número de noites, arredondada a 2 casas.
--
-- Altera DUAS tabelas na mesma chamada: RESERVA (status) e CANCELAMENTO (lança a multa; a reserva
-- cancelada deixa de ocupar o quarto para o trigger de sobreposição).
--
-- Concorrência: lê a reserva com FOR UPDATE. Duas sessões cancelando a mesma reserva são
-- serializadas: a segunda espera, enxerga o status já alterado e recebe HOTEL-007 (nunca gera
-- duas multas; uk_cancelamento_reserva é a rede de segurança final).
--
-- Parâmetros: p_hoje nulo = CURRENT_DATE (permite testar as fronteiras 7, 6, 2, 1 e 0 dias);
--             p_motivo nulo = texto padrão com a faixa aplicada.
-- Não faz COMMIT/ROLLBACK.
-- ---------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE cancelar_reserva(
    p_id_reserva INTEGER,
    p_hoje       DATE    DEFAULT NULL,
    p_motivo     VARCHAR DEFAULT NULL)
LANGUAGE plpgsql AS $$
DECLARE
    v_hoje   DATE := COALESCE(p_hoje, CURRENT_DATE);
    v_res    RECORD;
    v_noites INTEGER;
    v_diaria NUMERIC;
    v_dias   INTEGER;
    v_multa  NUMERIC(10,2);
    v_status VARCHAR(20);
    v_faixa  VARCHAR(255);
BEGIN
    IF p_id_reserva IS NULL THEN
        RAISE EXCEPTION 'HOTEL-001: o id da reserva é obrigatório' USING ERRCODE = 'P0001';
    END IF;

    -- Trava a linha da reserva: serializa cancelamentos concorrentes da mesma reserva.
    SELECT r.id_reserva, r.status_reserva, r.data_entrada_prevista,
           r.data_saida_prevista, r.valor_total_bruto
    INTO v_res
    FROM reserva r
    WHERE r.id_reserva = p_id_reserva
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'HOTEL-006: reserva % não encontrada', p_id_reserva USING ERRCODE = 'P0001';
    END IF;

    IF COALESCE(v_res.status_reserva, '') NOT IN ('PENDENTE', 'CONFIRMADA') THEN
        RAISE EXCEPTION 'HOTEL-007: a reserva % está % e só reservas PENDENTE ou CONFIRMADA podem ser canceladas',
            p_id_reserva, v_res.status_reserva USING ERRCODE = 'P0001';
    END IF;

    v_noites := v_res.data_saida_prevista - v_res.data_entrada_prevista;   -- >= 1 pelo ck_reserva_datas
    v_diaria := v_res.valor_total_bruto / v_noites;
    v_dias   := v_res.data_entrada_prevista - v_hoje;

    IF v_dias >= 7 THEN
        v_multa := 0;
        v_status := 'CANCELADA';
        v_faixa := format('Cancelado com %s dias de antecedência: sem multa', v_dias);
    ELSIF v_dias >= 2 THEN
        v_multa := ROUND(v_diaria * 0.5, 2);
        v_status := 'CANCELADA';
        v_faixa := format('Cancelado com %s dias de antecedência: 50%% da primeira diária (D = %s)',
                          v_dias, ROUND(v_diaria, 2));
    ELSIF v_dias >= 0 THEN
        v_multa := ROUND(v_diaria, 2);
        v_status := 'CANCELADA';
        v_faixa := format('Cancelado com %s dia(s) de antecedência: 100%% da primeira diária (D = %s)',
                          v_dias, ROUND(v_diaria, 2));
    ELSE
        v_multa := ROUND(v_diaria, 2);
        v_status := 'NO-SHOW';
        v_faixa := format('No-show: entrada já passou sem check-in, 100%% da primeira diária (D = %s)',
                          ROUND(v_diaria, 2));
    END IF;

    -- Tabela 1: muda o status da reserva (libera o quarto para novas reservas).
    UPDATE reserva SET status_reserva = v_status WHERE id_reserva = p_id_reserva;

    -- Tabela 2: lança a multa.
    INSERT INTO cancelamento (id_reserva, taxa_multa_aplicada, motivo_cancelamento)
    VALUES (p_id_reserva, v_multa, COALESCE(p_motivo, v_faixa));
END;
$$;

-- ---------------------------------------------------------------------------------------------
-- Procedure 2: fazer_checkout
--
-- Regras implementadas:
--   RN-08 (late check-out): horário padrão de saída = 12:00 do dia data_saida_prevista.
--         até 12:00:00 ........ sem taxa
--         12:00:01 a 18:00:00 . taxa de 50% da diária
--         depois de 18:00:00 .. taxa de 1 diária inteira
--         Saída antes do dia previsto não gera taxa nem estorno. Saída DEPOIS do dia previsto é
--         recusada (HOTEL-012): a reserva precisa ser prorrogada.
--   RN-05 (fidelidade): desconto sobre as diárias conforme as estadias CHECK-OUT anteriores do
--         hóspede: 0 a 4 -> 0%; 5 a 9 -> 5%; 10 ou mais -> 10%. A taxa de late check-out usa a
--         diária cheia (sem desconto).
--   RN-09 (pagamento): só finaliza se o valor entregue cobrir o valor final (HOTEL-009).
--   Só reserva em CHECK-IN pode fazer check-out (HOTEL-007).
--
--   Valor final = ROUND(valor_total_bruto * (1 - desconto/100) + soma dos consumos + taxa, 2).
--   Troco é assunto do caixa: grava-se o valor final, não o valor entregue.
--
-- Altera RESERVA (status CHECK-OUT, data_checkout_real, percentual_desconto, valor_final_pago) e
-- LÊ CONSUMO_SERVICO e as estadias do hóspede para recalcular o total. (O modelo atual não tem
-- PAGAMENTO nem status de quarto, então esta procedure grava em uma única tabela; ver o cabeçalho.)
--
-- Concorrência: lê a reserva com FOR UPDATE; dois check-outs simultâneos da mesma reserva são
-- serializados e o segundo recebe HOTEL-007.
--
-- Parâmetros: p_data_hora_saida nulo = agora (permite testar 12:00:00, 12:00:01, 18:00:00...).
-- Não faz COMMIT/ROLLBACK.
-- ---------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE fazer_checkout(
    p_id_reserva      INTEGER,
    p_valor_pago      NUMERIC,
    p_data_hora_saida TIMESTAMP DEFAULT NULL)
LANGUAGE plpgsql AS $$
DECLARE
    v_saida     TIMESTAMP := COALESCE(p_data_hora_saida, LOCALTIMESTAMP);
    v_res       RECORD;
    v_noites    INTEGER;
    v_diaria    NUMERIC;
    v_estadias  INTEGER;
    v_desconto  NUMERIC;
    v_consumos  NUMERIC;
    v_taxa      NUMERIC;
    v_final     NUMERIC(10,2);
BEGIN
    IF p_id_reserva IS NULL THEN
        RAISE EXCEPTION 'HOTEL-001: o id da reserva é obrigatório' USING ERRCODE = 'P0001';
    END IF;
    IF p_valor_pago IS NULL OR p_valor_pago < 0 THEN
        RAISE EXCEPTION 'HOTEL-001: o valor pago deve ser informado e não pode ser negativo'
            USING ERRCODE = 'P0001';
    END IF;

    -- Trava a linha da reserva: serializa check-outs concorrentes da mesma reserva.
    SELECT r.id_reserva, r.id_hospede, r.status_reserva, r.data_saida_prevista,
           r.data_entrada_prevista, r.data_checkin_real, r.valor_total_bruto
    INTO v_res
    FROM reserva r
    WHERE r.id_reserva = p_id_reserva
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'HOTEL-006: reserva % não encontrada', p_id_reserva USING ERRCODE = 'P0001';
    END IF;

    IF COALESCE(v_res.status_reserva, '') <> 'CHECK-IN' THEN
        RAISE EXCEPTION 'HOTEL-007: a reserva % está % e só uma reserva em CHECK-IN pode fazer check-out',
            p_id_reserva, v_res.status_reserva USING ERRCODE = 'P0001';
    END IF;

    IF v_saida::DATE > v_res.data_saida_prevista THEN
        RAISE EXCEPTION 'HOTEL-012: check-out em % depois da saída prevista (%): prorrogue a reserva antes',
            v_saida::DATE, v_res.data_saida_prevista USING ERRCODE = 'P0001';
    END IF;

    IF v_res.data_checkin_real IS NOT NULL AND v_saida < v_res.data_checkin_real THEN
        RAISE EXCEPTION 'HOTEL-001: a saída (%) é anterior ao check-in real (%)',
            v_saida, v_res.data_checkin_real USING ERRCODE = 'P0001';
    END IF;

    v_noites := v_res.data_saida_prevista - v_res.data_entrada_prevista;
    v_diaria := v_res.valor_total_bruto / v_noites;

    -- RN-05: fidelidade (estadias concluídas anteriores; a reserva em check-out ainda não conta).
    SELECT COUNT(*) INTO v_estadias
    FROM reserva
    WHERE id_hospede = v_res.id_hospede
      AND status_reserva = 'CHECK-OUT'
      AND id_reserva <> p_id_reserva;

    v_desconto := CASE WHEN v_estadias >= 10 THEN 10
                       WHEN v_estadias >= 5  THEN 5
                       ELSE 0 END;

    -- RN-08: late check-out (limites inclusivos: 12:00:00 e 18:00:00 ainda estão na faixa anterior).
    IF v_saida <= v_res.data_saida_prevista + INTERVAL '12 hours' THEN
        v_taxa := 0;
    ELSIF v_saida <= v_res.data_saida_prevista + INTERVAL '18 hours' THEN
        v_taxa := ROUND(v_diaria * 0.5, 2);
    ELSE
        v_taxa := ROUND(v_diaria, 2);
    END IF;

    SELECT COALESCE(SUM(valor_total_item), 0) INTO v_consumos
    FROM consumo_servico
    WHERE id_reserva = p_id_reserva;

    v_final := ROUND(v_res.valor_total_bruto * (1 - v_desconto / 100.0) + v_consumos + v_taxa, 2);

    -- RN-09: o pagamento precisa cobrir o valor final.
    IF p_valor_pago < v_final THEN
        RAISE EXCEPTION 'HOTEL-009: pagamento insuficiente: valor final % e valor pago %',
            v_final, p_valor_pago USING ERRCODE = 'P0001';
    END IF;

    UPDATE reserva
       SET status_reserva      = 'CHECK-OUT',
           data_checkout_real  = v_saida,
           percentual_desconto = v_desconto,
           valor_final_pago    = v_final
     WHERE id_reserva = p_id_reserva;
END;
$$;

-- ---------------------------------------------------------------------------------------------
-- Trigger: trg_reserva_sobreposicao  (função fn_reserva_sobreposicao)
--
-- Regra implementada (RN-02, anti-overbooking):
--   Um quarto não pode ter duas reservas ATIVAS com períodos sobrepostos.
--   - Reserva ativa = status PENDENTE, CONFIRMADA ou CHECK-IN (as que "seguram" o quarto).
--     CANCELADA, NO-SHOW e CHECK-OUT não bloqueiam.
--   - Intervalo semiaberto [entrada, saída): quem sai no dia 13 libera o quarto
--     para quem entra no dia 13. Há conflito se: entrada_existente < saída_nova
--     E saída_existente > entrada_nova.
--
-- Vale para INSERT e UPDATE diretos na tabela, sem depender de procedure ou aplicação.
-- No UPDATE, só reconfere quando algo relevante muda (quarto, datas, ou a reserva
-- passa de não-ativa para ativa, por exemplo CANCELADA -> CONFIRMADA); atualizar
-- outras colunas (valor_final_pago, check-in real...) não dispara a busca.
--
-- Concorrência: trava a linha do QUARTO (FOR UPDATE) antes de procurar conflito.
-- Duas sessões que reservam o mesmo quarto são serializadas: a segunda espera a
-- primeira terminar e, ao acordar (READ COMMITTED), enxerga a reserva nova e recebe HOTEL-005.
-- ---------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_reserva_sobreposicao() RETURNS TRIGGER AS $$
DECLARE
    v_quarto  INTEGER;
    v_conflito RECORD;
BEGIN
    -- Reserva que não segura o quarto nunca gera conflito.
    IF COALESCE(NEW.status_reserva, '') NOT IN ('PENDENTE', 'CONFIRMADA', 'CHECK-IN') THEN
        RETURN NEW;
    END IF;

    -- UPDATE que não mexe em quarto/datas e já era ativa: nada a rechecar.
    IF TG_OP = 'UPDATE'
       AND COALESCE(OLD.status_reserva, '') IN ('PENDENTE', 'CONFIRMADA', 'CHECK-IN')
       AND NEW.id_quarto = OLD.id_quarto
       AND NEW.data_entrada_prevista = OLD.data_entrada_prevista
       AND NEW.data_saida_prevista = OLD.data_saida_prevista THEN
        RETURN NEW;
    END IF;

    -- Trava o quarto para serializar reservas concorrentes do mesmo quarto.
    SELECT q.id_quarto INTO v_quarto
    FROM quarto q
    WHERE q.id_quarto = NEW.id_quarto
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN NEW;  -- quarto inexistente: a FK fk_reserva_quarto recusa o INSERT/UPDATE
    END IF;

    SELECT r.id_reserva, r.data_entrada_prevista, r.data_saida_prevista
    INTO v_conflito
    FROM reserva r
    WHERE r.id_quarto = NEW.id_quarto
      AND r.id_reserva IS DISTINCT FROM NEW.id_reserva          -- ignora a própria linha
      AND r.status_reserva IN ('PENDENTE', 'CONFIRMADA', 'CHECK-IN')
      AND r.data_entrada_prevista < NEW.data_saida_prevista     -- [entrada, saída): borda não conflita
      AND r.data_saida_prevista   > NEW.data_entrada_prevista
    ORDER BY r.data_entrada_prevista, r.id_reserva
    LIMIT 1;

    IF FOUND THEN
        RAISE EXCEPTION 'HOTEL-005: conflito de datas: o quarto % já tem a reserva % de % a %',
            NEW.id_quarto, v_conflito.id_reserva,
            v_conflito.data_entrada_prevista, v_conflito.data_saida_prevista
            USING ERRCODE = 'P0001';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_reserva_sobreposicao ON reserva;
CREATE TRIGGER trg_reserva_sobreposicao
BEFORE INSERT OR UPDATE ON reserva
FOR EACH ROW EXECUTE FUNCTION fn_reserva_sobreposicao();
