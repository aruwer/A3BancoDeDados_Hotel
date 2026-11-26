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
| P-03 | **Corrigido no PR #31** (`f91fe0c`): `.gitattributes` com LF para `*.sh`, `*.sql`, `*.py`; conferido com `autocrlf=true`. Falta ir para a `main`. Antes: o banco não sobe pelo Docker em checkout no Windows: o `postgres-init.sh` vira CRLF e o container sai com código 127 (`required file not found`). Não há `.gitattributes` | `d00bae7` "chore(docker): configura inicializacao automatica dos scripts sql e servicos app/testes" (PR #27) | (era Alta) | Testar `docker compose up -d --wait` num clone limpo no Windows depois do merge |
| P-04 | **Corrigido pela metade no PR #31:** a demo agora é repetível e não suja o banco (verificado em duas execuções), mas o caminho feliz falha com HOTEL-001 (check-in real em 2099). Antes: a demonstração do app não se repete: a segunda execução cai em HOTEL-007, porque a primeira faz o check-out real da reserva 10. Também deixa o banco incompatível com os testes | `461412d` "feat(app): desenvolve aplicacao python..." (PR #27) | Média | **Pendente (2ª rodada):** usar datas relativas a hoje (entrada hoje, saída amanhã, check-in real uma hora atrás), quarto sem reserva ativa no período e `Decimal("200.00")`; rodar `main.py` duas vezes. Detalhes na revisão do PR #31 |
| P-06 | O serviço `testes` do compose roda `pytest -q tests`, que antes não tinha testes pytest (código 5). Falta confirmar o serviço pelo compose com a suíte nova | `d00bae7` | Média | Rodar `docker compose run --rm testes` do zero e decidir se os dois `.sql` entram na verificação |
| P-05 | **Corrigido no PR #31.** Antes: BOM (U+FEFF) em `python/main.py`, `python/requirements.txt` e `.gitignore`. Não quebra nada (verificado) | `461412d` e `5a7acc7` | (era Baixa) | Nada |
| Caminho | **Corrigido no PR #31** (`AGENTS.md` agora cita `regras.md`). Antes: `AGENTS.md` cita `docs/regras.md`, mas o arquivo está em `regras.md` na raiz | `5a7acc7` (Rafaela criou) e `60b78d2` (Yuri atualizou) | (era Baixa) | Sobra o `regras.md` citar `docs/perguntas_de_negocio.md` (item de Pedro) |

**CTs:** CT-A13, CT-A15, CT-I10, CT-I16, CT-R13, CT-R14.

**Situação em 2026-11-26 (antes da 2ª rodada):** P-03, P-05 e o caminho do `AGENTS.md` estão corrigidos no PR #31. Falta o P-04 (caminho feliz) e, depois do merge, validar o P-06 (serviço `testes`, que a Amanda valida depois das correções). Falta também a Rafaela registrar o trabalho no `docs/ia-log.md`.

---

## Yuri Soares Dutra

| Id | Problema | Origem no histórico | Gravidade | O que fazer |
|---|---|---|---|---|
| P-07 | Cabeçalho do `02_inserts.sql` cita hóspedes que não existem (Diego, Bruno, Elisa, Fábio, Gabriela); os valores batem, os nomes não | `1406885` "feat(sql): adiciona 02_inserts.sql..." (os nomes dos hóspedes mudaram depois, em `bb9c5e8`, e o comentário não acompanhou) | Baixa | Trocar pelos nomes reais (João 2420, Carlos 2250, Ana 1550, Fernanda 1200, Mariana = Ricardo = 800, Luciana 400) |
| P-08 | Faltam dados de fronteira: Q02 em D+7 CONFIRMADA e D+8, taxa de 20% exata (Q06), serviço nunca consumido e empate (Q07), hóspede que usou todos menos um (Q09), mês sem receita | `02_inserts.sql` (vários commits) | Baixa | Acrescentar as linhas, mantendo datas relativas e as somas financeiras que o CT-U156 confere |
| DDL | `ck_reserva_desconto` aceita 0 a 100 (o `regras.md` diz 0, 5 ou 10); `ON DELETE CASCADE` em `cancelamento` e `consumo_servico` (o `regras.md` diz que todas as FKs bloqueiam); sem máximo de 30 noites (RN-01); `quarto` só tem `status_manutencao` booleano; `reserva` sem número de hóspedes (RN-03); `servico` sem `categoria` (Q09) | `fe72e9e` "Atualização sql" e anteriores (`b9a9e89`, `c68b2b5`) | Média | Decidir com Pedro: ou muda o DDL, ou o `regras.md` e o README registram a decisão (CT-M13) |

