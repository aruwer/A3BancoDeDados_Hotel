"""CT-U01 a CT-U28 (parte implementada): constraints e DDL barram dado inválido."""
import re
from datetime import timedelta
from decimal import Decimal
from pathlib import Path

import pytest

from helpers import erro_banco, hoje, nova_reserva, novo_hospede, todos, um

RAIZ = Path(__file__).resolve().parents[2]
CHECK, UNICO, NOT_NULL, FK, TAMANHO = "23514", "23505", "23502", "23503", "22001"

INSERT_RESERVA = (
    "INSERT INTO reserva (id_hospede,id_quarto,data_entrada_prevista,data_saida_prevista,{extra}valor_total_bruto)"
    " VALUES (1,7,{datas},{extra_v}100)"
)


def _inserir_reserva(conn, entrada_off, saida_off, status="CONFIRMADA", bruto=Decimal("200.00"),
                     desconto=0, quarto=7):
    h = hoje(conn)
    return nova_reserva(conn, novo_hospede(conn), quarto, h + timedelta(days=entrada_off),
                        h + timedelta(days=saida_off), status, bruto, desconto)


# ------------------------------------------------------------------ reserva
def test_ct_u01_saida_igual_a_entrada_e_recusada(conn):
    """Given um hóspede e um quarto válidos
    When uma reserva é inserida com entrada igual à saída (0 noite)
    Then o banco recusa com violação de CHECK em ck_reserva_datas"""
    estado, constraint = erro_banco(
        conn,
        "INSERT INTO reserva (id_hospede,id_quarto,data_entrada_prevista,data_saida_prevista,valor_total_bruto)"
        " VALUES (1,7,CURRENT_DATE+50,CURRENT_DATE+50,100)")
    assert (estado, constraint) == (CHECK, "ck_reserva_datas")


def test_ct_u02_datas_invertidas_sao_recusadas(conn):
    """Given um hóspede e um quarto válidos
    When a saída é um dia antes da entrada
    Then o banco recusa com ck_reserva_datas"""
    estado, constraint = erro_banco(
        conn,
        "INSERT INTO reserva (id_hospede,id_quarto,data_entrada_prevista,data_saida_prevista,valor_total_bruto)"
        " VALUES (1,7,CURRENT_DATE+50,CURRENT_DATE+49,100)")
    assert (estado, constraint) == (CHECK, "ck_reserva_datas")


@pytest.mark.parametrize("status", ["PENDENTE", "CONFIRMADA", "CHECK-IN", "CHECK-OUT", "CANCELADA", "NO-SHOW"])
def test_ct_u04_status_validos_sao_aceitos(conn, status):
    """When uma reserva é inserida com um status do domínio
    Then ela é aceita"""
    assert _inserir_reserva(conn, 60, 62, status) > 0


@pytest.mark.parametrize("status", ["FINALIZADA", "EM_ANDAMENTO", "confirmada", ""])
def test_ct_u04_status_fora_do_dominio_e_recusado(conn, status):
    """When uma reserva é inserida com status fora do domínio
    Then o banco recusa com ck_reserva_status"""
    estado, constraint = erro_banco(
        conn,
        "INSERT INTO reserva (id_hospede,id_quarto,data_entrada_prevista,data_saida_prevista,"
        "status_reserva,valor_total_bruto) VALUES (1,7,CURRENT_DATE+60,CURRENT_DATE+62,%s,100)", (status,))
    assert (estado, constraint) == (CHECK, "ck_reserva_status")


def test_ct_u04_status_nulo_e_recusado(conn):
    """When o status é nulo explicitamente
    Then o banco recusa por NOT NULL"""
    estado, _ = erro_banco(
        conn,
        "INSERT INTO reserva (id_hospede,id_quarto,data_entrada_prevista,data_saida_prevista,"
        "status_reserva,valor_total_bruto) VALUES (1,7,CURRENT_DATE+60,CURRENT_DATE+62,NULL,100)")
    assert estado == NOT_NULL


