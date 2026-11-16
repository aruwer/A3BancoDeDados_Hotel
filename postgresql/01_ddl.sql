-- 01_ddl.sql
-- Banco de Dados: PostgreSQL 17
-- Atende aos Critérios: 7 Entidades, Estados Claros na Reserva e Tabela Associativa N:M.
-- Convenção de constraints: pk_ (chave primária), fk_ (chave estrangeira),
-- uk_ (única), ck_ (check). Toda FK declara ON DELETE explicitamente.

CREATE TABLE Hospede (
    id_hospede SERIAL,
    cpf VARCHAR(11) NOT NULL,
    nome_completo VARCHAR(100) NOT NULL,
    email VARCHAR(100) NOT NULL,
    telefone VARCHAR(20),
    data_cadastro DATE DEFAULT CURRENT_DATE,
    CONSTRAINT pk_hospede PRIMARY KEY (id_hospede),
    CONSTRAINT uk_hospede_cpf UNIQUE (cpf),
    CONSTRAINT uk_hospede_email UNIQUE (email)
);

CREATE TABLE Categoria_Quarto (
    id_categoria SERIAL,
    nome_categoria VARCHAR(50) NOT NULL,
    capacidade_maxima INT NOT NULL,
    valor_diaria_base DECIMAL(10,2) NOT NULL,
    CONSTRAINT pk_categoria_quarto PRIMARY KEY (id_categoria),
    CONSTRAINT ck_categoria_capacidade CHECK (capacidade_maxima > 0),
    CONSTRAINT ck_categoria_valor CHECK (valor_diaria_base > 0)
);

CREATE TABLE Quarto (
    id_quarto SERIAL,
    id_categoria INT NOT NULL,
    numero_quarto VARCHAR(10) NOT NULL,
    andar INT,
    status_manutencao BOOLEAN DEFAULT FALSE,
    CONSTRAINT pk_quarto PRIMARY KEY (id_quarto),
    CONSTRAINT uk_quarto_numero UNIQUE (numero_quarto),
    CONSTRAINT fk_quarto_categoria FOREIGN KEY (id_categoria)
    REFERENCES Categoria_Quarto(id_categoria) ON DELETE RESTRICT
);

CREATE TABLE Reserva (
    id_reserva SERIAL,
    id_hospede INT NOT NULL,
    id_quarto INT NOT NULL,
    data_reserva TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    data_entrada_prevista DATE NOT NULL,
    data_saida_prevista DATE NOT NULL,
    data_checkin_real TIMESTAMP,
    data_checkout_real TIMESTAMP,
    status_reserva VARCHAR(20) DEFAULT 'PENDENTE',
    valor_total_bruto DECIMAL(10,2) NOT NULL,
    percentual_desconto DECIMAL(5,2) DEFAULT 0,
    valor_final_pago DECIMAL(10,2),
    CONSTRAINT pk_reserva PRIMARY KEY (id_reserva),
    CONSTRAINT fk_reserva_hospede FOREIGN KEY (id_hospede)
    REFERENCES Hospede(id_hospede) ON DELETE RESTRICT,
    CONSTRAINT fk_reserva_quarto FOREIGN KEY (id_quarto)
    REFERENCES Quarto(id_quarto) ON DELETE RESTRICT,
    CONSTRAINT ck_reserva_datas CHECK (data_saida_prevista > data_entrada_prevista),
    CONSTRAINT ck_reserva_status CHECK (status_reserva IN ('PENDENTE', 'CONFIRMADA', 'CHECK-IN', 'CHECK-OUT', 'CANCELADA', 'NO-SHOW'))
);

CREATE TABLE Cancelamento (
    id_cancelamento SERIAL,
    id_reserva INT NOT NULL,
    data_cancelamento TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    taxa_multa_aplicada DECIMAL(10,2) NOT NULL,
    motivo_cancelamento VARCHAR(255),
    CONSTRAINT pk_cancelamento PRIMARY KEY (id_cancelamento),
    CONSTRAINT uk_cancelamento_reserva UNIQUE (id_reserva),
    CONSTRAINT fk_cancelamento_reserva FOREIGN KEY (id_reserva)
    REFERENCES Reserva(id_reserva) ON DELETE CASCADE
);

-- RESOLUÇÃO N:M (Reserva x Serviços Consumidos)
CREATE TABLE Servico (
    id_servico SERIAL,
    nome_servico VARCHAR(100) NOT NULL,
    valor_unitario DECIMAL(10,2) NOT NULL,
    CONSTRAINT pk_servico PRIMARY KEY (id_servico),
    CONSTRAINT ck_servico_valor CHECK (valor_unitario >= 0)
);

CREATE TABLE Consumo_Servico (
    id_consumo SERIAL,
    id_reserva INT NOT NULL,
    id_servico INT NOT NULL,
    quantidade INT NOT NULL,
    data_consumo TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    valor_total_item DECIMAL(10,2) NOT NULL,
    CONSTRAINT pk_consumo_servico PRIMARY KEY (id_consumo),
    CONSTRAINT fk_consumo_reserva FOREIGN KEY (id_reserva)
    REFERENCES Reserva(id_reserva) ON DELETE CASCADE,
    CONSTRAINT fk_consumo_servico FOREIGN KEY (id_servico)
    REFERENCES Servico(id_servico) ON DELETE RESTRICT,
    CONSTRAINT ck_consumo_quantidade CHECK (quantidade > 0)
);