**CTs:** CT-U03, CT-U05, CT-U24, CT-U40 a CT-U43, CT-U80 a CT-U84, CT-U178.

---

## Pedro da Silva Kolling

Os testes **não encontraram defeito de comportamento** em `cancelar_reserva`, `fazer_checkout` e no trigger: os 5 testes de mutação foram detectados e as fronteiras do `regras.md` batem. O que sobra são lacunas de escopo entre o `regras.md` e o que foi implementado, já documentadas por ele no cabeçalho de `procedures/postgresql_procedures.sql`.

| Id | Problema | Origem no histórico | Gravidade | O que fazer |
|---|---|---|---|---|
| Lacuna | `cancelar_reserva` grava só a multa; o estorno do sinal (tabela 4.1) e o "valor devido" não são lançados. O estorno do `02_inserts.sql` foi inserido à mão | `2399f59` / `5df922f` | Média | Lançar o ESTORNO em `pagamento` na procedure, ou registrar o corte da regra |
| Lacuna | `fazer_checkout` não atualiza o quarto (LIMPEZA, decisão D-02) nem guarda taxa e valor final em colunas próprias (seção 13.2) | `2399f59` | Baixa | Depende da decisão sobre `status` do quarto (com Yuri) |
| Lacuna | Regras sem código: RN-03, RN-06, RN-07 (qualquer `UPDATE` de status passa), RN-10, RN-11, RN-12, auditoria, `registrar_reserva` e `fazer_checkin` | `regras.md` (`af3762c`, `45e87cd`, `b0ef3b0`) | Média | Decidir, regra por regra, entre implementar e cortar as "Extra" (seção 2 do `regras.md`) |
| Nomes | `regras.md` e `perguntas_de_negocio.md` usam `EM_ANDAMENTO`/`FINALIZADA`/`NO_SHOW`; o banco usa `CHECK-IN`/`CHECK-OUT`/`NO-SHOW` | `af3762c` e `44cd078` | Baixa | Alinhar os documentos ao DDL (ou o contrário) em um só commit |
| Caminho | `regras.md` cita `docs/perguntas_de_negocio.md`, que está na raiz | `af3762c` | Baixa | Corrigir o caminho |

**CTs:** CT-U61, CT-U62, CT-U90 a CT-U96, CT-U107, CT-U108, CT-U120 a CT-U143, CT-U160, CT-U161, CT-R12, CT-M25.

---

## Problemas de equipe (sem dono único)

| Item | Por quê | Quem decide |
|---|---|---|
| Decisão de escopo (CT-M13): quais regras "Extra" são implementadas e quais viram corte documentado | Mexe no DDL (Yuri), nas procedures (Pedro) e nas consultas (João) | Grupo |
| Registro de IA | Com P-01 e P-02 corrigidos por João, o relatório passa a ter dois erros reais encontrados e corrigidos (a tabela do README exige ao menos 2). Cada pessoa tem seu log (`docs/ia-log.md` de Pedro, `docs/Log-IA-Joao`); o `AGENTS.md` pede a consolidação em `docs/ia-log.md` e na seção 7 do README. Os problemas acima (por exemplo P-01, P-02 e P-03) são candidatos a "erro real encontrado e corrigido" na tabela, que exige ao menos 2 | Todos |
| Teste de ponta a ponta no Windows | P-03 só aparece em clone limpo no Windows; ninguém testou ainda | Rafaela, com apoio de quem usa Windows |
