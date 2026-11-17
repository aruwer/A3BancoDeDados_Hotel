-- postgresql_procedures.sql
-- Hotel Host · PostgreSQL 17 · procedures e triggers (PL/pgSQL)
--
-- Ordem de carga: 01_ddl.sql -> 02_inserts.sql -> este arquivo -> 04_indices.sql
--   psql -v ON_ERROR_STOP=1 -f procedures/postgresql_procedures.sql
-- O arquivo é idempotente (CREATE OR REPLACE / DROP TRIGGER IF EXISTS).
--
-- Código de erro de negócio (formato do projeto, regras.md seção 6):
--   HOTEL-005  conflito de datas com outra reserva do quarto
-- Nenhuma rotina deste arquivo faz COMMIT: quem chama decide a transação.

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
