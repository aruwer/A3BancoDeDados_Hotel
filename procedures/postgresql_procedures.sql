-- postgresql_procedures.sql
-- Hotel Host · PostgreSQL 17 · procedures e triggers (PL/pgSQL)
--
-- Ordem de carga: 01_ddl.sql -> 02_inserts.sql -> este arquivo -> 04_indices.sql
--   psql -v ON_ERROR_STOP=1 -f procedures/postgresql_procedures.sql
-- O arquivo é idempotente (CREATE OR REPLACE / DROP TRIGGER IF EXISTS).
--
-- Conteúdo:
--   1) cancelar_reserva(...)  procedure  RN-04 (multa por faixa de dias; NO-SHOW; estorno do sinal) altera RESERVA, CANCELAMENTO e PAGAMENTO
--   2) fazer_checkout(...)    procedure  RN-05, RN-08, RN-09 (fidelidade, late check-out, pagamento) altera RESERVA, QUARTO e PAGAMENTO
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
--   * O sinal de 30% (RN-10) ainda não é lançado (depende de uma procedure registrar_reserva, fora
--     deste escopo), mas cancelar_reserva e fazer_checkout já trabalham com qualquer PAGAMENTO/ESTORNO
--     existente (estorno do sinal no cancelamento; desconto do saldo no check-out).
--   * QUARTO tem status_quarto (DISPONIVEL, OCUPADO, LIMPEZA, MANUTENCAO; decisão D-02). Sem a procedure
--     fazer_checkin (fora deste escopo), nada leva o quarto a OCUPADO: isso é feito por UPDATE direto.
--     fazer_checkout leva o quarto a LIMPEZA. A disponibilidade para reservar continua dependendo só das
--     datas: o trigger trg_reserva_sobreposicao considera PENDENTE, CONFIRMADA e CHECK-IN como ocupando
--     o quarto, e CANCELADA, NO-SHOW e CHECK-OUT como liberando.
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
-- Sinal e estorno (regras.md 4.1, RN-10): sinal pago = PAGAMENTOs - ESTORNOs já lançados da reserva.
--       estorno      = maior valor entre (sinal pago - multa) e 0  -> lançado em PAGAMENTO (tipo ESTORNO,
--                      na mesma forma do último PAGAMENTO da reserva; PIX se não houver nenhum)
--       valor devido = maior valor entre (multa - sinal pago) e 0 -> gravado em CANCELAMENTO.valor_devido
--                      (a cobrança em si está fora do escopo). Sem sinal pago, não há estorno.
--
-- Altera TRÊS tabelas na mesma chamada: RESERVA (status), CANCELAMENTO (multa e valor devido) e
-- PAGAMENTO (estorno, só quando há algo a devolver). A reserva cancelada deixa de ocupar o quarto
-- para o trigger de sobreposição.
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
    v_pago    NUMERIC(10,2);
    v_estorno NUMERIC(10,2);
    v_devido  NUMERIC(10,2);
    v_forma   VARCHAR(20);
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

    -- Sinal efetivamente em poder do hotel: pagamentos - estornos já lançados.
    SELECT COALESCE(SUM(CASE tipo WHEN 'PAGAMENTO' THEN valor ELSE -valor END), 0)
    INTO v_pago
    FROM pagamento
    WHERE id_reserva = p_id_reserva;

    v_estorno := GREATEST(v_pago - v_multa, 0);   -- devolve o que sobra do sinal depois da multa
    v_devido  := GREATEST(v_multa - v_pago, 0);   -- parte da multa que o sinal não cobriu

    -- Tabela 2: lança a multa e o valor devido.
    INSERT INTO cancelamento (id_reserva, taxa_multa_aplicada, valor_devido, motivo_cancelamento)
    VALUES (p_id_reserva, v_multa, v_devido, COALESCE(p_motivo, v_faixa));

    -- Tabela 3: devolve o sinal que sobrou (estorno na mesma forma do último pagamento).
    IF v_estorno > 0 THEN
        SELECT p.forma INTO v_forma
        FROM pagamento p
        WHERE p.id_reserva = p_id_reserva AND p.tipo = 'PAGAMENTO'
        ORDER BY p.data_hora DESC, p.id_pagamento DESC
        LIMIT 1;

        INSERT INTO pagamento (id_reserva, tipo, forma, valor)
        VALUES (p_id_reserva, 'ESTORNO', COALESCE(v_forma, 'PIX'), v_estorno);
    END IF;
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
--   RN-09 (pagamento): saldo = valor final - (PAGAMENTOs - ESTORNOs já lançados). O valor entregue
--         precisa cobrir o saldo (HOTEL-009); a procedure lança um PAGAMENTO do valor do saldo
--         (troco é assunto do caixa). Se o saldo já for zero ou negativo, não lança nada.
--   Só reserva em CHECK-IN pode fazer check-out (HOTEL-007).
--
--   Valor final = ROUND(valor_total_bruto * (1 - desconto/100) + soma dos consumos + taxa, 2).
--
--   Ciclo do quarto (D-02): o check-out leva o quarto a LIMPEZA; a volta a DISPONIVEL é um UPDATE da
--   governança. Quarto em MANUTENCAO não é alterado (manutenção iniciada com o hóspede ainda lá).
--
-- Altera TRÊS tabelas na mesma chamada: RESERVA (status CHECK-OUT, data_checkout_real,
-- percentual_desconto, taxa_checkout e valor_final_pago recalculados), QUARTO (status_quarto =
-- LIMPEZA) e PAGAMENTO (lança a quitação). Lê CONSUMO_SERVICO e as estadias do hóspede para
-- recalcular o total. A taxa e o valor final ficam em colunas próprias da reserva, então as
-- consultas de receita não precisam refazer a conta.
--
-- Concorrência: lê a reserva com FOR UPDATE; dois check-outs simultâneos da mesma reserva são
-- serializados e o segundo recebe HOTEL-007 (nunca grava duas quitações).
--
-- Parâmetros: p_data_hora_saida nulo = agora (permite testar 12:00:00, 12:00:01, 18:00:00...);
--             p_forma_pagamento: DINHEIRO, PIX, CARTAO_CREDITO ou CARTAO_DEBITO (padrão PIX).
-- Não faz COMMIT/ROLLBACK.
-- ---------------------------------------------------------------------------------------------
-- A assinatura ganhou o parâmetro p_forma_pagamento: remove a versão antiga (3 parâmetros) para não
-- deixar uma sobrecarga que tornaria a chamada com 3 argumentos ambígua.
DROP PROCEDURE IF EXISTS fazer_checkout(INTEGER, NUMERIC, TIMESTAMP);

