# Problemas dos testes, separados por responsável

Escrito para: o grupo, para cada pessoa saber o que corrigir. Os detalhes técnicos, as evidências e as correções sugeridas de cada item (P-01 a P-08) estão em [relatorio-problemas.md](relatorio-problemas.md). As divergências com o `regras.md` estão na seção 3 daquele relatório.

## Como a atribuição foi feita

A pessoa listada é o **autor do commit que introduziu** o trecho com problema (`git log -S` e `git blame` na `main`). Isso mostra quem mexeu no arquivo, **não quem errou**: o projeto usa IA em todas as etapas, a revisão é do grupo (`AGENTS.md`) e há commits "Parte pessoa 2" que juntam trabalho de várias frentes. Use a lista para dividir a correção, não para cobrar culpa.

| Pessoa (autor nos commits) | Frente no repositório |
|---|---|
| **João Vitor Fraga da Rocha** (`jvfraga01`) | Consultas, índices e performance (`03_consultas.sql`, `04_indices.sql`, `performance/`) |
| **Rafaela Costa** | Docker, aplicação Python, `.gitignore`, `AGENTS.md` |
| **Yuri Soares Dutra** (`YuriSoaresD`) | DDL e dados de exemplo (`01_ddl.sql`, `02_inserts.sql`) |
| **Pedro da Silva Kolling** | Regras, procedures, trigger e testes SQL (`regras.md`, `procedures/`, `tests/*.sql`) |
| **Amanda Ruwer** (`aruwer`) | Repositório inicial e README; nenhum problema atribuído |

---

## João Vitor Fraga da Rocha

| Id | Problema | Origem no histórico | Gravidade | O que fazer |
|---|---|---|---|---|
| P-01 | ~~Q08 não executa~~ **RESOLVIDO** em `a89d648`: o `SELECT` externo usa `t.`. Reteste em 2026-11-25: CT-U177 passa | `cfb46e3` "Parte pessoa 2" | (era Alta) | Nada |
| P-02 | ~~`03_consultas.sql` virou saída gerada~~ **RESOLVIDO** em `a89d648`, `cfa7a5e` e `f97e2a7`: blocos `-- @Qnn` restaurados, versão pgAdmin em `03_consultas_todas_pgadmin.sql`, gerador em `python/gerar_consultas_pgadmin.py`. Reteste: CT-U180 e CT-U181 passam | `4a45258` | (era Alta) | Sobras menores: trocar "Q01 a Q05" por "Q01 a Q10" no cabeçalho; a docstring do gerador cita `scripts/`, mas ele está em `python/`; rodar o gerador e conferir que reproduz o arquivo versionado |
| P-08 (Q02, Q06, Q07, Q09) | As consultas passam, mas os dados não cobrem as fronteiras de D+7, de 20% exato, de serviço nunca usado e de "todos menos um" | Consultas em `cfb46e3`; os dados são de Yuri | Baixa | Em conjunto com Yuri: pedir as linhas faltantes para `02_inserts.sql` |
| Q09 | Considera todos os serviços; o planejamento pede só a categoria "Extras" | `cfb46e3` | Baixa | Depende de Yuri criar `servico.categoria`; depois filtrar a Q09 |

**CTs:** CT-U177, CT-U181 e CT-U178. Os dois primeiros eram `xfail` (BUG-01 e BUG-02) e agora passam.

**Situação em 2026-11-25:** suíte com 180 passando e nenhuma falha, depois dos 4 commits de João. Em aberto para ele só P-08 (com Yuri), a Q09 e as sobras menores do P-02.

---

## Rafaela Costa