@pytest.mark.parametrize("pct", [0, 5, 10])
def test_ct_u05_desconto_valido_e_aceito(conn, pct):
    """When o percentual de desconto é 0, 5 ou 10
    Then a reserva é aceita"""
    assert _inserir_reserva(conn, 60, 62, desconto=pct) > 0


@pytest.mark.parametrize("pct", [-1, 101])
def test_ct_u05_desconto_fora_de_0_a_100_e_recusado(conn, pct):
    """When o percentual de desconto está fora de 0 a 100
    Then o banco recusa com ck_reserva_desconto"""
    h = hoje(conn)
    estado, constraint = erro_banco(
        conn,
        "INSERT INTO reserva (id_hospede,id_quarto,data_entrada_prevista,data_saida_prevista,"
        "valor_total_bruto,percentual_desconto) VALUES (1,7,%s,%s,100,%s)",
        (h + timedelta(days=60), h + timedelta(days=62), pct))
    assert (estado, constraint) == (CHECK, "ck_reserva_desconto")


@pytest.mark.parametrize("pct", [1, 7, 50, 100])
def test_ct_u05_desconto_fora_de_0_5_10_e_recusado(conn, pct):
    """When o percentual de desconto está entre 0 e 100, mas não é 0, 5 ou 10 (regras.md)
    Then o banco recusa com ck_reserva_desconto"""
    h = hoje(conn)
    estado, constraint = erro_banco(
        conn,
        "INSERT INTO reserva (id_hospede,id_quarto,data_entrada_prevista,data_saida_prevista,"
        "valor_total_bruto,percentual_desconto) VALUES (1,7,%s,%s,100,%s)",
        (h + timedelta(days=60), h + timedelta(days=62), pct))
    assert (estado, constraint) == (CHECK, "ck_reserva_desconto")


def test_ct_u03_30_noites_e_aceito_e_31_e_recusado(conn):
    """Given o máximo de 30 noites por reserva (RN-01)
    When uma reserva de 30 noites e outra de 31 noites são inseridas
    Then a de 30 é aceita e a de 31 é recusada com ck_reserva_max_noites"""
    assert _inserir_reserva(conn, 60, 90) > 0
    h = hoje(conn)
    estado, constraint = erro_banco(
        conn,
        "INSERT INTO reserva (id_hospede,id_quarto,data_entrada_prevista,data_saida_prevista,"
        "valor_total_bruto) VALUES (1,8,%s,%s,100)",
        (h + timedelta(days=60), h + timedelta(days=91)))
    assert (estado, constraint) == (CHECK, "ck_reserva_max_noites")


@pytest.mark.parametrize("filho,colunas,valores,constraint", [
    ("cancelamento", "(id_reserva,taxa_multa_aplicada)", "(%s,0)", "fk_cancelamento_reserva"),
    ("consumo_servico", "(id_reserva,id_servico,quantidade,valor_total_item)", "(%s,1,1,35)", "fk_consumo_reserva"),
])
def test_ct_u24_apagar_reserva_com_filho_e_recusado(conn, filho, colunas, valores, constraint):
    """Given uma reserva com cancelamento ou com consumo de serviço
    When a reserva é apagada
    Then o banco recusa (ON DELETE RESTRICT), sem apagar o histórico em cascata"""
    rid = _inserir_reserva(conn, 60, 62)
    conn.execute(f"INSERT INTO {filho} {colunas} VALUES {valores}", (rid,))
    estado, nome = erro_banco(conn, "DELETE FROM reserva WHERE id_reserva = %s", (rid,))
    assert (estado, nome) == (FK, constraint)


def test_ct_u06_valor_bruto_negativo_e_recusado(conn):
    """When valor_total_bruto = -0,01
    Then recusa com ck_reserva_valor_bruto, mas 0,00 é aceito"""
    estado, constraint = erro_banco(
        conn,
        "INSERT INTO reserva (id_hospede,id_quarto,data_entrada_prevista,data_saida_prevista,valor_total_bruto)"
        " VALUES (1,7,CURRENT_DATE+60,CURRENT_DATE+62,-0.01)")
    assert (estado, constraint) == (CHECK, "ck_reserva_valor_bruto")
    assert _inserir_reserva(conn, 60, 62, bruto=Decimal("0.00")) > 0


