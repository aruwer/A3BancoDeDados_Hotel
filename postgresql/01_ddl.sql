-- 01_ddl.sql
-- Banco de Dados: PostgreSQL 17
-- Atende aos Critérios: 7 Entidades, Estados Claros na Reserva e Tabela Associativa N:M.
-- Convenção de constraints: pk_ (chave primária), fk_ (chave estrangeira),
-- uk_ (única), ck_ (check). Toda FK declara ON DELETE explicitamente.

CREATE TABLE hospede (
    id_hospede     SERIAL,
    cpf            VARCHAR(11)  NOT NULL,
    nome_completo  VARCHAR(100) NOT NULL,
    email          VARCHAR(100) NOT NULL,
    telefone       VARCHAR(20),
    data_cadastro  DATE         NOT NULL DEFAULT CURRENT_DATE,
    CONSTRAINT pk_hospede PRIMARY KEY (id_hospede),
    CONSTRAINT uk_hospede_cpf UNIQUE (cpf),
    CONSTRAINT uk_hospede_email UNIQUE (email)
);

CREATE TABLE categoria_quarto (
    id_categoria       SERIAL,
    nome_categoria     VARCHAR(50)   NOT NULL,
    capacidade_maxima  INT           NOT NULL,
    valor_diaria_base  DECIMAL(10,2) NOT NULL,
    CONSTRAINT pk_categoria_quarto PRIMARY KEY (id_categoria),
    CONSTRAINT ck_categoria_capacidade CHECK (capacidade_maxima > 0),
    CONSTRAINT ck_categoria_valor CHECK (valor_diaria_base > 0)
);

CREATE TABLE quarto (
    id_quarto          SERIAL,
    id_categoria       INT         NOT NULL,
    numero_quarto      VARCHAR(10) NOT NULL,
    andar              INT,
    -- Ciclo (regras.md seção 3): DISPONIVEL -> OCUPADO (check-in) -> LIMPEZA (check-out) -> DISPONIVEL (governança).
    -- MANUTENCAO é definido e removido por UPDATE direto. Substitui o antigo booleano status_manutencao (decisão D-02).
    status_quarto      VARCHAR(20) NOT NULL DEFAULT 'DISPONIVEL',
    CONSTRAINT pk_quarto PRIMARY KEY (id_quarto),
    CONSTRAINT uk_quarto_numero UNIQUE (numero_quarto),
    CONSTRAINT ck_quarto_status CHECK (status_quarto IN ('DISPONIVEL', 'OCUPADO', 'LIMPEZA', 'MANUTENCAO')),
    CONSTRAINT fk_quarto_categoria FOREIGN KEY (id_categoria)
        REFERENCES categoria_quarto(id_categoria) ON DELETE RESTRICT
);

CREATE TABLE reserva (
    id_reserva             SERIAL,
    id_hospede             INT           NOT NULL,
    id_quarto              INT           NOT NULL,
    data_reserva           TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
    data_entrada_prevista  DATE          NOT NULL,
    data_saida_prevista    DATE          NOT NULL,
    data_checkin_real      TIMESTAMP,
    data_checkout_real     TIMESTAMP,
    status_reserva         VARCHAR(20)   NOT NULL DEFAULT 'PENDENTE',
    valor_total_bruto      DECIMAL(10,2) NOT NULL,
    percentual_desconto    DECIMAL(5,2)  DEFAULT 0,
    valor_final_pago       DECIMAL(10,2),   -- gravado por fazer_checkout: diárias com desconto + consumos + taxa_checkout
    taxa_checkout          DECIMAL(10,2) NOT NULL DEFAULT 0,   -- late check-out (RN-08); 0 até o check-out acontecer
    CONSTRAINT pk_reserva PRIMARY KEY (id_reserva),
    CONSTRAINT fk_reserva_hospede FOREIGN KEY (id_hospede)
        REFERENCES hospede(id_hospede) ON DELETE RESTRICT,
    CONSTRAINT fk_reserva_quarto FOREIGN KEY (id_quarto)
        REFERENCES quarto(id_quarto) ON DELETE RESTRICT,
    CONSTRAINT ck_reserva_datas CHECK (data_saida_prevista > data_entrada_prevista),
    CONSTRAINT ck_reserva_checkout CHECK (data_checkout_real >= data_checkin_real),
    CONSTRAINT ck_reserva_desconto CHECK (percentual_desconto BETWEEN 0 AND 100),
    CONSTRAINT ck_reserva_valor_bruto CHECK (valor_total_bruto >= 0),
    CONSTRAINT ck_reserva_taxa_checkout CHECK (taxa_checkout >= 0),
    CONSTRAINT ck_reserva_status CHECK (status_reserva IN (
        'PENDENTE', 'CONFIRMADA', 'CHECK-IN', 'CHECK-OUT', 'CANCELADA', 'NO-SHOW'
    ))
);

