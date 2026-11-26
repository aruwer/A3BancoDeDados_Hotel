# Roteiro de Casos de Teste: Hotel Host

Casos de teste (CTs) escritos a partir dos **requisitos** (`A3_Projeto_BD.html`, `regras.md`, `AGENTS.md`), e não do código. Servem de base para os testes automatizados, os testes manuais e a defesa oral.

> Escopo: `main` já com as PRs #27 (app Python e Docker), #29 (consultas Q01 a Q10 e performance) e #30 (log de IA) mergeadas.
> Este documento **só descreve** os CTs. Nenhum código de teste foi escrito ainda.

---

## 1. Convenções

### 1.1 Padrão BDD (Gherkin)

As palavras-chave ficam em inglês (`Feature`, `Background`, `Scenario`, `Scenario Outline`, `Examples`, `Given`, `When`, `Then`, `And`, `But`) e o restante em português.

```gherkin
Scenario: Cancelar com 7 dias de antecedência não gera multa
  Given uma reserva CONFIRMADA de 3 noites com diária de R$ 200,00
  And a data de entrada é daqui a 7 dias
  When a procedure cancelar_reserva é chamada
  Then o status da reserva passa a ser CANCELADA
  And a multa registrada é R$ 0,00
```

### 1.2 Códigos

| Prefixo | Tipo | Como roda |
|---|---|---|
| CT-U | Unitário: uma constraint, uma procedure, um trigger ou uma consulta isolada | Automatizado (SQL/pytest) |
| CT-I | Integração: vários objetos juntos, duas sessões, Docker, aplicação + banco | Automatizado |
| CT-R | Regressão: protege algo que já quebrou ou que mudanças costumam quebrar | Automatizado, roda **só antes da entrega final** (não entre merges) |
| CT-A | Aplicação Python: bind, `Decimal`, erro de negócio, transação | Automatizado (pytest + psycopg) |
| CT-M | Manual: leitura, conferência humana, demonstração, entrega | Manual, com checklist |

### 1.3 Status de cada CT frente ao código

O `regras.md` descreve um modelo maior que o implementado. Cada CT leva um status para a matriz mostrar o que falta antes da entrega:

| Status | Significado |
|---|---|
| **IMPL** | A regra existe no código (main ou PR indicada) e o CT deve passar. |
| **PARCIAL** | Existe só parte da regra (por exemplo, a constraint barra uma fronteira, mas não a outra). O CT aponta o que falta. |
| **LACUNA** | A regra está nos requisitos, mas não há código. O CT **deve falhar hoje**. Ou implementa-se a regra, ou se registra a decisão de corte no README (o `regras.md` seção 2 permite cortar as regras "Extra"). |

### 1.4 Vocabulário usado nos CTs (nomes do código atual)

Os nomes de **status** do `regras.md`, do `README.md` e do `perguntas_de_negocio.md` já são os do banco (`PENDENTE`, `CONFIRMADA`, `CHECK-IN`, `CHECK-OUT`, `CANCELADA`, `NO-SHOW`). Os nomes antigos `EM_ANDAMENTO`, `FINALIZADA` e `NO_SHOW` não existem mais nos documentos e são recusados pelo `ck_reserva_status` (CT-U04). Restam diferenças só nos nomes de tabelas e colunas, onde vale o nome do banco; o equivalente do `regras.md` aparece entre parênteses na primeira vez.

| Banco (main) | `regras.md` |
|---|---|
| `quarto.status_quarto = 'MANUTENCAO'` | `quarto.status = MANUTENCAO` |
| `categoria_quarto` | `TIPO_QUARTO` |
| `servico.valor_unitario`, `consumo_servico` | `SERVICO.preco_unitario`, `CONSUMO_RESERVA` |
| `cancelamento.taxa_multa_aplicada` | `RESERVA.multa_cancelamento` |

### 1.5 Pré-condições gerais (`Background` de quase todos os CTs)

```gherkin
Background:
  Given o banco PostgreSQL 17 foi criado do zero com 01_ddl.sql, 02_inserts.sql, postgresql_procedures.sql e 04_indices.sql
  And os dados de exemplo originais estão carregados
  And cada cenário roda dentro de uma transação desfeita no final (ROLLBACK)
```

Dados de exemplo usados como referência (`02_inserts.sql`): categorias Standard (cap. 2, R$ 200), Superior (cap. 3, R$ 300) e Suíte (cap. 4, R$ 500); quartos 101 a 302, com o 103 em manutenção e o 302 sem reservas; hóspedes 1 a 8; reservas 1 a 9 em CHECK-OUT, 10 em CHECK-IN, 11, 12 e 18 futuras, 13 a 16 canceladas e 17 em NO-SHOW.

---

## 2. Matriz de rastreabilidade (requisito → CTs)

### 2.1 Regras de negócio (`regras.md`)

| Requisito | Prioridade | Status no código | CTs |
|---|---|---|---|
| RN-01 estadia de 1 a 30 noites | Núcleo | PARCIAL (só `saída > entrada`; falta o máximo de 30) | CT-U01, CT-U02, CT-U03 |
| RN-02 sem sobreposição de reservas ativas | Núcleo | IMPL (trigger) | CT-U30 a CT-U37, CT-I05, CT-I06, CT-R05 |
| RN-03 hóspedes de 1 até a capacidade | Núcleo | LACUNA | CT-U40 a CT-U43 |
| RN-04 cancelamento e multa | Núcleo | IMPL | CT-U50 a CT-U63, CT-I01, CT-I07 |
| RN-05 desconto de fidelidade | Extra | IMPL | CT-U70 a CT-U76 |
| RN-06 quarto em manutenção / check-in só em quarto disponível | Núcleo | LACUNA | CT-U80 a CT-U84 |
| RN-07 máquina de estados da reserva | Núcleo | LACUNA | CT-U90 a CT-U96 |
| RN-08 late check-out | Núcleo | IMPL | CT-U100 a CT-U108 |
| RN-09 pagamento cobre o saldo | Núcleo | IMPL | CT-U110 a CT-U115, CT-I02 |
| RN-10 sinal de 30% | Extra | LACUNA | CT-U120 a CT-U122 |
| RN-11 consumo só em reserva em andamento | Extra | LACUNA | CT-U130 a CT-U133 |
| RN-12 janela do check-in | Extra | LACUNA | CT-U140 a CT-U143 |
| Códigos HOTEL-001 a HOTEL-013 | Núcleo | PARCIAL (001, 005, 006, 007, 009, 012 existem) | CT-U150 a CT-U155 |
| Auditoria (`trg_reserva_auditoria`) | Núcleo (regras.md) | LACUNA | CT-U160, CT-U161 |

### 2.2 Rubrica da A3 (40 pontos)

| Critério | Pts | CTs que o protegem |
|---|---|---|
| 1. DER | 6 | CT-M10 a CT-M12 |
| 2. DDL | 6 | CT-U01 a CT-U29, CT-I10, CT-I11, CT-M13 |
| 3. 10 consultas | 10 | CT-U170 a CT-U181, CT-R10, CT-M14 |
| 4. 2 procedures + 1 trigger | 6 | CT-U30 a CT-U161, CT-I01 a CT-I09, CT-R01 a CT-R09 |
| 5. 3 índices + EXPLAIN | 4 | CT-U190 a CT-U194, CT-I20, CT-I21, CT-M15 |
| 6. Conexão pela aplicação | 4 | CT-A01 a CT-A15, CT-I30 |
| 7. Organização e documentação (README) | 2 | CT-M20 a CT-M26 |
| 7. Uso de IA | 2 | CT-M30 a CT-M36 |
| Docker Compose (critério transversal: "script que não roda = zero") | transversal | CT-I10 a CT-I14, CT-M01 a CT-M03 |
| Verificação automatizada mínima (10 testes) | transversal | Todo este roteiro; CT-M04 conta e confere |

---

## 3. Testes unitários (CT-U)

### 3.1 Constraints do DDL (critério 2)

```gherkin
Feature: Constraints barram dado inválido (DDL)
  Background: ver seção 1.5
```

**CT-U01 · RN-01 · Saída igual à entrada (0 noite) é recusada** · IMPL (`ck_reserva_datas`)
```gherkin
Scenario: Reserva de 0 noite
  Given um hóspede e um quarto válidos
  When uma reserva é inserida com data de entrada igual à data de saída
  Then o banco recusa com violação de CHECK (SQLSTATE 23514) em ck_reserva_datas
```

**CT-U02 · RN-01 · Saída antes da entrada é recusada** · IMPL
```gherkin
Scenario: Datas invertidas
  When uma reserva é inserida com saída um dia antes da entrada
  Then o banco recusa com SQLSTATE 23514 em ck_reserva_datas
```

**CT-U03 · RN-01 · Limite de 30 noites** · PARCIAL (o DDL não limita o máximo)
```gherkin
Scenario Outline: Fronteiras de 1 a 30 noites
  Given um quarto sem reservas no período
  When uma reserva é inserida com <noites> noites
  Then o resultado é <resultado>
  Examples:
    | noites | resultado                                  |
    | 1      | aceita                                     |
    | 30     | aceita                                     |
    | 31     | recusada (CHECK ck_reserva_estadia, HOTEL-002) |
```
Esperado hoje: a linha de 31 noites **falha** (a reserva é aceita). Falta `ck_reserva_estadia` com máximo de 30.

**CT-U04 · Status da reserva fora do domínio** · IMPL (`ck_reserva_status`)
```gherkin
Scenario Outline: Domínio do status
  When uma reserva é inserida com status <status>
  Then o resultado é <resultado>
  Examples:
    | status     | resultado |
    | PENDENTE   | aceita    |
    | CONFIRMADA | aceita    |
    | CHECK-IN   | aceita    |
    | CHECK-OUT  | aceita    |
    | CANCELADA  | aceita    |
    | NO-SHOW    | aceita    |
    | FINALIZADA | recusada, SQLSTATE 23514 |
    | (nulo)     | recusada, SQLSTATE 23502 |
```

