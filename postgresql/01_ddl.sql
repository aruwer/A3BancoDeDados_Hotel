-- 01_ddl_postgres.sql
-- Banco de Dados: PostgreSQL
-- Atende aos Critérios: 7 Entidades, Estados Claros na Reserva e Tabela Associativa N:M.

CREATE TABLE Hospede (
    id_hospede SERIAL PRIMARY KEY,
    cpf VARCHAR(11) UNIQUE NOT NULL,
    nome_completo VARCHAR(100) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    telefone VARCHAR(20),
    data_cadastro DATE DEFAULT CURRENT_DATE
);

CREATE TABLE Categoria_Quarto (
    id_categoria SERIAL PRIMARY KEY,
    nome_categoria VARCHAR(50) NOT NULL,
    capacidade_maxima INT NOT NULL CHECK (capacidade_maxima > 0),
    valor_diaria_base DECIMAL(10,2) NOT NULL CHECK (valor_diaria_base > 0)
);

CREATE TABLE Quarto (
    id_quarto SERIAL PRIMARY KEY,
    id_categoria INT NOT NULL,
    numero_quarto VARCHAR(10) UNIQUE NOT NULL,
    andar INT,
    status_manutencao BOOLEAN DEFAULT FALSE,
    CONSTRAINT fk_quarto_categoria FOREIGN KEY (id_categoria) REFERENCES Categoria_Quarto(id_categoria)
);

CREATE TABLE Reserva (
    id_reserva SERIAL PRIMARY KEY,
    id_hospede INT NOT NULL,
    id_quarto INT NOT NULL,
    data_reserva TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    data_entrada_prevista DATE NOT NULL,
    data_saida_prevista DATE NOT NULL,
    data_checkin_real TIMESTAMP,
    data_checkout_real TIMESTAMP,
    status_reserva VARCHAR(20) DEFAULT 'PENDENTE' CHECK (status_reserva IN ('PENDENTE', 'CONFIRMADA', 'CHECK-IN', 'CHECK-OUT', 'CANCELADA', 'NO-SHOW')),
    valor_total_bruto DECIMAL(10,2) NOT NULL,
    percentual_desconto DECIMAL(5,2) DEFAULT 0,
    valor_final_pago DECIMAL(10,2),
    CONSTRAINT fk_reserva_hospede FOREIGN KEY (id_hospede) REFERENCES Hospede(id_hospede),
    CONSTRAINT fk_reserva_quarto FOREIGN KEY (id_quarto) REFERENCES Quarto(id_quarto),
    CONSTRAINT chk_datas_reserva CHECK (data_saida_prevista > data_entrada_prevista)
);

CREATE TABLE Cancelamento (
    id_cancelamento SERIAL PRIMARY KEY,
    id_reserva INT UNIQUE NOT NULL,
    data_cancelamento TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    taxa_multa_aplicada DECIMAL(10,2) NOT NULL,
    motivo_cancelamento VARCHAR(255),
    CONSTRAINT fk_cancelamento_reserva FOREIGN KEY (id_reserva) REFERENCES Reserva(id_reserva) ON DELETE CASCADE
);

-- RESOLUÇÃO N:M (Reserva x Serviços Consumidos)
CREATE TABLE Servico (
    id_servico SERIAL PRIMARY KEY,
    nome_servico VARCHAR(100) NOT NULL,
    valor_unitario DECIMAL(10,2) NOT NULL CHECK (valor_unitario >= 0)
);

CREATE TABLE Consumo_Servico (
    id_consumo SERIAL PRIMARY KEY,
    id_reserva INT NOT NULL,
    id_servico INT NOT NULL,
    quantidade INT NOT NULL CHECK (quantidade > 0),
    data_consumo TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    valor_total_item DECIMAL(10,2) NOT NULL,
    CONSTRAINT fk_consumo_reserva FOREIGN KEY (id_reserva) REFERENCES Reserva(id_reserva) ON DELETE CASCADE,
    CONSTRAINT fk_consumo_servico FOREIGN KEY (id_servico) REFERENCES Servico(id_servico)
);