def test_ct_u07_checkout_real_antes_do_checkin_real_e_recusado(conn):
    """When data_checkout_real é um minuto antes de data_checkin_real
    Then recusa com ck_reserva_checkout"""
    estado, constraint = erro_banco(
        conn,
        "INSERT INTO reserva (id_hospede,id_quarto,data_entrada_prevista,data_saida_prevista,"
        "data_checkin_real,data_checkout_real,status_reserva,valor_total_bruto)"
        " VALUES (1,7,CURRENT_DATE-20,CURRENT_DATE-18,'2020-01-01 14:00','2020-01-01 13:59','CHECK-OUT',100)")
    assert (estado, constraint) == (CHECK, "ck_reserva_checkout")


# ------------------------------------------------------------------ hóspede / quarto / categoria
def test_ct_u08_cpf_duplicado_e_recusado(conn):
    """Given o hóspede 1 com CPF 12345678909
    When outro hóspede usa o mesmo CPF
    Then recusa com uk_hospede_cpf"""
    estado, constraint = erro_banco(
        conn, "INSERT INTO hospede (cpf,nome_completo,email) VALUES ('12345678909','X','x@exemplo.local')")
    assert (estado, constraint) == (UNICO, "uk_hospede_cpf")


def test_ct_u09_email_duplicado_e_recusado(conn):
    """When outro hóspede usa o e-mail do hóspede 1
    Then recusa com uk_hospede_email"""
    estado, constraint = erro_banco(
        conn, "INSERT INTO hospede (cpf,nome_completo,email) VALUES ('00000000001','X','ana.lima@gmail.com')")
    assert (estado, constraint) == (UNICO, "uk_hospede_email")


@pytest.mark.parametrize("campo", ["cpf", "nome_completo", "email"])
def test_ct_u10_hospede_sem_campo_obrigatorio(conn, campo):
    """When um hóspede é inserido com o campo obrigatório nulo
    Then o banco recusa por NOT NULL"""
    valores = {"cpf": "'00000000002'", "nome_completo": "'X'", "email": "'y@exemplo.local'"}
    valores[campo] = "NULL"
    estado, _ = erro_banco(
        conn,
        f"INSERT INTO hospede (cpf,nome_completo,email) VALUES "
        f"({valores['cpf']},{valores['nome_completo']},{valores['email']})")
    assert estado == NOT_NULL


def test_ct_u11_cpf_com_mais_de_11_caracteres_e_recusado(conn):
    """When o CPF tem 12 caracteres
    Then o banco recusa por tamanho"""
    estado, _ = erro_banco(
        conn, "INSERT INTO hospede (cpf,nome_completo,email) VALUES ('123456789012','X','z@exemplo.local')")
    assert estado == TAMANHO


def test_ct_u12_numero_de_quarto_duplicado_e_recusado(conn):
    """When um quarto repete o número '101'
    Then recusa com uk_quarto_numero"""
    estado, constraint = erro_banco(
        conn, "INSERT INTO quarto (id_categoria,numero_quarto,andar) VALUES (1,'101',1)")
    assert (estado, constraint) == (UNICO, "uk_quarto_numero")


@pytest.mark.parametrize("cap,valor,constraint", [
    (0, "100.00", "ck_categoria_capacidade"),
    (2, "0.00", "ck_categoria_valor"),
    (2, "-5.00", "ck_categoria_valor"),
])
def test_ct_u13_categoria_invalida_e_recusada(conn, cap, valor, constraint):
    """When a categoria tem capacidade ou diária inválidas
    Then o banco recusa com o CHECK correspondente"""
    estado, nome = erro_banco(
        conn, "INSERT INTO categoria_quarto (nome_categoria,capacidade_maxima,valor_diaria_base) VALUES ('T',%s,%s)",
        (cap, valor))
    assert (estado, nome) == (CHECK, constraint)