**CT-U05 · Desconto de fidelidade fora de 0, 5 ou 10** · PARCIAL
```gherkin
Scenario Outline: Percentual de desconto
  When uma reserva é inserida com percentual_desconto <valor>
  Then o resultado é <resultado>
  Examples:
    | valor | resultado |
    | 0     | aceita    |
    | 5     | aceita    |
    | 10    | aceita    |
    | -1    | recusada (23514) |
    | 101   | recusada (23514) |
    | 7     | recusada pelo regras.md seção 5.3 (0, 5 ou 10); hoje é aceita |
```

**CT-U06 · Valor bruto negativo** · IMPL (`ck_reserva_valor_bruto`)
```gherkin
Scenario: Valor bruto negativo
  When uma reserva é inserida com valor_total_bruto = -0,01
  Then o banco recusa com SQLSTATE 23514
  But valor_total_bruto = 0,00 é aceito
```

**CT-U07 · Check-out real não pode ser antes do check-in real** · IMPL (`ck_reserva_checkout`)
```gherkin
Scenario: Saída antes da entrada real
  When uma reserva é inserida com data_checkout_real um minuto antes de data_checkin_real
  Then o banco recusa com SQLSTATE 23514
```

**CT-U08 · CPF duplicado** · IMPL (`uk_hospede_cpf`)
```gherkin
Scenario: Dois hóspedes com o mesmo CPF
  Given o hóspede 1 com CPF 12345678909
  When outro hóspede é inserido com o mesmo CPF
  Then o banco recusa com SQLSTATE 23505 em uk_hospede_cpf
```

**CT-U09 · E-mail duplicado** · IMPL (`uk_hospede_email`), mesma estrutura do CT-U08, SQLSTATE 23505.

**CT-U10 · Hóspede sem campo obrigatório** · IMPL
```gherkin
Scenario Outline: Campos NOT NULL do hóspede
  When um hóspede é inserido com <campo> nulo
  Then o banco recusa com SQLSTATE 23502
  Examples:
    | campo         |
    | cpf           |
    | nome_completo |
    | email         |
```

**CT-U11 · Tamanho do CPF** · PARCIAL
```gherkin
Scenario: CPF com mais de 11 caracteres
  When um hóspede é inserido com CPF de 12 caracteres
  Then o banco recusa com SQLSTATE 22001
  But CPF com 5 caracteres é aceito hoje (não há CHECK de formato; registrar a decisão)
```

**CT-U12 · Número de quarto duplicado** · IMPL (`uk_quarto_numero`), SQLSTATE 23505.

**CT-U13 · Categoria com capacidade ou diária inválidas** · IMPL
```gherkin
Scenario Outline: Domínio da categoria
  When uma categoria é inserida com capacidade <cap> e diária <valor>
  Then o resultado é <resultado>
  Examples:
    | cap | valor  | resultado |
    | 1   | 0,01   | aceita    |
    | 0   | 100,00 | recusada (ck_categoria_capacidade) |
    | 2   | 0,00   | recusada (ck_categoria_valor)      |
    | 2   | -5,00  | recusada (ck_categoria_valor)      |
```

**CT-U14 · FK de quarto para categoria é RESTRICT** · IMPL
```gherkin
Scenario: Apagar categoria com quartos
  Given a categoria 1 tem quartos
  When a categoria 1 é apagada
  Then o banco recusa com SQLSTATE 23503 (fk_quarto_categoria)
```

**CT-U15 · FKs de reserva para hóspede e quarto são RESTRICT** · IMPL
```gherkin
Scenario Outline: Apagar pai com reservas
  When o <pai> que possui reservas é apagado
  Then o banco recusa com SQLSTATE 23503
  Examples:
    | pai    |
    | hóspede 1 |
    | quarto 4  |
```

**CT-U16 · Reserva com hóspede ou quarto inexistente** · IMPL, SQLSTATE 23503.

**CT-U17 · Cancelamento: uma multa por reserva** · IMPL (`uk_cancelamento_reserva`)
```gherkin
Scenario: Segunda linha de cancelamento para a mesma reserva
  Given a reserva 13 já tem cancelamento
  When outro cancelamento é inserido para a reserva 13
  Then o banco recusa com SQLSTATE 23505
```

**CT-U18 · Multa negativa** · IMPL (`ck_cancelamento_taxa`), SQLSTATE 23514; multa 0,00 aceita.

**CT-U19 · Consumo com quantidade zero ou negativa** · IMPL (`ck_consumo_quantidade`)
```gherkin
Scenario Outline: Quantidade do consumo
  When um consumo é inserido com quantidade <q>
  Then o resultado é <resultado>
  Examples:
    | q  | resultado |
    | 1  | aceito    |
    | 0  | recusado, SQLSTATE 23514 |
    | -1 | recusado, SQLSTATE 23514 |
```

**CT-U20 · Serviço com valor negativo** · IMPL (`ck_servico_valor`), valor 0 aceito.

**CT-U21 · Pagamento com valor zero, tipo ou forma inválidos** · IMPL (já coberto em `tests/test_procedures.sql`)
```gherkin
Scenario Outline: Domínio do pagamento
  When um pagamento é inserido com tipo <tipo>, forma <forma> e valor <valor>
  Then o resultado é <resultado>
  Examples:
    | tipo      | forma          | valor | resultado |
    | PAGAMENTO | PIX            | 10    | aceito |
    | ESTORNO   | CARTAO_DEBITO  | 0,01  | aceito |
    | PAGAMENTO | PIX            | 0     | recusado, 23514 |
    | DEPOSITO  | PIX            | 10    | recusado, 23514 |
    | PAGAMENTO | CHEQUE         | 10    | recusado, 23514 |
```

**CT-U22 · Pagamento para reserva inexistente** · IMPL, SQLSTATE 23503.

**CT-U23 · Pagamento: FK é RESTRICT** · IMPL
```gherkin
Scenario: Apagar reserva com pagamento
  Given a reserva tem um pagamento lançado
  When a reserva é apagada
  Then o banco recusa com SQLSTATE 23503 (histórico financeiro preservado)
```

**CT-U24 · ON DELETE de cancelamento e consumo** · PARCIAL (divergência a decidir)
```gherkin
Scenario: Apagar reserva com consumo ou cancelamento
  Given o regras.md seção 5.3 diz que todas as FKs bloqueiam (RESTRICT)
  When uma reserva que tem consumo é apagada
  Then o banco recusa com SQLSTATE 23503
```
Hoje `fk_consumo_reserva` e `fk_cancelamento_reserva` são `ON DELETE CASCADE`, então a reserva é apagada junto. Decidir: ou o DDL muda, ou o `regras.md` e o README documentam o CASCADE como decisão.

**CT-U25 · Toda constraint tem nome com prefixo pk_, uk_, fk_ ou ck_** · IMPL
```gherkin
Scenario: Nomes de constraints no catálogo
  When consulto pg_constraint no schema public
  Then nenhuma constraint tem nome gerado automaticamente (como reserva_check1 ou reserva_pkey)
  And toda FK tem confdeltype explícito (a = no action, r = restrict, c = cascade)
```

**CT-U26 · Tipos do dialeto PostgreSQL** · IMPL
```gherkin
Scenario: Nenhum tipo ou sintaxe Oracle
  When varro os scripts de postgresql/ e procedures/
  Then não existem VARCHAR2, NUMBER, DUAL, NVL, SYSDATE nem RAISE_APPLICATION_ERROR
```

**CT-U27 · Valores monetários usam NUMERIC/DECIMAL(10,2)** · IMPL
```gherkin
Scenario: Tipo das colunas de dinheiro
  When consulto information_schema.columns
  Then valor_total_bruto, valor_final_pago, valor_diaria_base, valor_unitario, valor_total_item, taxa_multa_aplicada e pagamento.valor são numeric(10,2)
```

**CT-U28 · Dados de exemplo usam datas relativas** · IMPL
```gherkin
Scenario: Nenhuma data fixa nos inserts
  When varro 02_inserts.sql
  Then todas as datas de reserva usam CURRENT_DATE ou CURRENT_TIMESTAMP (nenhum literal como '2025-01-01')
```

**CT-U29 · Dados fictícios (LGPD)** · IMPL, ver CT-M24 (conferência humana).

### 3.2 Trigger de sobreposição (RN-02, `trg_reserva_sobreposicao`)

```gherkin
Feature: Um quarto não pode ter duas reservas ativas sobrepostas, nem por INSERT direto
```

**CT-U30 · Sobreposição de 1 noite é recusada** · IMPL
```gherkin
Scenario: Entrada um dia antes da saída da outra
  Given o quarto 302 tem reserva CONFIRMADA de D+10 a D+13
  When insiro direto uma reserva CONFIRMADA no quarto 302 de D+12 a D+14
  Then o banco recusa com HOTEL-005
```

**CT-U31 · Saída e entrada no mesmo dia são aceitas** · IMPL
```gherkin
Scenario: Back-to-back
  Given o quarto 302 tem reserva CONFIRMADA de D+10 a D+13
  When insiro uma reserva de D+13 a D+15 no mesmo quarto
  Then a reserva é aceita
  And uma reserva de D+8 a D+10 também é aceita
```

**CT-U32 · Reserva engloba ou está dentro de outra** · IMPL
```gherkin
Scenario Outline: Formas de sobreposição
  Given o quarto 302 tem reserva ativa de D+10 a D+15
  When insiro reserva de <entrada> a <saida>
  Then o resultado é <resultado>
  Examples:
    | entrada | saida | resultado |
    | D+11    | D+13  | recusada (dentro)       |
    | D+8     | D+18  | recusada (engloba)      |
    | D+8     | D+11  | recusada (pega o início)|
    | D+14    | D+18  | recusada (pega o fim)   |
    | D+10    | D+15  | recusada (idêntica)     |
    | D+15    | D+17  | aceita                  |
    | D+7     | D+10  | aceita                  |
```

**CT-U33 · Reservas CANCELADA, NO-SHOW e CHECK-OUT não bloqueiam** · IMPL
```gherkin
Scenario Outline: Reserva não ativa no mesmo período
  Given o quarto 302 tem reserva <status> de D+10 a D+13
  When insiro uma reserva CONFIRMADA no mesmo quarto e período
  Then a reserva é aceita
  Examples:
    | status    |
    | CANCELADA |
    | NO-SHOW   |
    | CHECK-OUT |
```

