"""CT-U (concorrência) · duas sessões ao mesmo tempo: overbooking, cancelamento e check-out.

Cada teste abre DUAS conexões reais. A sessão A faz a operação e segura a transação aberta; a sessão B tenta a
mesma operação numa thread. O esperado: B **espera** (fica bloqueada pela trava `FOR UPDATE`) e, quando A confirma,
B acorda, enxerga o resultado de A e recebe o erro de negócio, sem gravar nada duplicado.

Diferente dos outros testes, aqui os dados precisam ser confirmados (COMMIT) para a outra sessão enxergá-los;
por isso a fixture `dados` apaga tudo o que criou ao final (e devolve o status do quarto usado).
Usa o quarto 302, que não tem reservas nos dados de exemplo, em datas distantes.
"""
import threading
from datetime import datetime, time, timedelta
from decimal import Decimal

import psycopg
import pytest

from conftest import DSN
from helpers import hoje, nova_reserva, novo_hospede, um

QUARTO = "302"
ESPERA_BLOQUEIO = 1.5      # segundos que B precisa continuar bloqueada para provar a espera
ESPERA_MAXIMA = 15         # segundos até desistir (evita travar a suíte)


class Dados:
    """Cria dados confirmados numa conexão própria e remove tudo no final."""

    def __init__(self):
        self.conn = psycopg.connect(DSN)
        self.hospedes = []
        self.id_quarto, self.status_original = um(
            self.conn, "SELECT id_quarto, status_quarto FROM quarto WHERE numero_quarto = %s", (QUARTO,))
        self.hoje = hoje(self.conn)

    def hospede(self):
        hid = novo_hospede(self.conn)
        self.hospedes.append(hid)
        return hid

    def reserva_confirmada(self, dias_ate_entrada=700, noites=3):
        entrada = self.hoje + timedelta(days=dias_ate_entrada)
        rid = nova_reserva(self.conn, self.hospede(), self.id_quarto, entrada,
                           entrada + timedelta(days=noites), "CONFIRMADA", Decimal("600.00"))
        self.conn.commit()
        return rid

    def reserva_em_checkin(self, noites=3):
        h = self.hoje
        rid = nova_reserva(
            self.conn, self.hospede(), self.id_quarto, h - timedelta(days=noites), h, "CHECK-IN", Decimal("600.00"),
            checkin_real=datetime.combine(h - timedelta(days=noites), time(14)))
        self.conn.commit()
        return rid

    def limpar(self):
        self.conn.rollback()
        if self.hospedes:
            ids = tuple(self.hospedes)
            for tabela in ("pagamento", "cancelamento", "consumo_servico"):
                self.conn.execute(
                    f"DELETE FROM {tabela} WHERE id_reserva IN (SELECT id_reserva FROM reserva WHERE id_hospede = ANY(%s))",
                    (list(ids),))
            self.conn.execute("DELETE FROM reserva WHERE id_hospede = ANY(%s)", (list(ids),))
            self.conn.execute("DELETE FROM hospede WHERE id_hospede = ANY(%s)", (list(ids),))
        self.conn.execute("UPDATE quarto SET status_quarto = %s WHERE id_quarto = %s",
                          (self.status_original, self.id_quarto))
        self.conn.commit()
        self.conn.close()


@pytest.fixture
def dados():
    d = Dados()
    try:
        yield d
    finally:
        d.limpar()


def _sessao():
    """Conexão nova, com limite de espera pela trava para o teste nunca ficar pendurado."""
    return psycopg.connect(DSN, options=f"-c lock_timeout={ESPERA_MAXIMA * 1000}")


class SessaoB:
    """Executa um comando numa thread e guarda o resultado (ok ou o erro do banco)."""

    def __init__(self, sql, params):
        self.conn = _sessao()
        self.erro = None
        self.thread = threading.Thread(target=self._rodar, args=(sql, params), daemon=True)

    def _rodar(self, sql, params):
        try:
            self.conn.execute(sql, params)
            self.conn.commit()
        except psycopg.Error as e:
            self.erro = e
            self.conn.rollback()

    def iniciar(self):
        self.thread.start()

    def esta_esperando(self):
        self.thread.join(ESPERA_BLOQUEIO)
        return self.thread.is_alive()

    def terminar(self):
        self.thread.join(ESPERA_MAXIMA)
        assert not self.thread.is_alive(), "a sessão B não acordou depois do COMMIT da sessão A"
        self.conn.close()
        return self.erro

    def codigo(self):
        assert self.erro is not None, "a sessão B deveria ter recebido um erro de negócio"
        assert self.erro.sqlstate == "P0001", f"ERRCODE inesperado: {self.erro.sqlstate}"
        return self.erro.diag.message_primary.split(":")[0]