def test_ct_u13_categoria_no_limite_e_aceita(conn):
    """When capacidade = 1 e diária = 0,01
    Then a categoria é aceita"""
    conn.execute("INSERT INTO categoria_quarto (nome_categoria,capacidade_maxima,valor_diaria_base) VALUES ('T',1,0.01)")


# ------------------------------------------------------------------ chaves estrangeiras
def test_ct_u14_apagar_categoria_com_quartos_e_recusado(conn):
    """Given a categoria 1 tem quartos
    When ela é apagada
    Then recusa com fk_quarto_categoria"""
    estado, constraint = erro_banco(conn, "DELETE FROM categoria_quarto WHERE id_categoria = 1")
    assert (estado, constraint) == (FK, "fk_quarto_categoria")


@pytest.mark.parametrize("sql,constraint", [
    ("DELETE FROM hospede WHERE id_hospede = 1", "fk_reserva_hospede"),
    ("DELETE FROM quarto WHERE id_quarto = 4", "fk_reserva_quarto"),
])
def test_ct_u15_apagar_pai_com_reservas_e_recusado(conn, sql, constraint):
    """When o hóspede ou o quarto que possui reservas é apagado
    Then o banco recusa (RESTRICT)"""
    estado, nome = erro_banco(conn, sql)
    assert (estado, nome) == (FK, constraint)


@pytest.mark.parametrize("hospede,quarto,constraint", [
    (999999, 7, "fk_reserva_hospede"),
    (1, 999999, "fk_reserva_quarto"),
])
def test_ct_u16_reserva_com_pai_inexistente_e_recusada(conn, hospede, quarto, constraint):
    """When a reserva referencia hóspede ou quarto inexistente
    Then o banco recusa"""
    estado, nome = erro_banco(
        conn,
        "INSERT INTO reserva (id_hospede,id_quarto,data_entrada_prevista,data_saida_prevista,valor_total_bruto)"
        " VALUES (%s,%s,CURRENT_DATE+60,CURRENT_DATE+62,100)", (hospede, quarto))
    assert (estado, nome) == (FK, constraint)


# ------------------------------------------------------------------ cancelamento, consumo, serviço
def test_ct_u17_uma_multa_por_reserva(conn):
    """Given a reserva 13 já tem cancelamento
    When outro é inserido para ela
    Then recusa com uk_cancelamento_reserva"""
    estado, constraint = erro_banco(
        conn, "INSERT INTO cancelamento (id_reserva,taxa_multa_aplicada) VALUES (13, 10)")
    assert (estado, constraint) == (UNICO, "uk_cancelamento_reserva")


def test_ct_u18_multa_negativa_e_recusada(conn):
    """When a multa é negativa
    Then recusa com ck_cancelamento_taxa, mas multa 0,00 é aceita"""
    rid = um(conn, "SELECT id_reserva FROM reserva WHERE status_reserva='CONFIRMADA' LIMIT 1")[0]
    estado, constraint = erro_banco(
        conn, "INSERT INTO cancelamento (id_reserva,taxa_multa_aplicada) VALUES (%s,-0.01)", (rid,))
    assert (estado, constraint) == (CHECK, "ck_cancelamento_taxa")
    conn.execute("INSERT INTO cancelamento (id_reserva,taxa_multa_aplicada) VALUES (%s,0.00)", (rid,))


@pytest.mark.parametrize("qtd", [0, -1])
def test_ct_u19_consumo_com_quantidade_invalida(conn, qtd):
    """When a quantidade do consumo é 0 ou negativa
    Then recusa com ck_consumo_quantidade"""
    estado, constraint = erro_banco(
        conn, "INSERT INTO consumo_servico (id_reserva,id_servico,quantidade,valor_total_item) VALUES (10,1,%s,35)", (qtd,))
    assert (estado, constraint) == (CHECK, "ck_consumo_quantidade")