**CT-U34 · Reservas PENDENTE, CONFIRMADA e CHECK-IN bloqueiam** · IMPL, mesma estrutura do CT-U33, resultado HOTEL-005.

**CT-U35 · Quartos diferentes não conflitam** · IMPL
```gherkin
Scenario: Mesmo período em quartos distintos
  When insiro duas reservas ativas no mesmo período em quartos 301 e 302
  Then ambas são aceitas
```

**CT-U36 · UPDATE que cria conflito é recusado** · IMPL
```gherkin
Scenario Outline: UPDATE direto
  Given duas reservas ativas no quarto 302, sem sobreposição
  When faço UPDATE <alteracao> na segunda
  Then o banco recusa com HOTEL-005
  Examples:
    | alteracao |
    | movendo as datas para dentro do período da primeira |
    | trocando o quarto para o quarto da primeira         |
    | reativando uma reserva CANCELADA (CANCELADA para CONFIRMADA) em período ocupado |
```

**CT-U37 · UPDATE inofensivo não dispara a busca** · IMPL
```gherkin
Scenario: Atualizar colunas sem relação com a regra
  Given uma reserva ativa
  When atualizo valor_final_pago ou data_checkin_real
  Then o UPDATE é aceito sem erro
  And a própria linha não conta como conflito de si mesma
```

### 3.3 Capacidade de hóspedes (RN-03) · LACUNA

O modelo atual não tem `numero_hospedes` na `reserva`. Os CTs abaixo exigem a coluna e a validação.

**CT-U40 · Hóspedes igual à capacidade é aceito**
```gherkin
Scenario: Quarto Standard (capacidade 2) com 2 hóspedes
  When registro uma reserva no quarto 101 com 2 hóspedes
  Then a reserva é aceita
```

**CT-U41 · Hóspedes acima da capacidade é recusado** · HOTEL-003
```gherkin
Scenario: Quarto Standard com 3 hóspedes
  When registro uma reserva no quarto 101 com 3 hóspedes
  Then o banco recusa com HOTEL-003
```

**CT-U42 · Zero hóspedes é recusado** · HOTEL-003; a constraint `ck_reserva_hospedes` (> 0) deve barrar até o INSERT direto.

**CT-U43 · Regra vale para INSERT direto** (a rubrica pede uma regra "que valha para quem insere direto")
```gherkin
Scenario: INSERT direto acima da capacidade
  When faço INSERT na tabela reserva com hóspedes = capacidade + 1, sem passar por procedure
  Then o trigger de validação recusa com HOTEL-003
```

### 3.4 Cancelamento e multa (RN-04, `cancelar_reserva`)

```gherkin
Feature: Multa de cancelamento por faixa de antecedência
  Background:
    Given uma reserva CONFIRMADA de 3 noites com valor bruto R$ 600,00 (diária D = R$ 200,00)
    And a procedure é chamada com p_hoje = entrada menos N dias
```

**CT-U50 · Faixas de multa (fronteiras 7, 6, 2, 1, 0 dias)** · IMPL
```gherkin
Scenario Outline: Multa por antecedência
  When cancelar_reserva é chamada com <dias> dias até a entrada
  Then o status final é <status>
  And a multa gravada em cancelamento é R$ <multa>
  Examples:
    | dias | status    | multa  |
    | 30   | CANCELADA | 0,00   |
    | 8    | CANCELADA | 0,00   |
    | 7    | CANCELADA | 0,00   |
    | 6    | CANCELADA | 100,00 |
    | 2    | CANCELADA | 100,00 |
    | 1    | CANCELADA | 200,00 |
    | 0    | CANCELADA | 200,00 |
    | -1   | NO-SHOW   | 200,00 |
    | -30  | NO-SHOW   | 200,00 |
```

**CT-U51 · Multa usa a diária da reserva e não da categoria** · IMPL
```gherkin
Scenario: Reserva 12 (3 noites, bruto 900, D = 300) a 5 dias
  When cancelo a reserva 12
  Then a multa é R$ 150,00 (50% de 300)
```

**CT-U52 · Arredondamento a 2 casas** · IMPL
```gherkin
Scenario: Diária com dízimas
  Given reserva de 3 noites com bruto R$ 100,00 (D = 33,333...)
  When cancelo com 1 dia de antecedência
  Then a multa é R$ 33,33
  And com 3 dias de antecedência a multa é R$ 16,67 (50% de 33,333... arredondado)
```

**CT-U53 · Reserva PENDENTE também pode ser cancelada** · IMPL (reserva 18)

**CT-U54 · Só PENDENTE e CONFIRMADA cancelam** · IMPL
```gherkin
Scenario Outline: Status que não cancelam
  Given a reserva está <status>
  When cancelar_reserva é chamada
  Then o banco recusa com HOTEL-007
  And nenhuma linha é criada em cancelamento
  Examples:
    | status    | reserva de exemplo |
    | CHECK-IN  | 10 |
    | CHECK-OUT | 1  |
    | CANCELADA | 13 |
    | NO-SHOW   | 17 |
```

**CT-U55 · Cancelar duas vezes não duplica a multa** · IMPL
```gherkin
Scenario: Segunda chamada
  Given a reserva 12 foi cancelada
  When cancelar_reserva é chamada de novo
  Then o banco recusa com HOTEL-007
  And continua existindo uma única linha em cancelamento para a reserva 12
```

**CT-U56 · Parâmetros inválidos** · IMPL
```gherkin
Scenario Outline: Erros de parâmetro
  When chamo <chamada>
  Then o erro é <codigo>
  Examples:
    | chamada                     | codigo    |
    | cancelar_reserva(NULL)      | HOTEL-001 |
    | cancelar_reserva(999999)    | HOTEL-006 |
```

**CT-U57 · Cancelamento altera duas tabelas** · IMPL
```gherkin
Scenario: Efeito completo
  When cancelo a reserva 12
  Then reserva.status_reserva muda para CANCELADA
  And cancelamento recebe exatamente uma linha com multa e motivo preenchidos
```

**CT-U58 · Motivo padrão descreve a faixa** · IMPL
```gherkin
Scenario Outline: Texto do motivo
  When cancelo sem informar p_motivo
  Then o motivo contém <trecho>
  Examples:
    | dias | trecho |
    | 8    | sem multa |
    | 4    | 50% |
    | 1    | 100% |
    | -1   | No-show |
```

**CT-U59 · Motivo informado prevalece** · IMPL, `p_motivo = 'Hóspede doente'` é gravado como veio.

**CT-U60 · Reserva cancelada libera o quarto** · IMPL
```gherkin
Scenario: Reservar o mesmo período depois do cancelamento
  Given a reserva 12 (quarto 4, D+5 a D+8) foi cancelada
  When insiro nova reserva ativa no quarto 4 no mesmo período
  Then a reserva é aceita
```

**CT-U61 · Estorno do sinal (tabela 4.1)** · IMPL
```gherkin
Scenario Outline: Estorno = maior valor entre (sinal - multa) e 0
  Given uma reserva de 3 noites com D = R$ 200,00 e sinal pago de R$ 180,00
  When cancelo com <dias> dias de antecedência
  Then o estorno lançado é R$ <estorno>
  Examples:
    | dias | multa  | estorno |
    | 7    | 0,00   | 180,00  |
    | 6    | 100,00 | 80,00   |
    | 1    | 200,00 | 0,00    |
    | -1   | 200,00 | 0,00    |
```
`cancelar_reserva` lança o ESTORNO em `pagamento` (e o valor devido em `cancelamento.valor_devido`).

**CT-U62 · Valor devido quando a multa passa do sinal** · IMPL, a multa de R$ 200,00 com sinal de R$ 180,00 deixa R$ 20,00 devidos, registrados de forma consultável (o `regras.md` seção 4.1 exige "valor devido").

**CT-U63 · Cancelamento não faz COMMIT nem ROLLBACK** · IMPL, ver CT-U154.

### 3.5 Desconto de fidelidade (RN-05, `fazer_checkout`)

```gherkin
Feature: Desconto por estadias concluídas anteriores
  Background:
    Given reserva em CHECK-IN, 3 noites, bruto R$ 600,00, saída prevista = hoje
    And check-out às 11:00 do dia previsto, sem consumo
```

**CT-U70 · Fronteiras 4, 5, 9 e 10 estadias** · IMPL
```gherkin
Scenario Outline: Percentual por histórico
  Given o hóspede tem <n> estadias CHECK-OUT anteriores
  When o check-out é feito
  Then percentual_desconto = <desc>
  And valor_final_pago = R$ <final>
  Examples:
    | n  | desc | final  |
    | 0  | 0    | 600,00 |
    | 4  | 0    | 600,00 |
    | 5  | 5    | 570,00 |
    | 9  | 5    | 570,00 |
    | 10 | 10   | 540,00 |
    | 25 | 10   | 540,00 |
```

**CT-U71 · A reserva em check-out não conta como estadia anterior** · IMPL
```gherkin
Scenario: Quinta estadia
  Given o hóspede tem 4 estadias concluídas e a reserva atual é a quinta
  When o check-out é feito
  Then o desconto é 0% (a atual ainda não conta)
```

**CT-U72 · Só CHECK-OUT conta** · IMPL
```gherkin
Scenario: Reservas canceladas, no-show e pendentes não contam
  Given o hóspede tem 9 reservas CANCELADA ou NO-SHOW e 3 CHECK-OUT
  When o check-out é feito
  Then o desconto é 0%
```

**CT-U73 · Desconto só sobre as diárias** · IMPL
```gherkin
Scenario: Consumo de R$ 100,00 com 5% de desconto
  When o check-out é feito
  Then valor final = 600 x 0,95 + 100 = R$ 670,00
```

**CT-U74 · Taxa de late check-out usa a diária cheia** · IMPL
```gherkin
Scenario: 10% de desconto com saída às 12:00:01
  Then valor final = 540,00 + 100,00 (50% de D = 200) = R$ 640,00
```

