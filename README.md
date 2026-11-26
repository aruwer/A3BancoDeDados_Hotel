# Hotel Host — gestão de reservas, hospedagem e consumo de um hotel

> **Grupo:** Pedro da Silva Kolling, Yuri Soares Dutra, Rafaela Acosta Pereira, Amanda Maffini Ruwer, João Vitor Fraga da Rocha.
> **Período:** 2026/2 · **Tag:** v1.0.0
> **SGBD:** PostgreSQL 17 · **Aplicação:** Python (psycopg 3)

---

## 1. Domínio e regras de negócio

### 1.1 O problema

A recepção controla reservas, hóspedes e cobranças em planilha e papel. Isso gera quatro falhas: duas reservas para o mesmo quarto nas mesmas datas (overbooking), reservas com mais hóspedes do que o quarto comporta, cancelamentos cobrados de forma diferente conforme quem atende, e late check-out e desconto de fidelidade dados no improviso.

**Pergunta central:** como garantir que um quarto nunca tenha duas reservas sobrepostas, que a multa de cancelamento e a taxa de late check-out sigam a regra, e que isso valha também para quem insere direto no banco?

### 1.2 Regras de negócio

Detalhes, fronteiras e códigos de erro em [`regras.md`](regras.md). Prioridade: **N** = núcleo, **E** = extra (cortada por falta de tempo, decisão registrada na seção 2 do `regras.md`).

| ID | P | Regra (com valor-limite) | Onde é aplicada | Situação |
|---|---|---|---|---|
| RN-01 | N | Estadia de no mínimo 1 e no máximo 30 noites | `ck_reserva_datas` e `ck_reserva_max_noites` | Implementada |
| RN-02 | N | Um quarto não pode ter duas reservas ativas com períodos sobrepostos (sair e entrar no mesmo dia é permitido) | trigger `trg_reserva_sobreposicao` (trava a linha do quarto com `FOR UPDATE`) | Implementada |
| RN-03 | N | Número de hóspedes de 1 até a capacidade da categoria do quarto | `ck_reserva_hospedes` + trigger `trg_reserva_validacao` | Implementada |
| RN-04 | N | Cancelamento com 7 dias ou mais de antecedência: sem multa; de 2 a 6 dias: 50% da primeira diária; menos de 2 dias: 100%. Entrada já passada sem check-in vira NO-SHOW, com 100% da primeira diária | procedure `cancelar_reserva` (multa, estorno do sinal e valor devido) | Implementada |
| RN-05 | E | Desconto de fidelidade: 5% com 5 a 9 estadias concluídas; 10% com 10 ou mais | procedure `fazer_checkout` + `ck_reserva_desconto` (0, 5 ou 10) | Implementada |
| RN-06 | N | Quarto em MANUTENCAO não pode ser reservado | trigger `trg_reserva_validacao` | Implementada |
| RN-07 | N | A reserva só muda de status pela sequência PENDENTE → CONFIRMADA → CHECK-IN → CHECK-OUT, ou PENDENTE / CONFIRMADA → CANCELADA / NO-SHOW | trigger `trg_reserva_validacao` | Implementada |
| RN-08 | N | Check-out até 12:00 sem taxa; até 18:00, 50% da diária; depois, 1 diária inteira | procedure `fazer_checkout` | Implementada |
| RN-09 | N | O check-out só finaliza se o pagamento cobrir o saldo (diárias com desconto + consumos + taxa − sinal) | procedure `fazer_checkout` | Implementada |
| RN-10 | E | Sinal de no mínimo 30% das diárias na reserva | — | Cortada |
| RN-11 | E | Consumo só em reserva CHECK-IN | — | Cortada |
| RN-12 | E | Check-in a partir da data de entrada e antes da data de saída | — | Cortada |

**Cortes conscientes (regras Extra):** RN-10, RN-11, RN-12, a auditoria de status e as procedures `registrar_reserva` e `fazer_checkin`. O sinal e o check-in são registrados por INSERT/UPDATE direto, e o trigger garante as regras que dependem deles.

### 1.3 Verificação do tema contra a rubrica