def test_ct_u19_consumo_com_quantidade_1_e_aceito(conn):
    """When a quantidade é 1
    Then o consumo é aceito"""
    conn.execute("INSERT INTO consumo_servico (id_reserva,id_servico,quantidade,valor_total_item) VALUES (10,1,1,35)")


def test_ct_u20_servico_com_valor_negativo(conn):
    """When o valor do serviço é negativo
    Then recusa com ck_servico_valor, mas valor 0 é aceito"""
    estado, constraint = erro_banco(
        conn, "INSERT INTO servico (nome_servico,valor_unitario) VALUES ('Teste',-1)")
    assert (estado, constraint) == (CHECK, "ck_servico_valor")
    conn.execute("INSERT INTO servico (nome_servico,valor_unitario) VALUES ('Cortesia',0)")


# ------------------------------------------------------------------ pagamento
@pytest.mark.parametrize("tipo,forma,valor", [
    ("PAGAMENTO", "PIX", "10"),
    ("ESTORNO", "CARTAO_DEBITO", "0.01"),
])
def test_ct_u21_pagamento_valido_e_aceito(conn, tipo, forma, valor):
    """When o pagamento tem tipo, forma e valor válidos
    Then é aceito"""
    conn.execute("INSERT INTO pagamento (id_reserva,tipo,forma,valor) VALUES (10,%s,%s,%s)", (tipo, forma, valor))


@pytest.mark.parametrize("tipo,forma,valor,constraint", [
    ("PAGAMENTO", "PIX", "0", "ck_pagamento_valor"),
    ("DEPOSITO", "PIX", "10", "ck_pagamento_tipo"),
    ("PAGAMENTO", "CHEQUE", "10", "ck_pagamento_forma"),
])
def test_ct_u21_pagamento_invalido_e_recusado(conn, tipo, forma, valor, constraint):
    """When tipo, forma ou valor estão fora do domínio
    Then recusa com o CHECK correspondente"""
    estado, nome = erro_banco(
        conn, "INSERT INTO pagamento (id_reserva,tipo,forma,valor) VALUES (10,%s,%s,%s)", (tipo, forma, valor))
    assert (estado, nome) == (CHECK, constraint)


def test_ct_u22_pagamento_para_reserva_inexistente(conn):
    """When o pagamento referencia uma reserva inexistente
    Then recusa com fk_pagamento_reserva"""
    estado, constraint = erro_banco(
        conn, "INSERT INTO pagamento (id_reserva,tipo,forma,valor) VALUES (999999,'PAGAMENTO','PIX',10)")
    assert (estado, constraint) == (FK, "fk_pagamento_reserva")


def test_ct_u23_apagar_reserva_com_pagamento_e_recusado(conn):
    """Given a reserva 11 tem pagamento
    When a reserva é apagada
    Then o histórico financeiro é preservado (RESTRICT)"""
    estado, constraint = erro_banco(conn, "DELETE FROM reserva WHERE id_reserva = 11")
    assert (estado, constraint) == (FK, "fk_pagamento_reserva")


# ------------------------------------------------------------------ catálogo e scripts
def test_ct_u25_toda_constraint_tem_nome_e_prefixo(conn):
    """When consulto pg_constraint no schema public
    Then toda constraint tem nome iniciado por pk_, uk_, fk_ ou ck_ (nenhum nome gerado pelo PostgreSQL)"""
    nomes = [r[0] for r in todos(conn, """
        SELECT c.conname FROM pg_constraint c JOIN pg_namespace n ON n.oid = c.connamespace
        WHERE n.nspname = 'public' AND c.contype IN ('p','u','f','c')""")]
    assert nomes
    assert [n for n in nomes if not re.match(r"^(pk|uk|fk|ck)_", n)] == []