**CT-U75 · Estadias de outro hóspede não contam** · IMPL, hóspede A com 10 estadias, hóspede B com 0 faz check-out e recebe 0%.

**CT-U76 · Fronteira sobre a base do desconto** · IMPL
```gherkin
Scenario: Arredondamento com desconto
  Given bruto R$ 333,33 e desconto de 5%
  Then o valor final é arredondado a 2 casas (316,66)
```

### 3.6 Manutenção do quarto e check-in (RN-06, RN-12) · LACUNA

O DDL guarda `status_quarto` (DISPONIVEL, OCUPADO, LIMPEZA, MANUTENCAO; antes era o booleano `status_manutencao`), mas `registrar_reserva` e `fazer_checkin` ainda não existem.

**CT-U80 · Reserva em quarto de manutenção é recusada** · HOTEL-004
```gherkin
Scenario: Quarto 103 (manutenção)
  When registro uma reserva ativa para o quarto 103
  Then o banco recusa com HOTEL-004
```

**CT-U81 · Reserva em quarto DISPONIVEL é aceita**, quarto 101 sem conflito.

**CT-U82 · Reserva em quarto inexistente é recusada** · HOTEL-004 (hoje a FK barra com SQLSTATE 23503, mas sem código de negócio).

**CT-U83 · Check-in só em quarto DISPONIVEL**
```gherkin
Scenario Outline: Status do quarto no check-in
  Given o quarto está <status>
  When faço o check-in da reserva CONFIRMADA
  Then o resultado é <resultado>
  Examples:
    | status     | resultado |
    | DISPONIVEL | aceito    |
    | OCUPADO    | recusado, HOTEL-004 |
    | LIMPEZA    | recusado, HOTEL-004 |
    | MANUTENCAO | recusado, HOTEL-004 |
```
O modelo já tem os quatro status (decisão D-02); falta a procedure `fazer_checkin` para aplicar a regra.

**CT-U84 · Ciclo do quarto** · PARCIAL. OCUPADO para LIMPEZA (check-out) e LIMPEZA para DISPONIVEL (UPDATE de governança) estão cobertos em CT-U107; DISPONIVEL para OCUPADO (check-in) depende de `fazer_checkin`.

### 3.7 Máquina de estados da reserva (RN-07) · LACUNA

Hoje o `UPDATE` direto aceita qualquer troca de status (só o CHECK de domínio protege).

**CT-U90 a CT-U93 · Transições válidas**
```gherkin
Scenario Outline: Transição permitida
  Given uma reserva em <de>
  When faço UPDATE direto do status para <para>
  Then o UPDATE é aceito
  Examples:
    | de         | para      |
    | CONFIRMADA | CHECK-IN  |
    | CHECK-IN   | CHECK-OUT |
    | CONFIRMADA | CANCELADA |
    | CONFIRMADA | NO-SHOW   |
```
(Um CT por linha: CT-U90, CT-U91, CT-U92, CT-U93.)

**CT-U94 a CT-U96 · Transições inválidas** · HOTEL-007
```gherkin
Scenario Outline: Transição proibida
  Given uma reserva em <de>
  When faço UPDATE direto do status para <para>
  Then o banco recusa com HOTEL-007
  Examples:
    | de        | para       | CT      |
    | CHECK-OUT | CONFIRMADA | CT-U94  |
    | CANCELADA | CHECK-IN   | CT-U95  |
    | NO-SHOW   | CONFIRMADA | CT-U96  |
```
Também devem falhar: CHECK-IN para CANCELADA, CONFIRMADA para CHECK-OUT (pula o check-in).

### 3.8 Late check-out (RN-08, `fazer_checkout`)

```gherkin
Feature: Taxa de late check-out por horário
  Background:
    Given reserva em CHECK-IN, 3 noites, bruto R$ 600,00 (D = 200,00), saída prevista = hoje
    And hóspede sem desconto e sem consumo
```

**CT-U100 · Fronteiras de horário** · IMPL
```gherkin
Scenario Outline: Taxa por horário de saída
  When faço check-out em <horario> do dia previsto
  Then a taxa é R$ <taxa>
  And o valor final é R$ <final>
  Examples:
    | horario  | taxa   | final  |
    | 08:00:00 | 0,00   | 600,00 |
    | 12:00:00 | 0,00   | 600,00 |
    | 12:00:01 | 100,00 | 700,00 |
    | 15:00:00 | 100,00 | 700,00 |
    | 18:00:00 | 100,00 | 700,00 |
    | 18:00:01 | 200,00 | 800,00 |
    | 23:59:59 | 200,00 | 800,00 |
```

**CT-U101 · Saída antecipada não gera estorno nem taxa** · IMPL
```gherkin
Scenario: Saída um dia antes do previsto
  When faço check-out no dia anterior às 15:00
  Then o valor final continua R$ 600,00
  And nenhum ESTORNO é lançado em pagamento
```

**CT-U102 · Saída depois do dia previsto é recusada** · IMPL, HOTEL-012
```gherkin
Scenario: Um dia depois
  When faço check-out às 08:00 do dia seguinte ao previsto
  Then o banco recusa com HOTEL-012
  And a reserva continua em CHECK-IN
```

**CT-U103 · Saída antes do check-in real é recusada** · IMPL, HOTEL-001.

**CT-U104 · Horário padrão é agora** · IMPL, `p_data_hora_saida = NULL` usa `LOCALTIMESTAMP` (ver CT-R07 sobre horário do teste).

**CT-U105 · Check-out grava `data_checkout_real`** · IMPL, o horário informado é gravado como veio.

**CT-U106 · Consumos entram no valor final** · IMPL
```gherkin
Scenario: Reserva 10 (bruto 1200, consumos 70 + 45)
  When faço check-out dentro do prazo
  Then o valor final é R$ 1.315,00
```

**CT-U107 · Quarto vai para LIMPEZA no check-out** · IMPL (D-02). `fazer_checkout` leva o quarto a LIMPEZA, parte de OCUPADO, DISPONIVEL ou LIMPEZA, não sobrescreve MANUTENCAO, não mexe no quarto quando o check-out é recusado (HOTEL-009) e desfaz com o ROLLBACK. A governança devolve o quarto a DISPONIVEL por UPDATE.

**CT-U108 · Taxa de late check-out fica gravada na reserva** · IMPL. `RESERVA.taxa_checkout` guarda 0, 50% ou 100% da diária cheia (fronteiras 12:00:00, 12:00:01, 18:00:00, 18:00:01), e `valor_final_pago` = diárias com desconto + consumos + `taxa_checkout`. Reserva ativa tem taxa 0 e valor final nulo; check-out recusado não grava taxa.

### 3.9 Pagamento e saldo (RN-09, `fazer_checkout`)

**CT-U110 · Valor igual ao saldo é aceito; 1 centavo a menos é recusado** · IMPL
```gherkin
Scenario Outline: Fronteira do pagamento
  Given o saldo do check-out é R$ 600,00
  When informo valor pago R$ <valor>
  Then o resultado é <resultado>
  Examples:
    | valor  | resultado |
    | 600,00 | aceito; lança PAGAMENTO de 600,00 |
    | 599,99 | recusado, HOTEL-009 |
    | 650,00 | aceito; lança PAGAMENTO de 600,00 (troco fora do escopo) |
    | 0,00   | recusado, HOTEL-009 |
```

**CT-U111 · Saldo considera pagamentos e estornos já lançados** · IMPL
```gherkin
Scenario Outline: Saldo = valor final - (pagamentos - estornos)
  Given valor final R$ 600,00
  And pagamentos prévios R$ <pago> e estornos prévios R$ <estorno>
  When faço o check-out pagando o saldo
  Then o PAGAMENTO lançado é R$ <lancado>
  Examples:
    | pago   | estorno | lancado |
    | 180,00 | 0,00    | 420,00  |
    | 0,00   | 0,00    | 600,00  |
    | 700,00 | 100,00  | nenhum (saldo 0) |
    | 600,00 | 0,00    | nenhum, pagar 0 é aceito |
```

**CT-U112 · Forma de pagamento** · IMPL
```gherkin
Scenario Outline: Domínio da forma
  When faço check-out com forma <forma>
  Then o resultado é <resultado>
  Examples:
    | forma          | resultado |
    | (padrão)       | aceito, grava PIX |
    | DINHEIRO       | aceito |
    | CARTAO_CREDITO | aceito |
    | CARTAO_DEBITO  | aceito |
    | CHEQUE         | recusado, HOTEL-001 |
    | (nulo)         | recusado, HOTEL-001 |
```

**CT-U113 · Valor pago nulo ou negativo é recusado** · IMPL, HOTEL-001.

**CT-U114 · Check-out em status errado** · IMPL
```gherkin
Scenario Outline: Só CHECK-IN faz check-out
  When chamo fazer_checkout para a reserva <id> (<status>)
  Then o erro é <codigo>
  Examples:
    | id     | status    | codigo    |
    | 1      | CHECK-OUT | HOTEL-007 |
    | 11     | CONFIRMADA| HOTEL-007 |
    | 999999 | inexistente | HOTEL-006 |
    | NULL   | nulo      | HOTEL-001 |
```

**CT-U115 · Check-out altera duas tabelas** · IMPL
```gherkin
Scenario: Efeito completo
  When faço o check-out válido
  Then reserva muda para CHECK-OUT com data_checkout_real, percentual_desconto e valor_final_pago preenchidos
  And pagamento recebe uma linha PAGAMENTO com o valor do saldo
```

### 3.10 Sinal de 30% (RN-10) · LACUNA

**CT-U120 · Sinal exatamente 30% é aceito** · reserva de 3 noites com D = 200 (diárias 600) e sinal R$ 180,00.

**CT-U121 · Sinal 1 centavo abaixo de 30% é recusado** · HOTEL-013, sinal R$ 179,99.

**CT-U122 · Sinal é lançado como PAGAMENTO e a base ignora o desconto de fidelidade** · o sinal usa noites × D sem desconto.

### 3.11 Consumo de serviços (RN-11) · LACUNA

