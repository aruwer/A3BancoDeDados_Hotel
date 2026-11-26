"""Funções auxiliares dos testes (dados de apoio e captura de erros do banco)."""
import itertools
from datetime import datetime, time, timedelta
from decimal import Decimal

import psycopg
import psycopg.rows
import pytest
from psycopg.errors import RaiseException

_seq = itertools.count(1)


def hoje(conn):
    return conn.execute("SELECT CURRENT_DATE").fetchone()[0]


def um(conn, sql, params=None):
    """Primeira linha do resultado (tupla)."""
    return conn.execute(sql, params).fetchone()


def todos(conn, sql, params=None):
    return conn.execute(sql, params).fetchall()


def codigo_negocio(conn, sql, params=None):
    """Executa esperando um erro de negócio (RAISE EXCEPTION) e devolve o código HOTEL-nnn.

    O comando roda num SAVEPOINT: o erro desfaz só a chamada e a transação do teste continua.
    """
    with pytest.raises(RaiseException) as exc:
        with conn.transaction():
            conn.execute(sql, params)
    msg = exc.value.diag.message_primary
    assert exc.value.sqlstate == "P0001", f"ERRCODE inesperado: {exc.value.sqlstate}"
    return msg.split(":")[0], msg


def erro_banco(conn, sql, params=None):
    """Executa esperando qualquer erro do banco e devolve (sqlstate, nome da constraint)."""
    with pytest.raises(psycopg.Error) as exc:
        with conn.transaction():
            conn.execute(sql, params)
    return exc.value.sqlstate, exc.value.diag.constraint_name


def novo_hospede(conn, estadias_anteriores=0):
    """Hóspede fictício novo, com N estadias CHECK-OUT antigas (quarto 7, sem sobrepor nada)."""
    n = next(_seq)
    hid = um(
        conn,
        "INSERT INTO hospede (cpf, nome_completo, email) VALUES (%s, %s, %s) RETURNING id_hospede",
        (f"9{n:010d}", f"Hospede Teste {n}", f"teste{n}@exemplo.local"),
    )[0]
    base = hoje(conn)
    for i in range(estadias_anteriores):
        entrada = base - timedelta(days=400 + 5 * i)
        nova_reserva(
            conn, hid, 7, entrada, entrada + timedelta(days=1), "CHECK-OUT", Decimal("100.00"),
            checkin_real=datetime.combine(entrada, time(14)),
            checkout_real=datetime.combine(entrada + timedelta(days=1), time(11)),
            valor_final=Decimal("100.00"),
        )
    return hid


def nova_reserva(conn, hospede, quarto, entrada, saida, status, bruto,
                 desconto=0, checkin_real=None, checkout_real=None, valor_final=None):
    return um(
        conn,
        """INSERT INTO reserva (id_hospede, id_quarto, data_entrada_prevista, data_saida_prevista,
                                data_checkin_real, data_checkout_real, status_reserva,
                                valor_total_bruto, percentual_desconto, valor_final_pago)
           VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s) RETURNING id_reserva""",
        (hospede, quarto, entrada, saida, checkin_real, checkout_real, status, bruto, desconto, valor_final),
    )[0]


def reserva_confirmada_futura(conn, bruto=Decimal("600.00"), noites=3, quarto=7, status="CONFIRMADA"):
    """Reserva a 100 dias, no quarto 7 (sem reservas nos dados de exemplo). Devolve (id, entrada)."""
    entrada = hoje(conn) + timedelta(days=100)
    hid = novo_hospede(conn)
    rid = nova_reserva(conn, hid, quarto, entrada, entrada + timedelta(days=noites), status, bruto)
    return rid, entrada


def reserva_para_checkout(conn, estadias_anteriores=0, bruto=Decimal("600.00"), noites=3, quarto=7):
    """Reserva CHECK-IN no quarto 7: entrou há `noites` dias, saída prevista = hoje (D = bruto/noites)."""
    h = hoje(conn)
    hid = novo_hospede(conn, estadias_anteriores)
    rid = nova_reserva(
        conn, hid, quarto, h - timedelta(days=noites), h, "CHECK-IN", bruto,
        checkin_real=datetime.combine(h - timedelta(days=noites), time(14)),
    )
    return rid


def saida(conn, dias=0, hora="11:00:00"):
    """Data e hora de saída = hoje + dias às `hora`."""
    h = hoje(conn) + timedelta(days=dias)
    return datetime.combine(h, time.fromisoformat(hora))


def fazer_checkout(conn, rid, valor, quando=None, forma=None):
    if forma is None:
        conn.execute("CALL fazer_checkout(%s, %s, %s)", (rid, valor, quando))
    else:
        conn.execute("CALL fazer_checkout(%s, %s, %s, %s)", (rid, valor, quando, forma))


def reserva(conn, rid):
    cur = conn.cursor(row_factory=psycopg.rows.dict_row)
    return cur.execute("SELECT * FROM reserva WHERE id_reserva = %s", (rid,)).fetchone()
