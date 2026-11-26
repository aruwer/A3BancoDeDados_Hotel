"""Fixtures comuns dos testes. Cada teste roda numa transação desfeita no final (ROLLBACK).

Conexão: variável PG_DSN (o docker-compose já define). Sem ela, usa o banco de laboratório local.
Pré-requisito: banco carregado do zero com 01_ddl, 02_inserts, procedures e 04_indices.
"""
import os

import psycopg
import pytest

DSN = os.getenv(
    "PG_DSN",
    "host=localhost port=5432 dbname=hotel user=hotel password=hotel_lab_pwd",
)


@pytest.fixture
def conn():
    c = psycopg.connect(DSN)
    try:
        yield c
    finally:
        c.rollback()
        c.close()