**CT-U130 · Consumo em reserva CHECK-IN é aceito** · reserva 10.

**CT-U131 · Consumo em reserva que não está em CHECK-IN é recusado** · HOTEL-010
```gherkin
Scenario Outline: Status da reserva no lançamento
  When lanço consumo em reserva <status>
  Then o resultado é <resultado>
  Examples:
    | status     | resultado |
    | CHECK-IN   | aceito |
    | CONFIRMADA | recusado, HOTEL-010 |
    | CHECK-OUT  | recusado, HOTEL-010 |
    | CANCELADA  | recusado, HOTEL-010 |
```

**CT-U132 · Preço unitário é copiado do serviço no lançamento** · hoje `valor_total_item` é digitado; o trigger deveria calcular `quantidade × valor_unitario` e uma mudança posterior do preço do serviço não altera consumos já lançados.

**CT-U133 · `valor_total_item` consistente com quantidade** · PARCIAL, hoje nada impede `valor_total_item` diferente de `quantidade × valor_unitario`.

### 3.12 Janela do check-in (RN-12) · LACUNA

**CT-U140 · Check-in no dia da entrada é aceito.**
**CT-U141 · Check-in na véspera é recusado** · HOTEL-008.
**CT-U142 · Check-in no dia da saída é recusado** · HOTEL-008.
**CT-U143 · Check-in grava `data_checkin_real` e coloca o quarto em OCUPADO.**

### 3.13 Códigos de erro e contrato das procedures

**CT-U150 · Formato `HOTEL-NNN: mensagem` com ERRCODE P0001** · IMPL
```gherkin
Scenario Outline: Cada erro de negócio carrega código estável
  When provoco o erro <codigo>
  Then SQLSTATE = P0001
  And a mensagem começa com "<codigo>:"
  Examples:
    | codigo    | como provocar |
    | HOTEL-001 | cancelar_reserva(NULL) |
    | HOTEL-005 | INSERT sobreposto |
    | HOTEL-006 | cancelar_reserva(999999) |
    | HOTEL-007 | cancelar_reserva(13) |
    | HOTEL-009 | check-out com 1 centavo a menos |
    | HOTEL-012 | check-out no dia seguinte |
```

**CT-U151 · Códigos sem uso** · PARCIAL, HOTEL-002, 003, 004, 008, 010 e 013 estão no `regras.md`, mas nenhum código os dispara (ver CT-U03, U41, U80, U141, U131, U121).

**CT-U152 · O código 011 permanece livre** · IMPL, nenhum script usa HOTEL-011.

**CT-U153 · Mensagens em português e sem dado sensível** · IMPL, a mensagem não traz CPF nem e-mail.

**CT-U154 · Nenhuma rotina faz COMMIT ou ROLLBACK** · IMPL
```gherkin
Scenario: Varredura do corpo das rotinas
  When consulto pg_proc para cancelar_reserva, fazer_checkout e fn_reserva_sobreposicao
  Then o corpo não contém COMMIT nem ROLLBACK
  And chamar a procedure dentro de BEGIN ... ROLLBACK desfaz tudo
```

**CT-U155 · Cada procedure e trigger tem comentário com a regra** · IMPL, ver CT-M22.

### 3.14 Auditoria (`trg_reserva_auditoria`) · LACUNA

**CT-U160 · Mudança de status grava auditoria** · não existe a tabela `auditoria_reserva`.
```gherkin
Scenario: Auditar a transição
  When o status da reserva muda de CONFIRMADA para CANCELADA
  Then auditoria_reserva recebe uma linha com status_antes, status_depois, usuário do banco e data e hora
```

**CT-U161 · UPDATE que não muda o status não grava auditoria.**

### 3.15 As 10 consultas (critério 3; PR #29)

Cada consulta é conferida contra um **valor esperado calculado à mão** a partir do `02_inserts.sql`. A tabela "Resultados esperados" do `perguntas_de_negocio.md` está com `_preencher_` e deve ser preenchida na primeira execução e **conferida por pessoa** (CT-M14), não copiada da saída.