| Id | Problema | Origem no histórico | Gravidade | O que fazer |
|---|---|---|---|---|
| P-03 | **Resolvido** (PR #31, `f91fe0c`, mergeado na branch de testes): `.gitattributes` com LF para `*.sh`, `*.sql`, `*.py`; conferido com `autocrlf=true`. Falta ir para a `main`. Antes: o banco não sobe pelo Docker em checkout no Windows: o `postgres-init.sh` vira CRLF e o container sai com código 127 (`required file not found`). Não há `.gitattributes` | `d00bae7` "chore(docker): configura inicializacao automatica dos scripts sql e servicos app/testes" (PR #27) | (era Alta) | Testar `docker compose up -d --wait` num clone limpo no Windows depois do merge |
| P-04 | **Resolvido** (PR #31, `ab8a272`): demo repetível, não suja o banco e o caminho feliz dá CHECK-OUT (verificado em duas execuções em 2026-11-26). Antes: a demonstração do app não se repete: a segunda execução cai em HOTEL-007, porque a primeira faz o check-out real da reserva 10. Também deixa o banco incompatível com os testes | `461412d` "feat(app): desenvolve aplicacao python..." (PR #27) | (era Média) | Nada |
| P-06 | **Resolvido** (verificado em 2026-11-26): `docker compose up -d --wait` e `docker compose run --rm testes` do zero deram 180 passando; sem alteração no serviço. Quem clonou antes do `.gitattributes` precisa regravar os arquivos (CRLF no disco). Antes: o serviço `testes` do compose roda `pytest -q tests`, que antes não tinha testes pytest (código 5). Falta confirmar o serviço pelo compose com a suíte nova | `d00bae7` | Média | (era Média) | Só decidir se os dois `.sql` de `tests/` entram na verificação (CT-I17) |
| P-05 | **Resolvido** (PR #31). Antes: BOM (U+FEFF) em `python/main.py`, `python/requirements.txt` e `.gitignore`. Não quebra nada (verificado) | `461412d` e `5a7acc7` | (era Baixa) | Nada |
| Caminho | **Resolvido** (PR #31; `AGENTS.md` agora cita `regras.md`). Antes: `AGENTS.md` cita `docs/regras.md`, mas o arquivo está em `regras.md` na raiz | `5a7acc7` (Rafaela criou) e `60b78d2` (Yuri atualizou) | (era Baixa) | Sobra o `regras.md` citar `docs/perguntas_de_negocio.md` (item de Pedro) |

**CTs:** CT-A13, CT-A15, CT-I10, CT-I16, CT-R13, CT-R14.

**Situação em 2026-11-26 (depois da 2ª rodada, PR #31 mergeado na branch de testes):** P-03, P-04, P-05 e o caminho do `AGENTS.md` estão resolvidos, e ela registrou o trabalho no `docs/ia-log.md` (a assinatura do log diz "Rafaela Acosta", o autor dos commits é Rafaela Costa). O P-06 (serviço `testes` do compose) também está resolvido: verificado pelo compose, 180 passando. Fica a divergência do README (cita Oracle, Java e serviços `app-python`/`app-java` que não existem no compose), que contradiz o `AGENTS.md`.

---

## Yuri Soares Dutra

| Id | Problema | Situação |
|---|---|---|
| P-07 | Cabeçalho do `02_inserts.sql` com nomes que não existem | **Resolvido** (PR #33) |
| P-08 | Faltam dados de fronteira (Q02, Q06, Q07, Q09, mês sem receita) | **Resolvido** (PR #33): F1 a F8; testes recalculados |
| DDL | `ck_reserva_desconto` 0 a 100; `CASCADE`; sem máximo de 30 noites | **Resolvido** (PR #33): desconto 0/5/10, RESTRICT e `ck_reserva_max_noites` |
| DDL | `quarto` só com booleano; `reserva` sem número de hóspedes; `servico` sem `categoria` | `status_quarto` e `numero_hospedes` resolvidos pelo PR #32 (Pedro); `servico.categoria` segue sem existir (Q09 considera todos os serviços) |

**CTs:** CT-U03, CT-U05, CT-U24, CT-U40 a CT-U43, CT-U80 a CT-U84, CT-U178: todos passam.

**Situação em 2026-11-26:** a integração com o PR #32 teve conflito só em duas linhas do `01_ddl.sql`, resolvido mantendo as constraints dos dois. Falta decidir se `testes/conftest.py` fica (o compose roda `tests`).

---

## Pedro da Silva Kolling

Os testes não encontraram defeito de comportamento nas procedures; o que havia eram lacunas de escopo, e o PR #32 as resolveu.

| Id | Problema | Situação |
|---|---|---|
| Lacuna | Estorno do sinal e valor devido não lançados | **Resolvido** (PR #32): CT-U61 e CT-U62 |
| Lacuna | `fazer_checkout` sem LIMPEZA e sem colunas de taxa e valor final | **Resolvido** (PR #32) |
| Lacuna | RN-03, RN-06, RN-07 sem código; RN-10, RN-11, RN-12 e auditoria | RN-03, RN-06 e RN-07 **resolvidas** (trigger `trg_reserva_validacao`); as Extra foram **cortadas e documentadas** |
| Nomes | Status `EM_ANDAMENTO`/`FINALIZADA`/`NO_SHOW` nos documentos | **Resolvido** (PR #32) |
| Caminho | `docs/perguntas_de_negocio.md` | **Resolvido** (PR #32) |
| Integração | O PR #32 trocou `status_manutencao` por `status_quarto` e quebrava `main.py`, a Q04 e o arquivo do pgAdmin; conflito em `03_consultas.sql` | **Resolvido** na integração (ver relatório, seção 7) |
| Registro | Falta no `docs/ia-log.md` a decisão de trocar o booleano por `status_quarto` | Aberto |

**CTs:** CT-U61, CT-U62, CT-U90 a CT-U96, CT-U107, CT-U108, CT-U120 a CT-U143, CT-U160, CT-U161, CT-R12, CT-M25: todos passam.

---

## Problemas de equipe (sem dono único)

| Item | Por quê | Quem decide |
|---|---|---|
| Decisão de escopo (CT-M13): quais regras "Extra" são implementadas e quais viram corte documentado | Mexe no DDL (Yuri), nas procedures (Pedro) e nas consultas (João) | Grupo |
| Registro de IA | Com P-01 e P-02 corrigidos por João, o relatório passa a ter dois erros reais encontrados e corrigidos (a tabela do README exige ao menos 2). Cada pessoa tem seu log (`docs/ia-log.md` de Pedro, `docs/Log-IA-Joao`); o `AGENTS.md` pede a consolidação em `docs/ia-log.md` e na seção 7 do README. Os problemas acima (por exemplo P-01, P-02 e P-03) são candidatos a "erro real encontrado e corrigido" na tabela, que exige ao menos 2 | Todos |
| Teste de ponta a ponta no Windows | P-03 só aparece em clone limpo no Windows; ninguém testou ainda | Rafaela, com apoio de quem usa Windows |