| Critério | Como o projeto atende |
|---|---|
| Problema real e identificável | Recepção de hotel com overbooking, cancelamento sem critério e cobrança de late check-out no improviso (seção 1.1) |
| 3+ regras com número | RN-01 (30 noites), RN-04 (7 e 2 dias), RN-05 (5 e 10 estadias), RN-08 (12:00 e 18:00) |
| 6+ entidades e N:M | 8 tabelas; `CONSUMO_SERVICO` resolve o N:M entre reserva e serviço |
| Procedure e trigger que importam | `cancelar_reserva` altera reserva, cancelamento e pagamento; `fazer_checkout` altera reserva, quarto e pagamento; os triggers `trg_reserva_sobreposicao` e `trg_reserva_validacao` valem também para INSERT e UPDATE direto |
| Originalidade | Não é biblioteca, escola de informática nem estoque de cozinha |

---

## 2. DER

Fonte versionada: [`der/hotel.puml`](der/hotel.puml) (PlantUML, notação Crow's Foot). Para gerar a imagem sem instalar nada além do Docker:

```bash
docker run --rm -v "$PWD/der:/data" plantuml/plantuml -tpng /data/hotel.puml
```

**Entidades (8):** `HOSPEDE`, `CATEGORIA_QUARTO`, `QUARTO`, `RESERVA` (carrega o estado), `CANCELAMENTO`, `PAGAMENTO`, `SERVICO` e `CONSUMO_SERVICO` (associativa, com `quantidade` e `valor_total_item`). Atributos, tipos e constraints de cada uma estão no `.puml` e em [`postgresql/01_ddl.sql`](postgresql/01_ddl.sql).

### 2.1 Cardinalidades (mín., máx.)

| Relacionamento | Cardinalidade | Observação |
|---|---|---|
| Hóspede — realiza — Reserva | (1,1) — (0,N) | Toda reserva tem hóspede; hóspede cadastrado pode não ter reserva |
| Categoria — agrupa — Quarto | (1,1) — (1,N) | Todo quarto tem categoria; o DER pede ao menos um quarto por categoria |
| Quarto — recebe — Reserva | (1,1) — (0,N) | Uma reserva = um quarto |
| Reserva — pode ter — Cancelamento | (1,1) — (0,1) | `UNIQUE` em `id_reserva`: no máximo um cancelamento por reserva |
| Reserva — engloba — Consumo_Servico | (1,1) — (0,N) | N:M entre reserva e serviço, resolvido pela associativa |
| Serviço — é consumido em — Consumo_Servico | (1,1) — (0,N) | Serviço do catálogo pode nunca ter sido consumido |
| Reserva — gera — Pagamento | (1,1) — (0,N) | Sinal, quitação e estorno (o tipo indica o sentido) |

---

## 3. Decisões de design

| Decisão | Justificativa |
|---|---|
| `RESERVA` separada de `QUARTO` | Datas e estado pertencem à reserva, não ao quarto: sem isso não há como checar sobreposição |
| Uma reserva = um quarto | Mantém o modelo pequeno; várias acomodações exigiriam outra entidade associativa (evolução futura) |
| `CONSUMO_SERVICO` como entidade associativa | N:M entre reserva e serviço, com atributos próprios (quantidade, valor do item) |
| `CATEGORIA_QUARTO` e `SERVICO` como entidades, não como atributos | Capacidade e diária base valem para todos os quartos da categoria; o catálogo de serviços muda sem tocar nas reservas |
| `CANCELAMENTO` como entidade própria | Só existe para reservas canceladas (0..1) e carrega multa, valor devido e motivo, que seriam colunas quase sempre nulas em `RESERVA` |
| PK artificial `SERIAL`; `UNIQUE` em CPF, e-mail e número do quarto | A PK não muda com o mundo real; os `UNIQUE` garantem a unicidade do que o usuário digita |
| Valores gravados na reserva (`valor_total_bruto`, `valor_final_pago`, `taxa_checkout`) | Desnormalização consciente: o valor cobrado não muda se a tarifa ou o catálogo mudarem depois, e as consultas de receita não recalculam diárias, desconto e consumos. Fora isso, o modelo está em 3FN: cada atributo depende só da chave da própria tabela |
| Overbooking barrado por trigger com `FOR UPDATE` no quarto | Vale para quem insere direto na tabela; a segunda sessão espera a primeira terminar e recebe `HOTEL-005` |
| Capacidade, manutenção e transições de status no trigger `trg_reserva_validacao` | São regras que não podem depender de a aplicação lembrar |
| `QUARTO.status_quarto` (DISPONIVEL, OCUPADO, LIMPEZA, MANUTENCAO) no lugar do booleano `status_manutencao` | Decisão D-02: `fazer_checkout` leva o quarto a LIMPEZA e a governança o devolve a DISPONIVEL por UPDATE. Só MANUTENCAO bloqueia reservas |
| Status PENDENTE e NO-SHOW | PENDENTE é o estado inicial antes da confirmação; NO-SHOW separa quem não apareceu do cancelamento antecipado |
| Desconto de fidelidade só 0, 5 ou 10 (`ck_reserva_desconto`) | É o que o `regras.md` permite; qualquer outro percentual é recusado pelo banco |
| Todas as FKs com `ON DELETE RESTRICT` | Histórico de reservas, cancelamentos, consumos e pagamentos não pode sumir junto com a reserva |
| Procedures sem COMMIT | Quem chama decide a transação; os testes e a demonstração usam ROLLBACK |
| Códigos de erro `HOTEL-00x` (ERRCODE `P0001`) | A aplicação trata o erro de negócio pelo código estável, não pelo texto |
| Datas relativas a hoje nos dados de exemplo | As consultas dão o mesmo resultado em qualquer dia |
| Índices em arquivo separado (`04_indices.sql`) | Permite medir antes e depois |

---

## 4. Como rodar

**Pré-requisito:** apenas Docker.

```bash
docker compose up -d --wait            # PostgreSQL pronto, com esquema, dados, procedures e índices
docker compose run --rm testes         # verificação automatizada (pytest)
docker compose run --rm app            # aplicação Python: consulta, procedure no caminho feliz e erro de negócio
docker compose down -v                 # limpar tudo (a próxima subida recarrega os scripts)
```

Porta 5432 ocupada? Use `PG_PORT=5433 docker compose up -d --wait`. Mudou um `.sql`? Rode `docker compose down -v` antes de subir de novo.

| Serviço | Porta | Usuário | Senha (**somente laboratório**) |
|---|---|---|---|
| PostgreSQL 17 (`hotel`) | 5432 | `hotel` | `hotel_lab_pwd` (definida no `docker-compose.yml`) |

### 4.1 Estrutura do repositório

```
.
├── README.md · AGENTS.md · opencode.json · docker-compose.yml · pytest.ini
├── regras.md · perguntas_de_negocio.md
├── der/                 # hotel.puml
├── postgresql/          # 01_ddl · 02_inserts · 03_consultas · 03_consultas_todas_pgadmin · 04_indices
├── procedures/          # postgresql_procedures.sql (2 procedures e 2 triggers)
├── performance/         # carga_massa.sql · medir_antes_depois.sql
├── python/              # main.py (aplicação) · gerar_consultas_pgadmin.py · requirements.txt
├── tests/               # unit/ (pytest) · test_*.sql · casos-de-teste/ (roteiro BDD e relatórios)
├── docs/                # ia-log.md e logs de IA por integrante
└── docker/              # Dockerfile.python · postgres-init.sh
```

### 4.2 O que foi testado

278 testes em pytest + psycopg, rodando contra o banco do compose (cada teste é revertido com ROLLBACK). Os testes seguem os requisitos de `regras.md`, não o código. O roteiro BDD completo (Given/When/Then) está em [`tests/casos-de-teste/roteiro-ct.md`](tests/casos-de-teste/roteiro-ct.md).

| Arquivo de teste (`tests/unit/`) | Nº de testes | O que verifica |
|---|---|---|
| `test_ct_u_constraints.py` | 82 | Constraints barram dado inválido (datas, status, desconto 0/5/10, 30 noites, CPF/e-mail únicos, FKs `RESTRICT`); toda constraint tem nome (`pk_`, `uk_`, `fk_`, `ck_`) |
| `test_ct_u_cancelar_reserva.py` | 38 | Caminho feliz e erros de `cancelar_reserva`: multa nas fronteiras de 7, 6, 2, 1 e 0 dias, NO-SHOW, estorno e valor devido |
| `test_ct_u_fazer_checkout.py` | 65 | Caminho feliz e erros de `fazer_checkout`: 12:00:00 e 12:00:01, 18:00:00 e 18:00:01, fidelidade com 4, 5, 9 e 10 estadias, quarto em LIMPEZA |
| `test_ct_u_trigger_sobreposicao.py` | 21 | Overbooking barrado em INSERT e UPDATE direto, incluindo as fronteiras de data |
| `test_ct_u_trigger_validacao.py` | 38 | Capacidade, quarto em manutenção e máquina de estados barrados em INSERT e UPDATE direto |
| `test_ct_u_consultas.py` | 13 | As 10 consultas com resultado esperado calculado à mão; as técnicas exigidas (JOIN, window, agregação, `NOT EXISTS`) |
| `test_ct_u_contrato_procedures.py` | 18 | Contrato das procedures e do trigger (códigos de erro estáveis, sem COMMIT) e consistência financeira dos dados de exemplo |
| `test_ct_u_indices.py` | 3 | Os 3 índices existem e cobrem as colunas previstas |
| **Total** | **278** | |

Há também `tests/test_procedures.sql` e `tests/test_trigger_sobreposicao.sql`, para rodar no `psql`.

### 4.3 As 10 consultas

Perguntas de negócio, decisões e dados de fronteira em [`perguntas_de_negocio.md`](perguntas_de_negocio.md); SQL em [`postgresql/03_consultas.sql`](postgresql/03_consultas.sql), com o resultado esperado de cada uma em comentário. Para rodar tudo de uma vez no pgAdmin, use `postgresql/03_consultas_todas_pgadmin.sql` (gerado por `python/gerar_consultas_pgadmin.py`).

| # | Pergunta | Técnica |
|---|---|---|
| Q01 | Receita de diárias por categoria de quarto | JOIN + GROUP BY/HAVING |
| Q02 | Chegadas dos próximos 7 dias | JOIN |
| Q03 | Ranking dos hóspedes que mais gastaram | window RANK |
| Q04 | Quartos disponíveis num período | NOT EXISTS |
| Q05 | Receita acumulada mês a mês | SUM OVER |
| Q06 | Categorias com cancelamento acima de 20% | GROUP BY/HAVING + FILTER |
| Q07 | Participação de cada serviço na receita de consumo | window sobre agregação |
| Q08 | Última estadia concluída de cada hóspede | ROW_NUMBER |
| Q09 | Hóspedes que usaram todos os serviços cadastrados | divisão relacional (NOT EXISTS duplo) |
| Q10 | Reservas e receita por categoria e situação, com subtotais | ROLLUP |

Limitação conhecida: a Q09 considera **todos** os serviços; o planejamento pedia só a categoria "Extras", que o DDL não tem.

---

## 5. Performance

Três índices em [`postgresql/04_indices.sql`](postgresql/04_indices.sql):

| Índice | Para quê |
|---|---|
| `idx_reserva_hospede` (`Reserva.id_hospede`) | FK usada em JOIN: reservas de um hóspede (Q03, Q08) |
| `idx_consumo_reserva` (`Consumo_Servico.id_reserva`) | FK da associativa: consumos de uma reserva (Q03, Q07, Q09, check-out) |
| `idx_reserva_status_entrada` (`Reserva.status_reserva`, `data_entrada_prevista`) | Busca: chegadas por situação e data de entrada (Q02) |

**Como medir** (massa de 200 mil reservas em um esquema à parte, `perf_test`, sem tocar no esquema do projeto):

```bash
docker compose exec -T postgres psql -U hotel -d hotel -f /dev/stdin < performance/carga_massa.sql
docker compose exec -T postgres psql -U hotel -d hotel -f /dev/stdin < performance/medir_antes_depois.sql
```

O segundo script mede 3 consultas antes e depois dos índices (5 execuções cada, com `EXPLAIN (ANALYZE, BUFFERS)`) e devolve a mediana do tempo e o plano real. A saída vai para [`performance/explain_antes_depois.txt`](performance/explain_antes_depois.txt).

**Resultados medidos:** ainda não registrados neste README. Os tempos e os planos só entram aqui depois de rodar os scripts acima e colar a saída no `explain_antes_depois.txt`; nenhum número é estimado.

---

## 6. Dificuldades e aprendizados

Só o que de fato aconteceu; cada linha tem registro correspondente na seção 7.

| Dificuldade | Causa | Solução | Aprendizado |
|---|---|---|---|
| O banco não subia pelo Docker no Windows (`required file not found`, código 127) | O Git converteu `postgres-init.sh` para CRLF no checkout | `.gitattributes` com LF para `.sh`, `.sql` e `.py`. Quem já tinha clonado precisou regravar os arquivos | Fim de linha é parte do código quando há contêiner; testar o compose numa cópia limpa |
| A Q08 não executava (`missing FROM-clause entry for table "r"`) | O `SELECT` externo usava o alias de uma subconsulta | Alias corrigido | Rodar cada consulta isolada mostra qual quebrou; rodar o arquivo inteiro esconde |
| O `03_consultas.sql` virou saída gerada e perdeu os comentários com resultado esperado | O gerador do pgAdmin sobrescreveu o arquivo original | Blocos `-- @Qnn` restaurados; a versão do pgAdmin ficou em arquivo à parte, gerado | Arquivo gerado nunca deve substituir a fonte |
| A demonstração do `main.py` não se repetia (`HOTEL-007` na segunda execução) | O check-out real da reserva 10 mudava o banco | Demonstração em transação isolada com ROLLBACK e datas relativas a hoje | Demonstração e testes precisam deixar o banco como encontraram |
| Os valores esperados das consultas ficaram desatualizados quando os dados de exemplo mudaram | Os testes tinham os números dos dados antigos | Valores recalculados à mão a partir das reservas e dos consumos, não copiados da saída | Copiar a saída como "esperado" esconderia defeitos |
| Conflitos ao juntar os PRs (DDL, consultas, `.gitattributes`) | Duas pessoas alteraram as mesmas linhas por motivos diferentes | Mantidas as constraints dos dois e uma só versão das consultas; a coluna `status_manutencao` virou `status_quarto` em todo o código | Combinar a troca de uma coluna com quem usa a coluna antes do merge |
| O `psql` ficou em transação abortada depois de um erro no meio de um script | `ON_ERROR_STOP` parou o script sem `ROLLBACK` | `ROLLBACK;` antes de continuar | Um erro no PostgreSQL aborta a transação inteira (por isso `SAVEPOINT` na aplicação) |

---

## 7. Uso de IA

**Ferramentas e modelos:** Claude Sonnet 5.5 (pelo chat do claude.ai e pelo Claude Code, na frente de testes); Gemini 3.1 Pro (DER e DDL iniciais); OpenCode com Nemotron 3 (Docker e pgAdmin; a versão exata está no log de João). **Skills do repositório:** nenhuma.
**Configuração versionada:** `opencode.json` (push negado, comandos com `ask`) e `AGENTS.md`. Nenhuma ferramenta executou `git push`. Nenhum dado pessoal real foi enviado: os dados de exemplo são fictícios.
**Logs completos:** [`docs/ia-log.md`](docs/ia-log.md) (18 registros), [`docs/log-AI-Amanda.md`](docs/log-AI-Amanda.md), [`docs/Log-IA-Joao`](docs/Log-IA-Joao) e [`docs/log_AI_DER_DLL.md`](docs/log_AI_DER_DLL.md).

### 7.1 Registros

| # | Artefato | Pedido (resumo) | O que o agente errou ou omitiu | O que o grupo fez |
|---|---|---|---|---|
| 1 | `der/hotel.puml` e `postgresql/01_ddl.sql` | (Gemini) Criar o DER e o DDL do hotel | **Erro real:** constraints sem nome, `ON DELETE CASCADE` em tabelas de histórico, `ON DELETE` ausente nas demais FKs e um booleano de manutenção fora do padrão das regras; o DDL nunca tinha sido executado | Revisão contra `regras.md` e a rubrica; constraints nomeadas, `RESTRICT` em todas as FKs, `status_quarto` no lugar do booleano |
| 2 | `postgresql/03_consultas.sql` (Q06 a Q10) | (Claude) Rascunho de 5 consultas com resultado esperado | **Erro real:** os "resultado esperado (calculado à mão)" não batiam com o `02_inserts.sql` (Q06 dava Standard com 5 reservas, o real eram 8; Q07 somava 2155, o real era 1335) | O grupo recalculou à mão a partir dos dados e corrigiu os comentários; os testes passaram a conferir cada consulta |
| 3 | `procedures/postgresql_procedures.sql` (`fazer_checkout`) | (Claude) Check-out com late check-out, fidelidade e pagamento, alterando 2 ou mais tabelas | **Erro real de omissão:** a 1ª versão gravava só em `Reserva`, reprovando o item "pelo menos 2 tabelas" | O grupo conferiu a entrega contra o checklist; `Pagamento` passou a receber a quitação; banco recriado do zero e testes passando |
| 4 | `tests/test_procedures.sql` | (Claude) Testes com valores de fronteira | **Erro real:** comparava a mensagem em inglês (`new row...`), mas o servidor responde em português; o teste falhou com a constraint funcionando | Passou a comparar o SQLSTATE (`23514`, `23503`), que não depende do idioma |
| 5 | `docker/postgres-init.sh` e `docker-compose.yml` | (OpenCode) Subir o banco pelo Docker | **Erro real:** contêiner saiu com código 127 (`required file not found`): script com CRLF; o diagnóstico exato foi feito com ajuda do Claude | `.gitattributes` com LF para `.sh`, `.sql` e `.py`; compose testado do zero |
| 6 | `python/main.py` | (IA) Isolar a demonstração para ela se repetir | **Erro real:** reserva de demonstração com data fixa em 2099 e check-out com `CURRENT_TIMESTAMP` deram `HOTEL-001` (saída anterior ao check-in) | Datas relativas a hoje, quarto livre escolhido por consulta, `Decimal("200.00")` e ROLLBACK; demonstração rodada duas vezes |
| 7 | `performance/medir_antes_depois.sql` | (Claude) Script de medição do `EXPLAIN` antes e depois | **Erro real:** usava nomes de colunas de outro esquema e comandos do `psql` que o pgAdmin não entende | Reescrito em SQL puro com os nomes reais das colunas |
| 8 | `tests/unit/test_ct_u_consultas.py` | (Claude) Testes das 10 consultas com valor esperado à mão | **Erro real:** rodar o arquivo inteiro como uma instrução escondeu que só a Q08 estava quebrada | Cada consulta passou a rodar isolada; a Q08 foi corrigida e todos os testes passam |
| 9 | `regras.md`, `README.md`, `AGENTS.md` | (Claude) Alinhar nomes de status e caminhos ao DDL | **Omissão:** o relatório listava só `EM_ANDAMENTO`/`FINALIZADA`/`NO_SHOW`; o banco também usa `PENDENTE`, que a documentação não citava | `PENDENTE` incluído no `regras.md`; caminhos corrigidos; testes impedem a volta |

### 7.2 Reflexão do grupo

- **Onde a IA mais ajudou:** montar as fronteiras dos testes (7, 6, 2, 1 e 0 dias; 12:00:00 e 12:00:01; 4, 5, 9 e 10 estadias), manter os códigos `HOTEL-00x` consistentes, calcular à mão os resultados esperados das consultas e achar defeitos que só aparecem ao executar (Q08 inválida, demonstração que não se repete, CRLF).
- **Onde mais errou:** em afirmações que não verificou antes de escrever (resultado esperado das consultas, "o BOM quebra o `pip install`", nome de coluna de outro esquema) e em detalhes de ambiente (fim de linha, mensagem em português, comandos do `psql` no pgAdmin). Nenhum desses erros apareceu lendo o código: todos apareceram ao executar.
- **O que faríamos diferente:** pedir à IA que verifique cada afirmação de risco com um comando antes de escrevê-la, rodar os testes logo após cada mudança de DDL ou de assinatura, e nunca usar a saída da consulta como valor esperado.
- **Regra que ficou no `AGENTS.md`:** a IA propõe e o grupo valida; `git push` é negado; todo DDL, DML, consulta e procedure passa por validação humana contra o `regras.md`; interações relevantes e erros vão para `docs/ia-log.md`.

---

### Checklist antes da tag v1.0.0

- [ ] `docker compose up -d --wait` sobe do zero, sem erro
- [ ] `docker compose run --rm testes` verde (278 testes)
- [ ] `performance/explain_antes_depois.txt` gerado e a tabela da seção 5 preenchida com a saída real
- [ ] Imagem do DER gerada (seção 2) e adicionada ao README
- [ ] Nenhuma senha real, chave de API ou `.env` no Git (`git log -p`)
- [ ] Todos os integrantes com commits e capazes de explicar o próprio trecho