| CT | Consulta | Dado de fronteira que o teste prova | Status |
|---|---|---|---|
| CT-U170 | Q01 receita por categoria (JOIN + GROUP BY/HAVING) | categoria sem estadia concluída não aparece | IMPL (PR #29) |
| CT-U171 | Q02 chegadas em 7 dias (JOIN) | entrada em D+7 entra, em D+8 não; cancelada fora; hoje entra | IMPL |
| CT-U172 | Q03 ranking de gastos (RANK) | empate de R$ 800,00 no 5º lugar gera 6 linhas e a posição seguinte ao empate é a 7ª | IMPL |
| CT-U173 | Q04 quartos livres (NOT EXISTS) | reserva que termina em X ou começa em Y não bloqueia; quarto 103 em manutenção fora; 302 sempre livre | IMPL |
| CT-U174 | Q05 receita acumulada (SUM OVER) | acumulado é crescente e o último valor é a soma total; estadia que cruza a virada de mês | IMPL |
| CT-U175 | Q06 cancelamento acima de 20% (HAVING) | taxa exatamente 20% não entra; categoria com 0 cancelamentos não entra | IMPL |
| CT-U176 | Q07 participação por serviço (window sobre agregação) | percentuais somam 100%; serviço nunca consumido aparece com 0% | IMPL |
| CT-U177 | Q08 última estadia (ROW_NUMBER) | desempate pelo maior id; hóspede sem estadia concluída não aparece | IMPL |
| CT-U178 | Q09 divisão relacional (NOT EXISTS duplo) | quem usou todos menos um não entra; resultado vazio é válido | PARCIAL (falta `servico.categoria`) |
| CT-U179 | Q10 ROLLUP | total geral = soma dos subtotais; linhas rotuladas TOTAL | IMPL |
| CT-U180 | Rubrica: 2+ JOIN, 2+ window, 2+ agregação, 1+ anti-join | contagem por técnica | IMPL |
| CT-U181 | Cada consulta tem o objetivo em comentário `-- @Qnn` | leitura do arquivo | IMPL |

Modelo do cenário (repetido para cada consulta):
```gherkin
Scenario: Q03 devolve o ranking esperado
  Given os dados de exemplo originais
  When executo a consulta Q03
  Then o resultado tem 6 linhas
  And o hóspede de maior gasto está em 1º, com o valor calculado à mão no CT-M14
  And os dois hóspedes com gasto igual a R$ 800,00 dividem a mesma posição
```
Os valores exatos são calculados à mão no CT-M14. Atenção: o comentário "Totais gastos" no cabeçalho do `02_inserts.sql` cita nomes (Diego, Bruno, Elisa, Fábio...) que não existem na lista de hóspedes inserida, ou seja, está desatualizado e não deve ser usado como esperado.

**CT-U182 · Consultas dão o mesmo resultado em qualquer dia** · IMPL, ver CT-R04.

### 3.16 Índices (critério 5)

**CT-U190 · Existem exatamente 3 índices de aplicação** · IMPL
```gherkin
Scenario: Catálogo de índices
  When consulto pg_indexes no schema public, ignorando índices de PK e UK
  Then existem idx_reserva_hospede, idx_consumo_reserva e idx_reserva_status_entrada
```

**CT-U191 · Índice em cada FK usada em JOIN** · PARCIAL, `fk_reserva_quarto` (reserva.id_quarto), `fk_pagamento_reserva` e `fk_consumo_servico` não têm índice. O `04_indices.sql` justifica a escolha; o CT confere se a justificativa está no arquivo (CT-M15).

**CT-U192 · O índice composto respeita a ordem igualdade e depois faixa** · IMPL, `(status_reserva, data_entrada_prevista)`.

**CT-U193 · O script de índices roda duas vezes?** · PARCIAL
```gherkin
Scenario: Reexecutar 04_indices.sql
  When rodo 04_indices.sql duas vezes
  Then a segunda execução falha com "relation already exists" (o script não usa IF NOT EXISTS)
```
Registrar como comportamento aceito (a carga roda uma vez, no volume novo) ou usar `IF NOT EXISTS`.

**CT-U194 · O planejador usa o índice na massa de dados** · ver CT-I20.

---

## 4. Testes de integração (CT-I)

### 4.1 Fluxos de negócio ponta a ponta

**CT-I01 · Ciclo de vida: reserva, cancelamento e liberação do quarto** · IMPL
```gherkin
Scenario: Reserva cancelada libera o quarto para outro hóspede
  Given o quarto 302 está livre
  When reservo D+10 a D+13 para o hóspede 1
  And cancelo com p_hoje = D+3 (7 dias antes)
  And reservo o mesmo quarto e período para o hóspede 2
  Then a segunda reserva é aceita
  And cancelamento tem uma linha com multa 0,00
```

**CT-I02 · Ciclo de vida: reserva, check-in, consumo, check-out e pagamento** · PARCIAL (sem `fazer_checkin` e sem trigger de consumo)
```gherkin
Scenario: Estadia completa
  Given uma reserva CONFIRMADA de 3 noites com sinal de 30%
  When faço o check-in, lanço consumos e faço o check-out com o valor exato do saldo
  Then valor_final_pago = diárias com desconto + consumos + taxa
  And a soma dos pagamentos menos os estornos é igual ao valor final
  And o quarto ocupa LIMPEZA no fim (D-02, coberto em CT-U107)
```

**CT-I03 · Estadia com desconto e late check-out juntos** · IMPL, hóspede com 10 estadias, saída às 12:00:01 e consumo de R$ 100,00, valor final conferido à mão.

**CT-I04 · Reserva em NO-SHOW** · IMPL
```gherkin
Scenario: Hóspede não aparece
  Given uma reserva CONFIRMADA com entrada ontem e sem check-in
  When cancelar_reserva é chamada
  Then o status é NO-SHOW e a multa é de 100% da diária
  And o quarto pode ser reservado de novo no mesmo período
```

**CT-I05 · Concorrência: duas sessões reservam o mesmo quarto e período** · IMPL (critério "Teste com duas sessões")
```gherkin
Scenario: Corrida pelo mesmo quarto
  Given duas conexões A e B abertas em transações separadas
  When A insere a reserva e ainda não confirma
  And B tenta inserir reserva no mesmo quarto e período
  Then B fica esperando
  When A confirma
  Then B recebe HOTEL-005
  And existe uma única reserva ativa para o quarto e período
```

**CT-I06 · Concorrência: A cancela e B reserva** · IMPL, B só consegue reservar depois do COMMIT de A.

**CT-I07 · Concorrência: dois cancelamentos da mesma reserva** · IMPL
```gherkin
Scenario: Duas recepcionistas cancelam a mesma reserva
  When as sessões A e B chamam cancelar_reserva(12) ao mesmo tempo
  Then uma conclui e a outra recebe HOTEL-007
  And cancelamento tem exatamente uma linha
```

**CT-I08 · Concorrência: dois check-outs da mesma reserva** · IMPL, segundo recebe HOTEL-007 e `pagamento` não duplica a quitação.

**CT-I09 · Atomicidade: erro no meio desfaz tudo** · IMPL
```gherkin
Scenario: Falha após a primeira alteração
  Given uma transação aberta que chama fazer_checkout com valor insuficiente
  When o HOTEL-009 é lançado
  Then a reserva continua em CHECK-IN
  And nenhuma linha nova existe em pagamento
```

### 4.2 Carga do banco e Docker (critério transversal)

**CT-I10 · Banco sobe do zero com tudo carregado** · IMPL (PR #27)
```gherkin
Scenario: docker compose up --wait
  Given um volume novo (docker compose down -v antes)
  When executo docker compose up -d --wait
  Then o serviço postgres fica healthy
  And existem as tabelas, os dados, as procedures, o trigger e os 3 índices
  And a versão do servidor é PostgreSQL 17
```

**CT-I11 · A carga aborta no primeiro erro** · IMPL
```gherkin
Scenario: Script com erro de sintaxe
  Given um erro proposital em 02_inserts.sql
  When subo o banco do zero
  Then a inicialização falha (ON_ERROR_STOP=1 e set -e)
  And o contêiner não fica healthy (não pode haver erro silencioso)
```

**CT-I12 · Ordem estrita de carga** · IMPL, 01_ddl, 02_inserts, procedures e 04_indices; trocar a ordem faz a carga falhar.

**CT-I13 · Scripts de init rodam só na primeira subida** · IMPL
```gherkin
Scenario: Segunda subida sem apagar o volume
  Given o banco já foi inicializado
  When executo docker compose down e depois up -d --wait
  Then os dados persistem e os scripts não rodam de novo
```

**CT-I14 · Porta ocupada tem saída documentada** · IMPL, `PG_PORT=5433 docker compose up -d --wait` sobe e a aplicação continua conectando pela rede interna.

**CT-I15 · Serviços `app` e `testes` existem e dependem do banco saudável** · IMPL (PR #27)
```gherkin
Scenario: Dependência do serviço
  When executo docker compose run --rm app com o banco parado
  Then o compose sobe o postgres e espera o healthcheck antes de iniciar o app
```

**CT-I16 · O serviço `testes` executa a verificação automatizada** · LACUNA (PR #27)
```gherkin
Scenario: docker compose run --rm testes
  When executo o serviço testes
  Then ele roda os testes e termina com código 0 quando tudo passa
  And termina com código diferente de 0 quando algum falha
```
Hoje o serviço roda `pytest -q tests`, mas `tests/` só tem `.sql`: o pytest sai com código 5 ("no tests collected").

**CT-I17 · Os testes SQL existentes rodam pelo compose** · PARCIAL, `tests/test_procedures.sql` e `tests/test_trigger_sobreposicao.sql` precisam de um executor (pytest chamando `psql`, ou outro serviço) para entrar no `run --rm testes`.

### 4.3 Performance

**CT-I20 · O plano usa o índice depois da carga em massa** · IMPL (PR #29)
```gherkin
Scenario Outline: EXPLAIN antes e depois
  Given o schema perf_test com dezenas de milhares de linhas (performance/carga_massa.sql)
  When executo EXPLAIN (ANALYZE) da consulta <consulta> sem o índice <indice>
  And executo de novo com o índice criado
  Then o plano "antes" usa Seq Scan
  And o plano "depois" usa Index Scan, Index Only Scan ou Bitmap Index Scan em <indice>
  And o tempo "depois" é menor que o tempo "antes"
  Examples:
    | consulta                    | indice                    |
    | reservas de um hóspede      | idx_reserva_hospede       |
    | consumos de uma reserva     | idx_consumo_reserva       |
    | chegadas por status e data  | idx_reserva_status_entrada |
```

**CT-I21 · A medição não toca o schema de produção** · IMPL
```gherkin
Scenario: Isolamento do schema
  When executo performance/medir_antes_depois.sql
  Then só o schema perf_test é alterado
  And o schema public continua com as contagens originais de linhas
```

**CT-I22 · O `explain_antes_depois.txt` existe e vem de execução real** · PARCIAL, a pasta `performance/` tem os scripts, mas o arquivo de texto com os planos colados ainda não existe no repositório (ver CT-M15).

### 4.4 Aplicação e banco

**CT-I30 · A aplicação conecta, consulta, chama procedure e trata erro** · ver CT-A01 a CT-A15.

---

## 5. Testes da aplicação Python (CT-A) · PR #27

```gherkin
Feature: Aplicação Python integrada ao PostgreSQL 17 via psycopg
  Background:
    Given o banco está de pé e saudável
    And a variável PG_DSN aponta para o banco do laboratório
```

**CT-A01 · Conexão pela variável de ambiente** · IMPL
```gherkin
Scenario: PG_DSN definido e padrão
  When a aplicação inicia com PG_DSN válido
  Then a conexão é estabelecida
  And, sem PG_DSN, usa o DSN padrão do laboratório (localhost:5432)
```

**CT-A02 · Falha de conexão tem mensagem clara** · PARCIAL
```gherkin
Scenario: Banco indisponível
  Given o banco está parado
  When a aplicação inicia
  Then ela termina com mensagem de erro de conexão legível e código diferente de 0
```
Hoje a exceção sobe sem tratamento.

**CT-A03 · Consulta com bind, sem concatenação** · IMPL
```gherkin
Scenario: Parâmetro com tentativa de injeção
  When consultar_reservas recebe o status "CONFIRMADA' OR '1'='1"
  Then nenhuma reserva é devolvida e nenhuma tabela é alterada
  And o código-fonte não usa f-string nem "+" para montar o SQL (varredura estática)
```

**CT-A04 · Consulta devolve o esperado** · IMPL
```gherkin
Scenario: Status CONFIRMADA
  When consultar_reservas é chamada com CONFIRMADA
  Then devolve no máximo 5 linhas ordenadas por id_reserva
  And cada linha traz hóspede, quarto, status e valor bruto
```

**CT-A05 · Status sem reservas** · IMPL, imprime "Nenhuma reserva encontrada" e não falha.

**CT-A06 · Procedure no caminho feliz com `Decimal` e commit** · IMPL
```gherkin
Scenario: Check-out válido
  Given a reserva 10 está em CHECK-IN
  When a aplicação chama fazer_checkout com Decimal("1200.00") (ou o valor do saldo)
  Then a transação é confirmada com commit
  And a reserva 10 fica em CHECK-OUT
```

**CT-A07 · `float` no lugar de `Decimal` não é usado** · IMPL
```gherkin
Scenario: Varredura estática e dinâmica
  Then nenhum valor monetário passa como float para o CALL
  And um teste mostra que o CALL com float falha por não achar a procedure de parâmetro NUMERIC (armadilha do enunciado)
```

**CT-A08 · Erro de negócio é capturado e a transação é desfeita** · IMPL
```gherkin
Scenario: Check-out de reserva sem check-in
  Given a reserva 11 está CONFIRMADA
  When a aplicação chama fazer_checkout(11, Decimal("600.00"))
  Then RaiseException é capturada
  And a mensagem exibida é a mensagem de negócio (HOTEL-007)
  And conn.rollback() é chamado e a reserva 11 continua CONFIRMADA
```

**CT-A09 · Erro de pagamento insuficiente (HOTEL-009) pela aplicação** · PARCIAL
```gherkin
Scenario: Valor menor que o saldo
  When a aplicação chama fazer_checkout com valor R$ 0,01 para uma reserva em CHECK-IN
  Then ela mostra HOTEL-009 e faz rollback
```
O fluxo de demonstração do `regras.md` seção 11 pede esse caso (insuficiente e depois suficiente); a PR #27 cobre só HOTEL-007.

**CT-A10 · Conflito de datas (HOTEL-005) pela aplicação** · LACUNA, o fluxo de demonstração pede "tentar datas em conflito"; a aplicação não insere reserva.

**CT-A11 · Cancelamento pela aplicação com multa** · LACUNA, `cancelar_reserva` não é chamada pela aplicação.

**CT-A12 · SAVEPOINT por chamada** · PARCIAL
```gherkin
Scenario: Um erro não aborta as chamadas seguintes
  Given duas chamadas na mesma transação, a primeira com erro de negócio
  When a primeira falha
  Then o rollback para o SAVEPOINT desfaz só a primeira
  And a segunda chamada executa normalmente
```
No PostgreSQL um erro aborta a transação inteira; a aplicação resolve com `rollback()` total, e o `regras.md` seção 11 recomenda SAVEPOINT.

**CT-A13 · A demonstração é repetível** · LACUNA (bug da PR #27)
```gherkin
Scenario: Executar duas vezes seguidas sem recriar o banco
  When rodo docker compose run --rm app duas vezes
  Then a segunda execução tem o mesmo resultado da primeira
```
Hoje a primeira execução faz check-out real da reserva 10; na segunda, o "caminho feliz" cai em HOTEL-007. Corrigir com rollback ao final, com reserva própria da demo, ou documentando `down -v`.

**CT-A14 · Saída do app não mascara erro inesperado** · PARCIAL
```gherkin
Scenario: Exceção que não é de negócio
  When ocorre um erro inesperado (por exemplo, tabela inexistente)
  Then o código de saída do processo é diferente de 0
  And a mensagem final não afirma "Execução concluída com segurança"
```

**CT-A15 · Arquivos sem BOM** · LACUNA (bug da PR #27)
```gherkin
Scenario: Codificação dos arquivos novos
  When leio os primeiros bytes de python/main.py e python/requirements.txt
  Then não começam com EF BB BF
  And pip install -r python/requirements.txt lê a primeira linha sem erro
```

**CT-A16 · Roda pelo compose sem instalar Python na máquina** · IMPL
```gherkin
Scenario: Imagem da aplicação
  When executo docker compose run --rm app
  Then a imagem python:3.12-slim é construída e a aplicação roda
  And as credenciais vêm do docker-compose.yml, marcadas como de laboratório
```

---

## 6. Testes de regressão (CT-R)

Rodam **somente antes da entrega final** (decisão do grupo), não entre os merges; por isso o CT-M40 inclui a execução completa deste grupo. Cada um protege um defeito já visto no `docs/ia-log.md` ou uma regra com histórico de quebra.

**CT-R01 · Reexecutar toda a suíte SQL existente** · IMPL
```gherkin
Scenario: Suíte completa sobre banco novo
  When executo tests/test_procedures.sql e tests/test_trigger_sobreposicao.sql
  Then terminam sem ERROR com a mensagem final de sucesso
```

**CT-R02 · Mudança de assinatura não deixa sobrecarga ambígua** · IMPL (erro #4 do log de IA)
```gherkin
Scenario: Apenas uma versão de fazer_checkout
  When consulto pg_proc pelo nome fazer_checkout
  Then existe exatamente uma assinatura
  And CALL fazer_checkout(10, 5000) com 2 argumentos continua funcionando
```

**CT-R03 · Recarregar o arquivo de procedures é idempotente** · IMPL
```gherkin
Scenario: Rodar postgresql_procedures.sql duas vezes
  Then a segunda execução não falha
  And continua existindo um só trigger trg_reserva_sobreposicao em reserva
```

**CT-R04 · Resultado independente do dia** · IMPL
```gherkin
Scenario Outline: Mesmo resultado em outra data
  Given a data do sistema simulada em <data>
  When recarrego os dados e executo as 10 consultas
  Then o resultado é igual ao de hoje
  Examples:
    | data |
    | hoje |
    | hoje + 30 dias |
    | virada de mês |
    | 29/02 de ano bissexto |
```

**CT-R05 · Teste de mutação da sobreposição** · IMPL (recomendado no `regras.md` seção 9)
```gherkin
Scenario Outline: Quebrar o código de propósito
  Given uma cópia temporária da função do trigger com a alteração <mutacao>
  When executo a suíte do trigger
  Then pelo menos um teste falha
  Examples:
    | mutacao |
    | trocar "<" por "<=" na comparação de entrada |
    | trocar ">" por ">=" na comparação de saída   |
    | remover FOR UPDATE do quarto                 |
    | remover PENDENTE da lista de status ativos   |
```
Se nenhum teste falhar, falta dado de fronteira.

**CT-R06 · Teste de mutação das procedures** · IMPL
```gherkin
Scenario Outline: Mutar limites de multa e de late check-out
  Given uma alteração em <limite> (por exemplo, v_dias >= 7 para > 7, ou 12 horas para 13)
  When executo tests/test_procedures.sql
  Then pelo menos um teste falha
  Examples:
    | limite |
    | 7 dias, 2 dias, 0 dia |
    | 12:00:00 e 18:00:00 |
    | 5 e 10 estadias |
    | 5% e 10% |
```

**CT-R07 · Testes de horário não dependem da hora de execução** · IMPL
```gherkin
Scenario: Rodar a suíte às 00:05 e às 23:55
  When executo tests/test_procedures.sql nesses horários
  Then o resultado é o mesmo (os testes passam p_data_hora_saida e p_hoje explícitos)
```

**CT-R08 · Contagem dos dados de exemplo não muda** · IMPL
```gherkin
Scenario: Seed estável
  When consulto a contagem de cada tabela depois da carga
  Then as contagens de cada tabela são iguais às registradas na primeira execução validada (anotar aqui: hóspedes 8, quartos 7, categorias 3 e serviços 6 conferidos no script; reservas a conferir)
```

**CT-R09 · Fixtures dos testes não vazam** · IMPL
```gherkin
Scenario: Suíte desfeita no final
  When rodo a suíte e depois conto as linhas de cada tabela
  Then as contagens são iguais às de antes
```

**CT-R10 · Resultado das 10 consultas é guardado como baseline** · IMPL
```gherkin
Scenario: Comparação com o resultado esperado versionado
  When executo as consultas depois de qualquer mudança em DDL ou inserts
  Then a saída é igual ao arquivo de resultados esperados
  And a diferença aponta qual consulta mudou e por quê
```

**CT-R11 · Nome das constraints não muda** · IMPL, os testes dependem de nomes (ck_reserva_datas etc.); renomear sem atualizar os CTs falha.

**CT-R12 · Mudança de status do enunciado** · IMPL. Documentos alinhados ao DDL; o teste `test_ct_r12_documentos_usam_os_status_do_ddl` falha se um nome antigo voltar.
```gherkin
Scenario: Alinhamento entre documentação e banco
  When o conjunto de status do DDL muda
  Then regras.md, README, perguntas_de_negocio.md, inserts, procedures e testes são atualizados juntos
```
Hoje há duas nomenclaturas (ver seção 1.4); este CT impede que a divergência cresça.

**CT-R13 · Encoding dos scripts** · IMPL (ver CT-A15), nenhum `.sql`, `.py` ou `.txt` de dependências com BOM.

**CT-R14 · Quebra de linha e shebang do `postgres-init.sh`** · IMPL
```gherkin
Scenario: Script de init com CRLF
  Given o repositório clonado no Windows com CRLF
  When o contêiner executa /docker-entrypoint-initdb.d/00-init.sh
  Then o script roda (arquivo com LF, ou .gitattributes força LF)
```

---

## 7. Testes manuais (CT-M)

Cada CT-M tem um **responsável** e uma **evidência** (print, trecho de log ou link), anotados na execução.

### 7.1 Subida do ambiente e demonstração (apresentação, 10 minutos)

**CT-M01 · Cópia limpa do zip**
```gherkin
Scenario: Quem avalia só tem Docker
  Given o zip do repositório descompactado em outra pasta
  And docker compose down -v executado antes
  When executo docker compose up -d --wait
  And executo docker compose run --rm testes
  Then o banco sobe com esquema, dados, procedures e índices
  And a verificação passa
```

**CT-M02 · Roteiro da demonstração ao vivo** · ensaiado e cronometrado
```gherkin
Scenario: Os 10 minutos da apresentação
  Given banco já iniciado, comandos testados e portas livres
  Then o problema e o DER são apresentados em 2 minutos
  And docker compose up e testes em 2 minutos
  And uma regra de negócio ao vivo, no caminho feliz e no erro, também pela aplicação, em 3 minutos
  And o que o trigger registrou (auditoria) é mostrado
  And índice e plano antes e depois em 1 minuto
  And lições e IA em 2 minutos, com todos falando
```

**CT-M03 · Plano B da demonstração** · uma gravação do fluxo pronta caso o Docker falhe.

**CT-M04 · Contagem mínima da verificação automatizada** · conferir que há pelo menos 10 testes, incluindo constraints barrando dado inválido, procedure no caminho feliz e nos dois erros de negócio, um trigger e 2 consultas com resultado esperado.

### 7.2 Exploração do banco (teste exploratório)

**CT-M05 · Sessão exploratória de 30 minutos no psql**
```gherkin
Scenario: Tentar quebrar as regras sem roteiro
  Given o banco recém-carregado
  When tento INSERT, UPDATE e DELETE diretos em cada tabela com dados estranhos (nulos, negativos, datas extremas, textos longos)
  Then cada achado é registrado com o comando, o resultado e a regra afetada
```

**CT-M06 · Mensagens de erro legíveis para quem usa o sistema** · cada HOTEL-00x traz uma mensagem que um recepcionista entende e diz o que fazer.

**CT-M07 · Duas sessões `psql` lado a lado** · repetir CT-I05 à mão, com dois terminais, como será mostrado ao professor.

### 7.3 DER e modelo

**CT-M10 · DER cumpre a rubrica**
```gherkin
Scenario: Conferência do der/hotel.puml
  Then há 6 ou mais entidades, cada uma com atributos, PK, UK e FK
  And as cardinalidades (mín., máx.) estão em todas as relações, em Crow's Foot
  And há um N:M resolvido por entidade associativa (reserva x serviço, em consumo_servico)
  And há uma entidade com estado (reserva)
  And o arquivo .puml renderiza sem erro e a imagem está no README
```

**CT-M11 · DER é coerente com o DDL**
```gherkin
Scenario: Comparar diagrama e tabelas
  Then toda tabela do DDL aparece no DER com os mesmos atributos e chaves
  And as cardinalidades do README (seção 2.1) batem com as FKs e os NOT NULL
```
O `cancelamento` e o `pagamento` existem no DDL; conferir se estão no `.puml`.

**CT-M12 · Decisões de modelagem justificadas** · README responde "por que PK artificial", "por que cancelamento é entidade e não atributo", "por que uma reserva = um quarto".

**CT-M13 · Decisão sobre o descompasso `regras.md` x banco** · uma reunião curta decide, regra por regra, entre implementar ou cortar (seção 2 do `regras.md`), e registra no README. O resultado alimenta os status IMPL/PARCIAL/LACUNA deste roteiro.

### 7.4 Consultas e performance

**CT-M14 · Conferência humana das 10 consultas** · para cada Q01 a Q10: calcular à mão o resultado esperado a partir do `02_inserts.sql`, comparar com a saída e preencher a tabela "Resultados esperados" do `perguntas_de_negocio.md`. Valor copiado da saída do banco não vale.

**CT-M15 · Evidência de performance**
```gherkin
Scenario: explain_antes_depois.txt
  Then o arquivo existe em performance/
  And os planos estão colados como texto, de uma execução do grupo
  And os tempos medidos (Execution Time) aparecem antes e depois
  And a tabela antes/depois do README bate com o arquivo
  And nenhum número foi inventado (o grupo reexecuta uma medição na frente do avaliador)
```

### 7.5 Documentação (critério 7)

**CT-M20 · README com os 7 blocos** · domínio, DER, decisões de design, como rodar, performance, dificuldades e Uso de IA, todos presentes.

**CT-M21 · "Como rodar" funciona seguindo só o texto** · uma pessoa fora do grupo executa os comandos do README, na ordem, sem ajuda.

**CT-M22 · Comentários nas rotinas** · cada procedure e trigger tem comentário dizendo qual regra implementa e qual tabela altera.

**CT-M23 · Estrutura de diretórios coerente**
```gherkin
Scenario: Árvore do repositório
  Then a estrutura bate com a da Aula 32 e com a seção 4.1 do README
  And não há sobras como a pasta testes/ (com conftest.py de 1 linha) ao lado de tests/
  And não há arquivos Java ou Oracle (AGENTS.md proíbe)
```

**CT-M24 · LGPD e segredos**
```gherkin
Scenario: Dados e credenciais
  Then os hóspedes, CPFs, e-mails e telefones são fictícios (CPFs de exemplo, domínios genéricos)
  And não há senha real, chave de API nem arquivo .env no repositório nem no histórico Git
  And as senhas do compose estão marcadas como de laboratório
```

**CT-M25 · Referências cruzadas dos documentos** · IMPL. Links e caminhos citados existem. `AGENTS.md`, `README.md`, `regras.md` e `perguntas_de_negocio.md` agora apontam para `regras.md` e `perguntas_de_negocio.md` na raiz; o teste `test_ct_m25_caminhos_citados_existem` confere cada caminho `docs/...` e cada link `.md`.

**CT-M26 · Seção "Como testar" da PR e do README sem trechos cortados.**

### 7.6 Uso de IA (critério 7, 2 pontos) e governança

Esta é a particularidade do projeto: o uso de IA é liberado, mas precisa ser **documentado** (onde foi usada, como, se errou e como foi corrigido).

**CT-M30 · Tabela de registros completa**
```gherkin
Scenario: Seção 7 do README e docs/ia-log.md
  Then há 5 ou mais registros
  And cobrem 4 ou mais tipos de artefato diferentes (DER, DDL, consultas, procedure/trigger, índices/EXPLAIN, aplicação, README)
  And cada linha tem artefato, pedido, erro ou omissão da IA e o que o grupo fez
```

**CT-M31 · Erros reais documentados**
```gherkin
Scenario: Pelo menos 2 linhas com erro real
  Then a coluna "o que o agente errou" descreve um erro verificável (ver os 6 registros atuais em docs/ia-log.md)
  And cada erro tem a correção correspondente e o commit ou arquivo onde ela aparece
```

**CT-M32 · Todo SQL gerado por IA foi executado no banco** · para cada registro, existe evidência de execução (saída do `psql` ou do teste).

**CT-M33 · Registro das três PRs e dos CTs** · o uso de IA nestes casos de teste também entra no log: ferramenta e modelo, o pedido, o que a IA errou e a correção. Inclui os logs individuais (PR #30, `docs/Log-IA-Joao`) consolidados no `docs/ia-log.md` e na seção 7 do README, como pede o AGENTS.md.

**CT-M34 · Ferramenta, modelo e skills declarados**, com versão, e coerentes entre README, `docs/ia-log.md` e `opencode.json`.

**CT-M35 · Reflexão do grupo** · onde a IA mais ajudou, onde mais errou, o que faria diferente.

**CT-M36 · AGENTS.md e opencode.json coerentes com o repositório**
```gherkin
Scenario: Governança
  Then o AGENTS.md declara PostgreSQL 17 e Python e é igual ao que o repositório entrega
  And o opencode.json nega git push e pede confirmação para comandos
  And nenhuma interação da IA executou git push
```

### 7.7 Entrega

**CT-M40 · Checklist da A3 e execução dos CT-R** · rodar todo o grupo CT-R (seção 6) e percorrer o "Checklist Completo da A3" do enunciado, item a item, com responsável e evidência.

**CT-M41 · Histórico Git** · commits ao longo das semanas, de todos os integrantes, em Conventional Commits; `.gitignore` correto; tag da entrega apontando para o commit que está no zip.

**CT-M42 · Defesa oral**
```gherkin
Scenario: O professor escolhe um trecho
  Given um artefato qualquer (constraint, consulta, procedure, plano)
  When o professor pede uma explicação
  Then qualquer integrante explica o que o trecho faz, por que foi feito assim e o que a IA errou nele
```
Ensaiar em rodízio: cada pessoa explica um trecho que não escreveu.

**CT-M43 · Pacote de entrega** · capa em PDF de 1 página (nome, integrantes com RA, link, tag, hash), zip com `.git` sem `.venv` nem dados do banco, e link do GitHub.

---

## 8. Resumo quantitativo

| Tipo | Quantidade de CTs | Observação |
|---|---|---|
| CT-U (unitário) | 109 CTs em títulos próprios, mais as tabelas das consultas (CT-U170 a CT-U182) e das transições (CT-U90 a CT-U96) | Várias linhas de `Examples` por CT; a numeração salta de propósito entre os grupos |
| CT-I (integração) | 21 | Inclui concorrência, Docker e performance |
| CT-A (aplicação) | 16 | PR #27 |
| CT-R (regressão) | 14 | Inclui mutação |
| CT-M (manual) | 31 | Documentação, IA, entrega e apresentação |

### 8.1 Lacunas encontradas na análise (para decidir antes da entrega)

| # | Lacuna ou divergência | CTs que falham hoje |
|---|---|---|
| 1 | Limite de 30 noites (RN-01) sem constraint | CT-U03 |
| 2 | Capacidade de hóspedes (RN-03) sem coluna nem validação | CT-U40 a CT-U43 |
| 3 | Quarto em manutenção pode ser reservado (RN-06); o status de quarto já existe, mas falta `registrar_reserva`/`fazer_checkin` para aplicá-lo | CT-U80 a CT-U84 |
| 4 | Máquina de estados (RN-07) sem trigger; qualquer UPDATE de status passa | CT-U94 a CT-U96 |
| 5 | Sinal de 30% (RN-10) e estorno no cancelamento (tabela 4.1) não são lançados | CT-U61, CT-U62, CT-U120 a CT-U122 |
| 6 | Consumo sem trigger (RN-11); `valor_total_item` digitado à mão | CT-U131 a CT-U133 |
| 7 | Check-in (RN-12) sem procedure | CT-U140 a CT-U143 |
| 8 | Auditoria de status sem tabela nem trigger | CT-U160, CT-U161 |
| 9 | `ck_reserva_desconto` aceita 0 a 100, e o `regras.md` fala em 0, 5 ou 10 | CT-U05 |
| 10 | `ON DELETE CASCADE` em cancelamento e consumo, contra "todas as FKs bloqueiam" do `regras.md` | CT-U24 |
| 11 | Serviço `testes` do compose roda `pytest` sem testes pytest | CT-I16, CT-I17 |
| 12 | App Python: demo não repetível, BOM em dois arquivos, sem HOTEL-009 nem HOTEL-005 | CT-A09, CT-A10, CT-A13, CT-A15 |
| 13 | `explain_antes_depois.txt` ainda não existe | CT-I22, CT-M15 |
| 14 | ~~Duas nomenclaturas de status (CHECK-IN/CHECK-OUT x EM_ANDAMENTO/FINALIZADA)~~ **Corrigido** | CT-R12 |
| 15 | ~~Caminhos citados nos documentos não existem (`docs/regras.md`, `docs/perguntas_de_negocio.md`)~~ **Corrigido** | CT-M25 |
| 16 | `Q09` pede `servico.categoria`, que não existe no DDL | CT-U178 |

### 8.2 Próximos passos sugeridos

1. Decidir, regra por regra, entre implementar e cortar as lacunas 1 a 8 (CT-M13).
2. Implementar o executor de testes do serviço `testes` (lacuna 11), automatizando primeiro os CTs IMPL.
3. Registrar este trabalho no `docs/ia-log.md` e na seção 7 do README (CT-M33), com os erros que a IA cometer na escrita dos testes.

---

## 9. Implementação dos CT-U (status)

Os CT-U com status IMPL e PARCIAL (parte implementada) estão codificados em `tests/unit/` (pytest + psycopg; `PG_DSN` define a conexão). Cada teste roda numa transação desfeita no final. O nome de cada função leva o código do CT (`test_ct_u50_...`).

| Arquivo | CTs |
|---|---|
| `test_ct_u_constraints.py` | CT-U01, U02, U04 a U23, U25 a U28 |
| `test_ct_u_trigger_sobreposicao.py` | CT-U30 a U37 |
| `test_ct_u_cancelar_reserva.py` | CT-U50 a U60 |
| `test_ct_u_fazer_checkout.py` | CT-U70 a U76, U100 a U106, U110 a U115 |
| `test_ct_u_contrato_procedures.py` | CT-U150, U152 a U155 e dois CTs novos: **CT-U156** (pagamentos menos estornos = valor final ou multa, nos dados de exemplo) e **CT-U157** (valor final do exemplo = bruto + consumos) |
| `test_ct_u_consultas.py` | CT-U170 a U179, U180, U181 |
| `test_ct_u_indices.py` | CT-U190, U192 |

Resultado atual: todos passam, sem `xfail` (confirmar com `docker compose run --rm testes`; BUG-01 e BUG-02, descritos em `relatorio-problemas.md`, foram corrigidos e os dois testes deixaram de ser `xfail`). Fora desta etapa ficam: os CT-U com status LACUNA, o CT-U03 (31 noites; a constraint do máximo não existe), o CT-U24 (decisão sobre `ON DELETE`), o CT-U29 (manual), o CT-U151 e o CT-U191/U193/U194 (dependem de decisão ou de massa de dados) e os grupos CT-I, CT-A, CT-R e CT-M.
