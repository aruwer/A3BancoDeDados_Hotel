#!/bin/sh
set -e

echo "Iniciando carga estrita do banco de dados Hotel Host..."

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -f /scripts/postgresql/01_ddl.sql
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -f /scripts/postgresql/02_inserts.sql
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -f /scripts/procedures/postgresql_procedures.sql
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -f /scripts/postgresql/04_indices.sql

echo "Carga do banco concluída com sucesso!"