CREATE TABLE cancelamento (
    id_cancelamento      SERIAL,
    id_reserva           INT           NOT NULL,
    data_cancelamento    TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
    taxa_multa_aplicada  DECIMAL(10,2) NOT NULL,
    valor_devido         DECIMAL(10,2) NOT NULL DEFAULT 0,   -- parte da multa que o sinal não cobriu (regras.md 4.1)
    motivo_cancelamento  VARCHAR(255),
    CONSTRAINT pk_cancelamento PRIMARY KEY (id_cancelamento),
    CONSTRAINT uk_cancelamento_reserva UNIQUE (id_reserva),
    CONSTRAINT fk_cancelamento_reserva FOREIGN KEY (id_reserva)
        REFERENCES reserva(id_reserva) ON DELETE CASCADE,
    CONSTRAINT ck_cancelamento_taxa CHECK (taxa_multa_aplicada >= 0),
    CONSTRAINT ck_cancelamento_devido CHECK (valor_devido >= 0)
);

-- RESOLUÇÃO N:M (Reserva x Serviços Consumidos)
CREATE TABLE servico (
    id_servico      SERIAL,
    nome_servico    VARCHAR(100)  NOT NULL,
    valor_unitario  DECIMAL(10,2) NOT NULL,
    CONSTRAINT pk_servico PRIMARY KEY (id_servico),
    CONSTRAINT ck_servico_valor CHECK (valor_unitario >= 0)
);

CREATE TABLE consumo_servico (
    id_consumo        SERIAL,
    id_reserva        INT           NOT NULL,
    id_servico        INT           NOT NULL,
    quantidade        INT           NOT NULL,
    data_consumo      TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
    valor_total_item  DECIMAL(10,2) NOT NULL,
    CONSTRAINT pk_consumo_servico PRIMARY KEY (id_consumo),
    CONSTRAINT fk_consumo_reserva FOREIGN KEY (id_reserva)
        REFERENCES reserva(id_reserva) ON DELETE CASCADE,
    CONSTRAINT fk_consumo_servico FOREIGN KEY (id_servico)
        REFERENCES servico(id_servico) ON DELETE RESTRICT,
    CONSTRAINT ck_consumo_quantidade CHECK (quantidade > 0)
);

-- PAGAMENTO: sinal, quitação do check-out e estorno (valor sempre positivo; o tipo indica o sentido).
-- Alimentada por fazer_checkout. FK com RESTRICT: o histórico financeiro não some com a reserva.
CREATE TABLE Pagamento (
    id_pagamento SERIAL,
    id_reserva INT NOT NULL,
    tipo VARCHAR(10) NOT NULL,
    forma VARCHAR(20) NOT NULL,
    valor DECIMAL(10,2) NOT NULL,
    data_hora TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_pagamento PRIMARY KEY (id_pagamento),
    CONSTRAINT fk_pagamento_reserva FOREIGN KEY (id_reserva)
    REFERENCES Reserva(id_reserva) ON DELETE RESTRICT,
    CONSTRAINT ck_pagamento_tipo CHECK (tipo IN ('PAGAMENTO', 'ESTORNO')),
    CONSTRAINT ck_pagamento_forma CHECK (forma IN ('DINHEIRO', 'PIX', 'CARTAO_CREDITO', 'CARTAO_DEBITO')),
    CONSTRAINT ck_pagamento_valor CHECK (valor > 0)
);
