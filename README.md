# Hotel Host — gestão de reservas, hospedagem e consumo de um hotel

> **Grupo:** Pedro da Silva Kolling, Yuri Soares Dutra, Rafaela Acosta Pereira, Amanda Maffini Ruwer, João Vitor Fraga da Rocha.
> **Período:** 2026/2 · **Tag:** v1.0.0
> **SGBDs:** PostgreSQL 17 e Oracle XE 21 · **Aplicações:** Python e Java
>
> _Esqueleto da A3. Troque tudo que está entre `< >` e apague os comentários `TODO` antes da entrega._
> _Seções 1 a 3 já trazem a versão unificada das regras (ver `docs/regras.md`); revisem e ajustem ao que o professor aprovou._

---

## 1. Domínio e regras de negócio

### 1.1 O problema

A recepção controla reservas, hóspedes e cobranças em planilha e papel. Isso gera quatro falhas: duas reservas para o mesmo quarto nas mesmas datas (overbooking), reservas com mais hóspedes do que o quarto comporta, cancelamentos cobrados de forma diferente conforme quem atende, e late check-out e desconto de fidelidade dados no improviso.

**Pergunta central:** como garantir que um quarto nunca tenha duas reservas sobrepostas, que a multa de cancelamento e a taxa de late check-out sigam a regra, e que isso valha também para quem insere direto no banco, com o mesmo resultado no PostgreSQL e no Oracle?

### 1.2 Regras de negócio

Detalhes, fronteiras e códigos de erro em [`docs/regras.md`](docs/regras.md). Prioridade: **N** = núcleo, **E** = extra (cortar primeiro se o tempo apertar).

| ID | P | Regra (com valor-limite) | Onde é aplicada |
|---|---|---|---|
| RN-01 | N | Estadia de no mínimo 1 e no máximo 30 noites; check-out depois do check-in | CHECK + procedure `registrar_reserva` |
| RN-02 | N | Um quarto não pode ter duas reservas ativas com períodos sobrepostos (sair e entrar no mesmo dia é permitido) | procedure `registrar_reserva` (trava o quarto) + trigger `trg_reserva_sobreposicao` (destaque) |
| RN-03 | N | Número de hóspedes de 1 até a capacidade do tipo de quarto | trigger `trg_reserva_validacao` + procedure `registrar_reserva` |
| RN-04 | N | Cancelamento com 7 dias ou mais de antecedência: sem multa; de 2 a 6 dias: 50% da primeira diária; menos de 2 dias: 100%. Entrada já passada sem check-in vira NO_SHOW, com 100% da primeira diária | procedure `cancelar_reserva` |
| RN-05 | E | Desconto de fidelidade sobre as diárias: 5% com 5 a 9 estadias concluídas; 10% com 10 ou mais | procedure `fazer_checkout` |
| RN-06 | N | Quarto em MANUTENCAO não pode ser reservado; check-in só em quarto DISPONIVEL (MANUTENCAO, LIMPEZA e OCUPADO bloqueiam) | procedures `registrar_reserva` e `fazer_checkin` + CHECK no status |
| RN-07 | N | A reserva só muda de status pela sequência CONFIRMADA → EM_ANDAMENTO → FINALIZADA, ou CONFIRMADA → CANCELADA / NO_SHOW | trigger `trg_reserva_validacao` |
| RN-08 | N | Check-out até 12:00 sem taxa; até 18:00, 50% da diária; depois, 1 diária inteira | procedure `fazer_checkout` |
| RN-09 | N | O check-out só finaliza se o pagamento cobrir o saldo (diárias com desconto + consumos + taxa − sinal) | procedure `fazer_checkout` |
| RN-10 | E | Sinal de no mínimo 30% das diárias na reserva | procedure `registrar_reserva` |
| RN-11 | E | Consumo só em reserva EM_ANDAMENTO; quantidade maior que zero | trigger `trg_consumo_validacao` + CHECK |
| RN-12 | E | Check-in a partir da data de entrada e antes da data de saída | procedure `fazer_checkin` |

<!-- TODO: ajustar números e regras ao que o professor aprovar no checkpoint 1. Mínimo: 3 regras com número. -->

### 1.3 Verificação do tema contra a rubrica