def _contar(conn, sql, params=None):
    return conn.execute(sql, params).fetchone()[0]


def test_ct_u_conc01_overbooking_mesma_data_so_uma_sessao_reserva(dados):
    """Given duas sessões que reservam o mesmo quarto nas mesmas datas ao mesmo tempo
    When a sessão A insere a reserva (ainda sem COMMIT) e a sessão B tenta inserir outra igual
    Then B fica esperando; depois do COMMIT de A, B recebe HOTEL-005 e o quarto fica com uma só reserva"""
    entrada = dados.hoje + timedelta(days=700)
    saida = entrada + timedelta(days=3)
    hid_a, hid_b = dados.hospede(), dados.hospede()
    dados.conn.commit()
    insert = ("INSERT INTO reserva (id_hospede,id_quarto,data_entrada_prevista,data_saida_prevista,"
              "status_reserva,valor_total_bruto) VALUES (%s,%s,%s,%s,'CONFIRMADA',600)")
    a = _sessao()
    try:
        a.execute(insert, (hid_a, dados.id_quarto, entrada, saida))        # A segura a trava do quarto
        b = SessaoB(insert, (hid_b, dados.id_quarto, entrada, saida))
        b.iniciar()
        assert b.esta_esperando(), "B deveria esperar pela trava do quarto, mas terminou antes do COMMIT de A"
        a.commit()
        b.terminar()
        assert b.codigo() == "HOTEL-005"
    finally:
        a.close()
    total = _contar(dados.conn, "SELECT count(*) FROM reserva WHERE id_quarto=%s AND data_entrada_prevista=%s",
                    (dados.id_quarto, entrada))
    assert total == 1


def test_ct_u_conc02_overbooking_datas_que_se_sobrepoem_parcialmente(dados):
    """Given a sessão A reservando D+700 a D+703 e a sessão B reservando D+702 a D+705 no mesmo quarto
    When as duas rodam ao mesmo tempo
    Then B espera por A e é recusada com HOTEL-005 (a sobreposição vale mesmo sem datas iguais)"""
    entrada = dados.hoje + timedelta(days=700)
    hid_a, hid_b = dados.hospede(), dados.hospede()
    dados.conn.commit()
    insert = ("INSERT INTO reserva (id_hospede,id_quarto,data_entrada_prevista,data_saida_prevista,"
              "status_reserva,valor_total_bruto) VALUES (%s,%s,%s,%s,'CONFIRMADA',600)")
    a = _sessao()
    try:
        a.execute(insert, (hid_a, dados.id_quarto, entrada, entrada + timedelta(days=3)))
        b = SessaoB(insert, (hid_b, dados.id_quarto, entrada + timedelta(days=2), entrada + timedelta(days=5)))
        b.iniciar()
        assert b.esta_esperando()
        a.commit()
        b.terminar()
        assert b.codigo() == "HOTEL-005"
    finally:
        a.close()


def test_ct_u_conc03_reservas_em_quartos_diferentes_nao_se_bloqueiam(dados):
    """Given a sessão A com uma reserva aberta no quarto 302 e a sessão B reservando outro quarto
    When as duas rodam ao mesmo tempo
    Then B não espera (a trava é por quarto) e as duas reservas são gravadas"""
    entrada = dados.hoje + timedelta(days=700)
    saida = entrada + timedelta(days=3)
    hid_a, hid_b = dados.hospede(), dados.hospede()
    outro_quarto = um(dados.conn, "SELECT id_quarto FROM quarto WHERE numero_quarto = '301'")[0]
    dados.conn.commit()
    insert = ("INSERT INTO reserva (id_hospede,id_quarto,data_entrada_prevista,data_saida_prevista,"
              "status_reserva,valor_total_bruto) VALUES (%s,%s,%s,%s,'CONFIRMADA',600)")
    a = _sessao()
    try:
        a.execute(insert, (hid_a, dados.id_quarto, entrada, saida))
        b = SessaoB(insert, (hid_b, outro_quarto, entrada, saida))
        b.iniciar()
        assert not b.esta_esperando(), "B esperou sem precisar: a trava deveria ser só do quarto 302"
        assert b.terminar() is None
        a.commit()
    finally:
        a.close()
    assert _contar(dados.conn, "SELECT count(*) FROM reserva WHERE id_hospede = ANY(%s)", ([hid_a, hid_b],)) == 2