def test_ct_u25_toda_fk_declara_on_delete_explicito():
    """When leio o DDL
    Then toda FOREIGN KEY tem cláusula ON DELETE"""
    ddl = (RAIZ / "postgresql" / "01_ddl.sql").read_text(encoding="utf-8")
    ddl = "\n".join(l.split("--")[0] for l in ddl.splitlines())
    fks = re.findall(r"CONSTRAINT\s+fk_\w+\s+FOREIGN KEY\s*\([^)]*\)\s*REFERENCES\s+\w+\s*\([^)]*\)([^,;]*)", ddl, re.I)
    assert len(fks) >= 7
    assert [f for f in fks if "ON DELETE" not in f.upper()] == []


def test_ct_u26_scripts_sem_sintaxe_oracle():
    """When varro os scripts SQL
    Then não há VARCHAR2, NVL, SYSDATE, DUAL, NUMBER( nem RAISE_APPLICATION_ERROR"""
    proibidos = re.compile(r"\b(VARCHAR2|NVL|SYSDATE|RAISE_APPLICATION_ERROR|FROM\s+DUAL|NUMBER\s*\()", re.I)
    achados = []
    for arq in [*RAIZ.glob("postgresql/*.sql"), *RAIZ.glob("procedures/*.sql")]:
        for n, linha in enumerate(arq.read_text(encoding="utf-8").splitlines(), 1):
            if proibidos.search(linha.split("--")[0]):
                achados.append(f"{arq.name}:{n}")
    assert achados == []


def test_ct_u27_colunas_de_dinheiro_sao_numeric_10_2(conn):
    """When consulto information_schema
    Then as colunas monetárias são numeric(10,2)"""
    colunas = [("reserva", "valor_total_bruto"), ("reserva", "valor_final_pago"), ("reserva", "taxa_checkout"),
               ("categoria_quarto", "valor_diaria_base"), ("servico", "valor_unitario"),
               ("consumo_servico", "valor_total_item"), ("cancelamento", "taxa_multa_aplicada"), ("cancelamento", "valor_devido"),
               ("pagamento", "valor")]
    for tabela, coluna in colunas:
        tipo = um(conn, "SELECT data_type, numeric_precision, numeric_scale FROM information_schema.columns "
                        "WHERE table_name=%s AND column_name=%s", (tabela, coluna))
        assert tipo == ("numeric", 10, 2), f"{tabela}.{coluna} = {tipo}"


def test_ct_u28_inserts_usam_datas_relativas():
    """When varro 02_inserts.sql
    Then nenhuma data de calendário fixa (como '2025-01-01') é usada"""
    sql = (RAIZ / "postgresql" / "02_inserts.sql").read_text(encoding="utf-8")
    sql = "\n".join(l.split("--")[0] for l in sql.splitlines())
    assert re.findall(r"'\d{4}-\d{2}-\d{2}", sql) == []


# ------------------------------------------------------------------ D-02 e seção 13.2: status do quarto e taxa de check-out
@pytest.mark.parametrize("status", ["DISPONIVEL", "OCUPADO", "LIMPEZA", "MANUTENCAO"])
def test_ct_u38_status_de_quarto_validos_sao_aceitos(conn, status):
    """When um quarto é inserido com um status do ciclo (DISPONIVEL, OCUPADO, LIMPEZA, MANUTENCAO)
    Then ele é aceito"""
    conn.execute("INSERT INTO quarto (id_categoria,numero_quarto,andar,status_quarto) VALUES (1,%s,1,%s)",
                 ("T-" + status[:4], status))   # numero_quarto é VARCHAR(10)


@pytest.mark.parametrize("status", ["LIVRE", "disponivel", "", "EM_MANUTENCAO"])
def test_ct_u38_status_de_quarto_fora_do_dominio_e_recusado(conn, status):
    """When um quarto é inserido com status fora do domínio
    Then o banco recusa com ck_quarto_status"""
    estado, constraint = erro_banco(
        conn, "INSERT INTO quarto (id_categoria,numero_quarto,andar,status_quarto) VALUES (1,'T-X',1,%s)", (status,))
    assert (estado, constraint) == (CHECK, "ck_quarto_status")


