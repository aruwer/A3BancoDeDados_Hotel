#!/usr/bin/env python3
"""Gera postgresql/03_consultas_todas_pgadmin.sql a partir de postgresql/03_consultas.sql.

Por que existe: o pgAdmin so mostra a grade do ULTIMO comando de um script. Este gerador embrulha cada consulta Qnn
para que as 10 saiam numa grade unica (uma linha de texto JSON por linha de resultado, mais uma linha "linhas: N" por consulta).
A fonte da verdade continua sendo 03_consultas.sql (e o que os testes e a aplicacao leem). Nao edite o arquivo gerado.

Uso (na raiz do repositorio):  python scripts/gerar_consultas_pgadmin.py
"""
import re
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
ENTRADA = RAIZ / "postgresql" / "03_consultas.sql"
SAIDA = RAIZ / "postgresql" / "03_consultas_todas_pgadmin.sql"


def extrair_consultas(texto):
    texto = texto.replace("\r\n", "\n")
    marcas = list(re.finditer(r"(?m)^-- @(Q\d+)\b", texto))
    consultas = []
    for i, m in enumerate(marcas):
        fim = marcas[i + 1].start() if i + 1 < len(marcas) else len(texto)
        linhas = texto[m.start():fim].split("\n")
        # pula os comentarios e linhas em branco do cabecalho do bloco
        k = 0
        while k < len(linhas) and (linhas[k].strip() == "" or linhas[k].lstrip().startswith("--")):
            k += 1
        sql = "\n".join(linhas[k:])
        ultimo = sql.rfind(";")
        if ultimo < 0:
            raise SystemExit(f"{m.group(1)}: consulta sem ponto e virgula no final")
        sql = sql[:ultimo].strip()
        consultas.append((m.group(1), sql))
    if not consultas:
        raise SystemExit("nenhum bloco '-- @Qnn' encontrado")
    return consultas


def main():
    consultas = extrair_consultas(ENTRADA.read_text(encoding="utf-8"))
    partes = []
    for nome, sql in consultas:
        partes.append(f"SELECT '{nome}' AS consulta, 0::bigint AS ordem, 'linhas: ' || count(*) AS linha\n  FROM (\n{sql}\n  ) c")
        partes.append(f"SELECT '{nome}', row_number() OVER (), to_json(q)::text\n  FROM (\n{sql}\n  ) q")
    cab = (
        "-- GERADO por scripts/gerar_consultas_pgadmin.py a partir de postgresql/03_consultas.sql. NAO EDITE A MAO.\n"
        "-- Copie TUDO, cole no Query Tool do pgAdmin e execute uma vez (F5): as consultas saem numa grade so.\n"
        "-- Cada consulta tem uma linha 'linhas: N' (ordem 0) e depois uma linha por resultado (texto JSON, na ordem da consulta).\n"
        "-- Compare com os 'Resultado esperado' dos comentarios de 03_consultas.sql.\n"
        "-- Consulta que devolve 0 linhas aparece so com 'linhas: 0'.\n\n"
    )
    corpo = "SELECT consulta, ordem, linha\n  FROM (\n" + "\n  UNION ALL\n".join(partes) + "\n  ) todas\n ORDER BY consulta, ordem;\n"
    SAIDA.write_text(cab + corpo, encoding="utf-8", newline="\n")
    print(f"{SAIDA.relative_to(RAIZ)} gerado com {len(consultas)} consultas: {', '.join(n for n, _ in consultas)}")


if __name__ == "__main__":
    main()
