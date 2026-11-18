#!/bin/bash
# postgres-init.sh — Script de inicialização do PostgreSQL 17
# Roda na primeira subida do volume (docker-entrypoint-initdb.d).
# Ordem estrita: DDL → Inserts → Procedures → Índices.
# Qualquer erro aborta a inicialização (ON_ERROR_STOP=1).

set -e

psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f /scripts/postgresql/01_ddl.sql
psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f /scripts/postgresql/02_inserts.sql
psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f /scripts/procedures/postgresql_procedures.sql
psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f /scripts/postgresql/04_indices.sql

echo "Inicialização concluída com sucesso."