| Critério | Como o projeto atende |
|---|---|
| Problema real e identificável | Recepção de hotel com overbooking, cancelamento sem critério e cobrança de late check-out no improviso (seção 1.1) |
| 3+ regras com número | RN-01 (30 noites), RN-04 (7 e 2 dias), RN-05 (5 e 10 estadias), RN-08 (12:00 e 18:00), RN-10 (30%) |
| 6+ entidades e N:M | 8 tabelas; `CONSUMO_RESERVA` resolve o N:M entre reserva e serviço |
| Procedure e trigger que importam | `registrar_reserva` altera reserva e pagamento; `fazer_checkout` altera reserva, quarto e pagamento; os triggers (`trg_reserva_validacao`, `trg_reserva_auditoria`) valem para INSERT e UPDATE direto |
| Originalidade | Não é biblioteca, escola de informática nem estoque de cozinha |

---

## 2. DER

![DER](der/hotelhost.png)

Fonte versionada: [`der/hotelhost.puml`](der/hotelhost.puml) (PlantUML, notação Crow's Foot).

**Entidades:** `HOSPEDE`, `TIPO_QUARTO`, `QUARTO`, `RESERVA` (com estado), `SERVICO`, `CONSUMO_RESERVA` (associativa, com `quantidade` e `preco_unitario`), `PAGAMENTO`, `AUDITORIA_RESERVA`. Atributos principais em `docs/regras.md`, seção 7.

### 2.1 Cardinalidades (mín., máx.)

| Relacionamento | Cardinalidade | Observação |
|---|---|---|
| Tipo de quarto — classifica — Quarto | (1,1) — (0,N) | Todo quarto tem tipo; um tipo pode existir sem quartos |
| Hóspede — faz — Reserva | (1,1) — (0,N) | Reserva sempre tem hóspede; hóspede cadastrado pode não ter reserva |
| Quarto — é reservado em — Reserva | (1,1) — (0,N) | Uma reserva = um quarto |
| Reserva — registra — Consumo (com Serviço) | (1,1) — (0,N) | N:M resolvido por CONSUMO_RESERVA, que carrega quantidade e preço cobrado |
| Serviço — é consumido em — Consumo | (1,1) — (0,N) | Serviço do catálogo pode nunca ter sido consumido |
| Reserva — gera — Pagamento | (1,1) — (0,N) | Sinal, quitação e estorno |

---

## 3. Decisões de design

| Decisão | Justificativa |
|---|---|
| `RESERVA` separada de `QUARTO` | Datas e estado pertencem à reserva, não ao quarto: sem isso não há como checar sobreposição |
| Uma reserva = um quarto | Mantém o modelo pequeno; várias acomodações exigiriam outra entidade associativa (evolução futura) |
| `CONSUMO_RESERVA` como entidade associativa | N:M entre reserva e serviço, com atributos próprios (quantidade, preço cobrado) |
| PK artificial por identidade (`GENERATED BY DEFAULT AS IDENTITY`) | Mesma sintaxe nos dois bancos; `UNIQUE` no documento do hóspede e no número do quarto garante a unicidade do mundo real |
| Preço unitário copiado para `CONSUMO_RESERVA`, e diária copiada para `RESERVA` | O valor cobrado não muda se o catálogo ou a tarifa mudarem depois |
| Regra de sobreposição em procedure **e** (destaque) trigger | Defesa em profundidade: a procedure responde cedo; o trigger protege quem faz INSERT direto. No Oracle o trigger precisa ser composto, por causa da tabela mutante (ORA-04091) |
| Capacidade e transições de status em trigger | São regras que não podem depender de a aplicação lembrar; valem também para INSERT e UPDATE direto |
| Status NO_SHOW e LIMPEZA | NO_SHOW separa o hóspede que não apareceu do cancelamento antecipado; LIMPEZA dá ao quarto um ciclo realista após o check-out |
| Procedures sem COMMIT | Quem chama decide a transação; os testes e a demonstração usam ROLLBACK |
| Códigos de erro `HOTEL-00x` iguais nos dois bancos | A aplicação trata o erro de negócio da mesma forma, venha de onde vier |
| `ON DELETE` explícito em toda FK | Nenhuma FK usa CASCADE: histórico de reservas, consumos e pagamentos não pode sumir; RESTRICT no PostgreSQL e, no Oracle, omitir a cláusula equivale a bloquear |
| Auditoria em tabela própria, alimentada por trigger e sem FK | Não depende de a aplicação lembrar de registrar e sobrevive a qualquer remoção |
| Datas relativas a hoje nos dados de exemplo | As consultas dão o mesmo resultado em qualquer dia |
| Índices em arquivo separado (`04_indices.sql`) | Permite medir antes e depois |

<!-- TODO: incluir também a justificativa de normalização (3FN) e por que cada "coisa" é entidade e não atributo. -->

---

## 4. Como rodar

**Pré-requisito:** apenas Docker (o Oracle XE usa cerca de 2 GB de memória e leva 1 a 2 minutos na primeira subida).

```bash
docker compose up -d --wait            # PostgreSQL e Oracle prontos, com esquema, dados, procedures e índices
docker compose run --rm testes         # verificação automatizada nos DOIS bancos
docker compose --profile apps run --rm app-python
docker compose --profile apps run --rm app-java
docker compose down -v                 # limpar tudo
```

| Serviço | Porta | Usuário | Senha (**somente laboratório**) |
|---|---|---|---|
| PostgreSQL 17 | <5432> | <hotel> | <definida no docker-compose.yml> |
| Oracle XE 21 (`XEPDB1`) | <1521> | <hotel> | <definida no docker-compose.yml> |

### 4.1 Estrutura do repositório

```
hotel-host/
├── README.md · AGENTS.md · opencode.json
├── docker-compose.yml          # postgres, oracle, testes, app-python, app-java
├── der/                        # hotelhost.puml · hotelhost.png
├── docs/                       # regras.md · perguntas_de_negocio.md · ia-log.md
├── postgresql/                 # 01_ddl · 02_inserts · 03_consultas · 04_indices
├── oracle/                     # os mesmos quatro arquivos, em Oracle
├── procedures/                 # postgresql_procedures.sql · oracle_procedures.sql
├── performance/                # carga em massa, medição e explain_antes_depois.txt
├── python/                     # aplicação (psycopg + python-oracledb)
├── java/                       # aplicação JDBC
├── tests/                      # o mesmo teste roda nos dois bancos
└── docker/                     # scripts de inicialização dos bancos
```

### 4.2 O que foi testado

<!-- TODO: preencher com números reais, depois de rodar. Mínimo: 10 testes nos dois bancos. -->

| Arquivo de teste | Nº de testes | O que verifica |
|---|---|---|
| `tests/test_constraints.py` | <n> | Constraints barram dado inválido; toda constraint tem nome (`pk_`, `uk_`, `fk_`, `ck_`) |
| `tests/test_procedures.py` | <n> | Caminho feliz e os erros de negócio de cada procedure (HOTEL-002, 003, 004, 005, 009, 012, 013) |
| `tests/test_triggers.py` | <n> | Capacidade e transição de status barradas em INSERT/UPDATE direto; auditoria gravada |
| `tests/test_concorrencia.py` | <n> | Duas sessões reservando o mesmo quarto e as mesmas datas: só uma é atendida |
| `tests/test_consultas.py` | <n> | As 10 consultas dão o resultado esperado, igual nos dois bancos |
| **Total** | **<n>** | <n cenários × 2 bancos> |

### 4.3 As 10 consultas

Perguntas de negócio, decisões e dados de fronteira em [`docs/perguntas_de_negocio.md`](docs/perguntas_de_negocio.md); SQL em `*/03_consultas.sql`.

| # | Pergunta | Técnica |
|---|---|---|
| Q01 | Receita de diárias por tipo de quarto | JOIN + GROUP BY/HAVING |
| Q02 | Chegadas dos próximos 7 dias | JOIN |
| Q03 | Ranking dos hóspedes que mais gastaram | window RANK |
| Q04 | Quartos disponíveis num período | NOT EXISTS |
| Q05 | Receita acumulada mês a mês | SUM OVER |
| Q06 | Tipos de quarto com cancelamento acima de 20% | GROUP BY/HAVING |
| Q07 | Participação de cada serviço na receita de consumo | window sobre agregação |
| Q08 | Última estadia concluída de cada hóspede | ROW_NUMBER |
| Q09 | Hóspedes que usaram todos os serviços extras | divisão relacional |
| Q10 | Reservas e receita por tipo e situação, com subtotais | ROLLUP |

---

## 5. Performance

<!-- TODO: medir de verdade (massa de dezenas de milhares de linhas, em esquema à parte).
Nunca escrever "melhorou" sem o plano colado. Não inventar número. -->

| Consulta | Índice criado | Plano antes | Plano depois | Tempo antes | Tempo depois |
|---|---|---|---|---|---|
| <Q04 disponibilidade> | `ix_reserva_quarto_datas` (quarto_id, data_entrada, data_saida) | <Seq Scan / TABLE ACCESS FULL> | <Index Scan / INDEX RANGE SCAN> | <ms> | <ms> |
| <Q02 chegadas> | `ix_reserva_checkin` (data_entrada) | <...> | <...> | <ms> | <ms> |
| <Q03 gasto por hóspede> | `ix_reserva_hospede` (hospede_id, FK) | <...> | <...> | <ms> | <ms> |

**O que mudou no plano:** <explicar com as palavras do grupo>

Planos completos (texto colado): [`performance/explain_antes_depois.txt`](performance/explain_antes_depois.txt).
Condições da medição: <máquina, contêiner, nº de linhas, nº de repetições>.

---

## 6. Dificuldades e aprendizados

<!-- TODO: preencher só com o que de fato aconteceu; cada linha pode virar registro na seção 7.
As colunas de PostgreSQL e Oracle abaixo são diferenças conhecidas; a última coluna é do grupo. -->

### 6.1 PostgreSQL × Oracle

| Ponto | PostgreSQL | Oracle | O que o grupo fez |
|---|---|---|---|
| Tipos de texto e número | `VARCHAR`, `NUMERIC`, `INTEGER` | `VARCHAR2`, `NUMBER` | <...> |
| Valor padrão de data | `CURRENT_DATE` | `TRUNC(SYSDATE)` | <...> |
| `ON DELETE RESTRICT` | existe | não existe (omitir a cláusula) | <...> |
| Aritmética de datas (noites) | `date − date` devolve inteiro | `date − date` devolve número; usar `TRUNC` | <...> |
| Horário 12:00 e 18:00 no check-out | `data + INTERVAL '12 hours'` | `data + 12/24` (literal `TIME` dá ORA-01861) | <...> |
| Trigger que consulta a própria tabela | permitido | ORA-04091 (tabela mutante): usar trigger composto | <...> |
| Linguagem procedural | PL/pgSQL, `RAISE EXCEPTION` | PL/SQL, `RAISE_APPLICATION_ERROR` | <...> |
| Erro dentro da transação | aborta a transação inteira (SAVEPOINT) | desfaz só o comando que falhou | <...> |
| <ponto do grupo> | <...> | <...> | <...> |

### 6.2 Outras dificuldades

| Dificuldade | Causa | Solução | Aprendizado |
|---|---|---|---|
| <ex.: duas sessões reservaram o mesmo quarto> | <procedure não travava a linha> | <...> | <...> |
| <...> | <...> | <...> | <...> |

---

## 7. Uso de IA

**Ferramenta e modelo:** <OpenCode + modelo via OpenRouter> · **Skills usadas:** <grilling, to-spec, ...>
**Configuração versionada:** `opencode.json` (push negado, comandos com `ask`) e `AGENTS.md`.

### 7.1 Registros

<!-- TODO: mínimo 5 registros, 4 tipos de artefato diferentes, 2 erros reais com a mensagem de erro.
Anotar na hora em que acontece (docs/ia-log.md). Não inventar erros: o professor pode pedir para reproduzir. -->

| # | Artefato | Pedido (resumo) | O que o agente errou ou omitiu | O que o grupo fez |
|---|---|---|---|---|
| 1 | `der/hotelhost.puml` | <...> | <...> | <...> |
| 2 | `oracle/01_ddl.sql` | <...> | <mensagem de erro real, ex.: ORA-xxxxx> | <...> |
| 3 | `postgresql/03_consultas.sql` | Rascunho das 10 consultas a partir das perguntas de negócio | <...> | <...> |
| 4 | `procedures/` | <...> | <...> | <...> |
| 5 | `performance/explain_antes_depois.txt` | <...> | <...> | <...> |

### 7.2 Reflexão do grupo

- **Onde a IA mais ajudou:** <...>
- **Onde mais errou:** <...>
- **O que faríamos diferente:** <...>
- **Regra que ficou no `AGENTS.md`:** <...>

---

### Checklist antes da tag v1.0.0

- [ ] `docker compose up -d --wait` sobe do zero, sem erro, nos dois bancos
- [ ] `docker compose run --rm testes` verde (≥ 10 testes nos dois bancos)
- [ ] Nenhuma senha real, chave de API ou `.env` no Git (`git log -p`)
- [ ] Todos os integrantes com commits e capazes de explicar o próprio trecho
- [ ] README com os 7 blocos preenchidos, sem `<...>` restante