CREATE OR REPLACE PROCEDURE fazer_checkout(
    p_id_reserva      INTEGER,
    p_valor_pago      NUMERIC,
    p_data_hora_saida TIMESTAMP DEFAULT NULL,
    p_forma_pagamento VARCHAR   DEFAULT 'PIX')
LANGUAGE plpgsql AS $$
DECLARE
    v_saida      TIMESTAMP := COALESCE(p_data_hora_saida, LOCALTIMESTAMP);
    v_res        RECORD;
    v_noites     INTEGER;
    v_diaria     NUMERIC;
    v_estadias   INTEGER;
    v_desconto   NUMERIC;
    v_consumos   NUMERIC;
    v_taxa       NUMERIC(10,2);
    v_final      NUMERIC(10,2);
    v_ja_pago    NUMERIC;
    v_saldo      NUMERIC(10,2);
BEGIN
    IF p_id_reserva IS NULL THEN
        RAISE EXCEPTION 'HOTEL-001: o id da reserva é obrigatório' USING ERRCODE = 'P0001';
    END IF;
    IF p_valor_pago IS NULL OR p_valor_pago < 0 THEN
        RAISE EXCEPTION 'HOTEL-001: o valor pago deve ser informado e não pode ser negativo'
            USING ERRCODE = 'P0001';
    END IF;
    IF p_forma_pagamento IS NULL
       OR p_forma_pagamento NOT IN ('DINHEIRO', 'PIX', 'CARTAO_CREDITO', 'CARTAO_DEBITO') THEN
        RAISE EXCEPTION 'HOTEL-001: forma de pagamento inválida (%): use DINHEIRO, PIX, CARTAO_CREDITO ou CARTAO_DEBITO',
            p_forma_pagamento USING ERRCODE = 'P0001';
    END IF;

    -- Trava a linha da reserva: serializa check-outs concorrentes da mesma reserva.
    SELECT r.id_reserva, r.id_hospede, r.id_quarto, r.status_reserva, r.data_saida_prevista,
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

    -- RN-09: saldo = valor final - (pagamentos - estornos já lançados).
    SELECT COALESCE(SUM(CASE tipo WHEN 'PAGAMENTO' THEN valor ELSE -valor END), 0) INTO v_ja_pago
    FROM pagamento
    WHERE id_reserva = p_id_reserva;

    v_saldo := v_final - v_ja_pago;

    IF p_valor_pago < GREATEST(v_saldo, 0) THEN
        RAISE EXCEPTION 'HOTEL-009: pagamento insuficiente: saldo % (valor final %, já pago %) e valor pago %',
            v_saldo, v_final, v_ja_pago, p_valor_pago USING ERRCODE = 'P0001';
    END IF;

    -- Tabela 1: finaliza a reserva e grava a taxa e o total recalculados (colunas próprias).
    UPDATE reserva
       SET status_reserva      = 'CHECK-OUT',
           data_checkout_real  = v_saida,
           percentual_desconto = v_desconto,
           taxa_checkout       = v_taxa,
           valor_final_pago    = v_final
     WHERE id_reserva = p_id_reserva;

    -- Tabela 2: o quarto entra em LIMPEZA (D-02). MANUTENCAO é preservado.
    UPDATE quarto
       SET status_quarto = 'LIMPEZA'
     WHERE id_quarto = v_res.id_quarto
       AND status_quarto <> 'MANUTENCAO';

    -- Tabela 3: lança a quitação do saldo (troco não é lançado). Saldo zerado: nada a lançar.
    IF v_saldo > 0 THEN
        INSERT INTO pagamento (id_reserva, tipo, forma, valor)
        VALUES (p_id_reserva, 'PAGAMENTO', p_forma_pagamento, v_saldo);
    END IF;
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