def test_ct_u38_status_de_quarto_nulo_e_recusado(conn):
    """When o status do quarto é nulo explicitamente
    Then o banco recusa por NOT NULL"""
    estado, _ = erro_banco(
        conn, "INSERT INTO quarto (id_categoria,numero_quarto,andar,status_quarto) VALUES (1,'T-N',1,NULL)")
    assert estado == NOT_NULL


def test_ct_u38_quarto_novo_nasce_disponivel(conn):
    """When um quarto é inserido sem informar o status
    Then ele nasce DISPONIVEL"""
    qid = um(conn, "INSERT INTO quarto (id_categoria,numero_quarto,andar) VALUES (1,'T-D',1) RETURNING id_quarto")[0]
    assert um(conn, "SELECT status_quarto FROM quarto WHERE id_quarto=%s", (qid,))[0] == "DISPONIVEL"


def test_ct_u39_taxa_de_checkout_negativa_e_recusada(conn):
    """When uma reserva é inserida com taxa_checkout negativa
    Then o banco recusa com ck_reserva_taxa_checkout"""
    estado, constraint = erro_banco(
        conn,
        "INSERT INTO reserva (id_hospede,id_quarto,data_entrada_prevista,data_saida_prevista,taxa_checkout,"
        "valor_total_bruto) VALUES (1,7,CURRENT_DATE+70,CURRENT_DATE+72,-0.01,100)")
    assert (estado, constraint) == (CHECK, "ck_reserva_taxa_checkout")


def test_ct_u39_taxa_de_checkout_zero_e_default_e_aceita(conn):
    """When uma reserva é inserida sem taxa_checkout, ou com 0,00
    Then ela é aceita e a taxa fica 0"""
    rid = _inserir_reserva(conn, 70, 72)
    assert um(conn, "SELECT taxa_checkout FROM reserva WHERE id_reserva=%s", (rid,))[0] == Decimal("0")


# ------------------------------------------------------------------ CT-R12 e CT-M25: documentos alinhados ao DDL
_DOCS = ["regras.md", "perguntas_de_negocio.md", "README.md", "AGENTS.md"]


@pytest.mark.parametrize("doc", _DOCS)
def test_ct_r12_documentos_usam_os_status_do_ddl(doc):
    """Given os documentos de referência (regras, perguntas, README, AGENTS)
    Then nenhum usa os nomes antigos de status (EM_ANDAMENTO, FINALIZADA, NO_SHOW), só os do DDL"""
    texto = (RAIZ / doc).read_text(encoding="utf-8")
    assert re.findall(r"EM_ANDAMENTO|FINALIZADAS?\b|NO_SHOW", texto) == []


def test_ct_r12_regras_cita_todos_os_status_do_check_do_ddl():
    """Given o CHECK ck_reserva_status do DDL
    Then o regras.md cita cada um dos seis status"""
    ddl = (RAIZ / "postgresql" / "01_ddl.sql").read_text(encoding="utf-8")
    bloco = re.search(r"ck_reserva_status CHECK \((.*?)\)\s*\)", ddl, re.S).group(1)
    status = re.findall(r"'([A-Z-]+)'", bloco)
    assert len(status) == 6
    regras = (RAIZ / "regras.md").read_text(encoding="utf-8")
    assert [s for s in status if s not in regras] == []


@pytest.mark.parametrize("doc", _DOCS)
def test_ct_m25_caminhos_citados_existem(doc):
    """Given um documento que cita caminhos docs/... ou links .md
    Then cada arquivo citado existe"""
    texto = (RAIZ / doc).read_text(encoding="utf-8")
    citados = set(re.findall(r"\bdocs/[\w./-]+\.md\b", texto))
    citados |= set(re.findall(r"\]\(((?!https?:)[\w./-]+\.md)\)", texto))
    assert [c for c in citados if not (RAIZ / c).exists()] == []