def test_ct_u_conc04_dois_cancelamentos_da_mesma_reserva(dados):
    """Given uma reserva CONFIRMADA e duas sessões que a cancelam ao mesmo tempo
    When a sessão A chama cancelar_reserva (sem COMMIT) e a sessão B chama a mesma procedure
    Then B espera; depois do COMMIT de A, recebe HOTEL-007 e existe um único cancelamento"""
    rid = dados.reserva_confirmada()
    a = _sessao()
    try:
        a.execute("CALL cancelar_reserva(%s)", (rid,))
        b = SessaoB("CALL cancelar_reserva(%s)", (rid,))
        b.iniciar()
        assert b.esta_esperando(), "B deveria esperar pela trava da reserva"
        a.commit()
        b.terminar()
        assert b.codigo() == "HOTEL-007"
    finally:
        a.close()
    assert _contar(dados.conn, "SELECT count(*) FROM cancelamento WHERE id_reserva = %s", (rid,)) == 1
    assert _contar(dados.conn, "SELECT count(*) FROM reserva WHERE id_reserva=%s AND status_reserva='CANCELADA'",
                   (rid,)) == 1


def test_ct_u_conc05_dois_checkouts_da_mesma_reserva(dados):
    """Given uma reserva CHECK-IN e duas sessões que fazem o check-out ao mesmo tempo
    When a sessão A chama fazer_checkout (sem COMMIT) e a sessão B chama a mesma procedure
    Then B espera; depois do COMMIT de A, recebe HOTEL-007 e a quitação é lançada uma só vez"""
    rid = dados.reserva_em_checkin()
    quando = datetime.combine(dados.hoje, time(11))
    a = _sessao()
    try:
        a.execute("CALL fazer_checkout(%s, %s, %s)", (rid, Decimal("600.00"), quando))
        b = SessaoB("CALL fazer_checkout(%s, %s, %s)", (rid, Decimal("600.00"), quando))
        b.iniciar()
        assert b.esta_esperando(), "B deveria esperar pela trava da reserva"
        a.commit()
        b.terminar()
        assert b.codigo() == "HOTEL-007"
    finally:
        a.close()
    assert _contar(dados.conn, "SELECT count(*) FROM pagamento WHERE id_reserva=%s AND tipo='PAGAMENTO'", (rid,)) == 1
    assert _contar(dados.conn, "SELECT count(*) FROM reserva WHERE id_reserva=%s AND status_reserva='CHECK-OUT'",
                   (rid,)) == 1


def test_ct_u_conc06_a_sessao_a_desfaz_e_b_consegue_reservar(dados):
    """Given a sessão A com a reserva aberta e a sessão B esperando pelo mesmo quarto e datas
    When A faz ROLLBACK em vez de COMMIT
    Then B acorda, não encontra conflito e a reserva dela é gravada"""
    entrada = dados.hoje + timedelta(days=700)
    saida = entrada + timedelta(days=3)
    hid_a, hid_b = dados.hospede(), dados.hospede()
    dados.conn.commit()
    insert = ("INSERT INTO reserva (id_hospede,id_quarto,data_entrada_prevista,data_saida_prevista,"
              "status_reserva,valor_total_bruto) VALUES (%s,%s,%s,%s,'CONFIRMADA',600)")
    a = _sessao()
    try:
        a.execute(insert, (hid_a, dados.id_quarto, entrada, saida))
        b = SessaoB(insert, (hid_b, dados.id_quarto, entrada, saida))
        b.iniciar()
        assert b.esta_esperando()
        a.rollback()
        assert b.terminar() is None
    finally:
        a.close()
    assert _contar(dados.conn, "SELECT count(*) FROM reserva WHERE id_hospede = ANY(%s)", ([hid_a, hid_b],)) == 1
    assert _contar(dados.conn, "SELECT count(*) FROM reserva WHERE id_hospede = %s", (hid_b,)) == 1
