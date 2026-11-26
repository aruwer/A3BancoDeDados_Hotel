# Regras de negócio: Hotel Host

Documento de referência das regras do Hotel Host. A numeração RN-01 a RN-12 é a mesma usada no `README.md` e em `perguntas_de_negocio.md`. Os detalhes de cada regra (fronteiras, código de erro e onde vira código) estão nas seções a seguir. Este documento descreve o que está **implementado** em `postgresql/01_ddl.sql` e `procedures/postgresql_procedures.sql`; o que foi cortado está marcado como tal.

O Hotel Host é um hotel fictício de pequeno porte. Todos os dados de exemplo são fictícios (nada de CPF, e-mail ou telefone reais, por causa da LGPD).

## 1. O problema

A recepção controla reservas, hóspedes e cobranças em planilha e papel. Isso gera quatro falhas: duas reservas para o mesmo quarto nas mesmas datas (overbooking), reservas com mais hóspedes do que o quarto comporta, cancelamentos cobrados de forma diferente conforme quem atende, e late check-out e desconto de fidelidade dados no improviso.

**Pergunta central:** como garantir que um quarto nunca tenha duas reservas sobrepostas, que a multa de cancelamento e a taxa de late check-out sigam a regra, e que isso valha também para quem insere direto no banco?

## 2. Como ler este documento

- **Núcleo**: regras que são implementadas de qualquer forma. Sozinhas cobrem o que a rubrica pede (2 procedures, 1 trigger, constraints, consultas com fronteira).
- **Extra**: regras que enriquecem o projeto. Foram cortadas por falta de tempo (escopo de cerca de 26 horas): um modelo pequeno, completo e testado vale mais que um grande pela metade.
- Toda regra tem número-limite, fronteiras para testar, onde vira código e código de erro.
- Todo valor de fronteira vira linha em `02_inserts.sql` ou teste automatizado (`tests/unit/`).
- **Estado atual (PostgreSQL 17):** as regras de núcleo RN-01 a RN-09 estão implementadas e testadas. RN-03, RN-06 (reserva em manutenção) e RN-07 estão no trigger `trg_reserva_validacao`, sem passar por procedure. As procedures `registrar_reserva` e `fazer_checkin`, as regras RN-10, RN-11 e RN-12 e a auditoria de status foram **cortadas** (Extra). Onde as seções abaixo citam essas procedures, leia como escopo cortado.

## 3. Vocabulário e estados

| Conceito | Definição |
|---|---|
| Noite | Da data de entrada até a data de saída, sem contar o dia da saída. Entrada dia 10 e saída dia 13 são 3 noites. |
| Intervalo da reserva | Semiaberto: [entrada, saída). Quem sai no dia 13 libera o quarto para quem entra no dia 13. |
| Diária (D) | Valor da noite: `valor_total_bruto` da reserva dividido pelas noites, copiado da categoria no momento da reserva. Mudar a tarifa depois não altera reservas existentes. |
| Estadia concluída | Reserva com status CHECK-OUT. |
| Status da reserva | PENDENTE, CONFIRMADA, CHECK-IN, CHECK-OUT, CANCELADA, NO-SHOW (os mesmos valores de `RESERVA.status_reserva`, CHECK `ck_reserva_status`). PENDENTE é o status inicial (DEFAULT): reserva criada e ainda não confirmada |
| Status do quarto | DISPONIVEL, OCUPADO, LIMPEZA, MANUTENCAO |
| Tipo de pagamento | PAGAMENTO ou ESTORNO (valor sempre positivo; o tipo indica o sentido) |

Máquina de estados da reserva (única sequência permitida):

- PENDENTE → CONFIRMADA (confirmação da reserva)
- PENDENTE → CANCELADA / NO-SHOW (mesmas regras do cancelamento, RN-04)
- CONFIRMADA → CHECK-IN (check-in)
- CHECK-IN → CHECK-OUT (check-out)
- CONFIRMADA → CANCELADA (cancelamento antes da entrada)
- CONFIRMADA → NO-SHOW (hóspede não apareceu; ver RN-04)
- CHECK-OUT, CANCELADA e NO-SHOW são estados finais.

Ciclo do quarto: DISPONIVEL → OCUPADO (check-in, por UPDATE direto) → LIMPEZA (check-out) → DISPONIVEL (governança, por UPDATE). MANUTENCAO é definido e removido por UPDATE direto.

## 4. As regras

| ID | Prior. | Regra (com números) | Fronteiras para testar | Onde vira código | Erro |
|---|---|---|---|---|---|
| RN-01 | Núcleo | Estadia de 1 a 30 noites; a saída é sempre depois da entrada. | 0 noite (recusa), 1 (aceita), 30 (aceita), 31 (recusa) | CHECK `ck_reserva_datas` e `ck_reserva_max_noites` na RESERVA (vale para qualquer INSERT) | violação de CHECK (SQLSTATE 23514) |
| RN-02 | Núcleo | Um quarto não pode ter duas reservas ativas (PENDENTE, CONFIRMADA ou CHECK-IN) com períodos sobrepostos, usando [entrada, saída). Sair e entrar no mesmo dia é permitido. | saída = entrada da outra (aceita); sobreposição de 1 noite (recusa); reserva CANCELADA ou NO-SHOW não bloqueia | Trigger `trg_reserva_sobreposicao`, que trava a linha do quarto (`FOR UPDATE`) antes de procurar conflito (seção 9) | HOTEL-005 |
| RN-03 | Núcleo | O número de hóspedes vai de 1 até a capacidade da categoria do quarto. | igual à capacidade (aceita), capacidade + 1 (recusa), 0 (recusa) | CHECK `ck_reserva_hospedes` (maior que zero) e trigger `trg_reserva_validacao` (limite da categoria; vale para INSERT e UPDATE direto) | HOTEL-003 |
| RN-04 | Núcleo | Cancelamento só para reserva PENDENTE ou CONFIRMADA. Multa por faixa de dias até a entrada (tabela 4.1): 7 dias ou mais, sem multa; de 2 a 6 dias, 50% da primeira diária; menos de 2 dias, 100% da primeira diária. Se a entrada já passou sem check-in, a reserva vira NO-SHOW com multa de 100% da primeira diária. | 7, 6, 2, 1 e 0 dias; entrada ontem (NO-SHOW); reserva já CANCELADA (recusa) | Procedure `cancelar_reserva` (altera RESERVA, CANCELAMENTO e PAGAMENTO) | HOTEL-006, HOTEL-007 |
| RN-05 | Extra | Desconto de fidelidade sobre as diárias, conforme as estadias concluídas anteriores do hóspede: 0 a 4, sem desconto; 5 a 9, 5%; 10 ou mais, 10%. Aplicado no check-out. | hóspedes com exatamente 4, 5, 9 e 10 estadias concluídas | Procedure `fazer_checkout`; CHECK `ck_reserva_desconto` (só 0, 5 ou 10) | — |
| RN-06 | Núcleo | Quarto em MANUTENCAO não pode ser reservado. | reserva em quarto DISPONIVEL (aceita) e MANUTENCAO (recusa); quarto inexistente (recusa pela FK) | Trigger `trg_reserva_validacao`; CHECK `ck_quarto_status`. A parte "check-in só em quarto DISPONIVEL" dependia de `fazer_checkin` e foi **cortada** | HOTEL-004 |
| RN-07 | Núcleo | A reserva só muda de status pela sequência da seção 3. | cada transição válida e pelo menos duas inválidas (CHECK-OUT → CONFIRMADA, CANCELADA → CHECK-IN) | Trigger `trg_reserva_validacao`, BEFORE INSERT OR UPDATE (vale para UPDATE direto) | HOTEL-007 |
| RN-08 | Núcleo | No check-out, o horário padrão é 12:00 do dia da saída. Até 12:00:00 não há taxa; depois de 12:00 e até 18:00:00, taxa de 50% da diária; depois de 18:00:00, 1 diária inteira. Saída antes do dia previsto não gera estorno. Saída depois do dia previsto é recusada (a reserva precisa ser prorrogada). | 12:00:00, 12:00:01, 18:00:00, 18:00:01, saída antecipada, dia posterior | Procedure `fazer_checkout` (altera RESERVA, QUARTO e PAGAMENTO) | HOTEL-012 |
| RN-09 | Núcleo | O check-out só finaliza se o pagamento cobrir o saldo (seção 4.3). | valor igual ao saldo (aceita), 1 centavo a menos (recusa) | Procedure `fazer_checkout` | HOTEL-009 |
| RN-10 | Extra, **cortada** | A reserva exigiria sinal de pelo menos 30% do valor das diárias. O sinal é registrado por INSERT direto em PAGAMENTO. | — | — (dependia de `registrar_reserva`) | (HOTEL-013 reservado) |
| RN-11 | Extra, **cortada** | Só se lançaria consumo em reserva CHECK-IN. Hoje só há o CHECK `ck_consumo_quantidade` (quantidade maior que zero). | — | — (dependia de `trg_consumo_validacao`) | (HOTEL-010 reservado) |
| RN-12 | Extra, **cortada** | O check-in ocorreria a partir da data de entrada e antes da saída. O check-in é feito por UPDATE direto, e o trigger da RN-07 valida a transição. | — | — (dependia de `fazer_checkin`) | (HOTEL-008 reservado) |

### 4.1 Multa de cancelamento (RN-04)

Base: D = diária da reserva. Dias até a entrada = data de entrada − hoje. Estorno do sinal = maior valor entre (sinal pago − multa) e 0.

| Dias até a entrada | Multa | Status final | Exemplo (3 noites, D = 200,00, sinal = 180,00) |
|---|---|---|---|
| 7 ou mais | 0 | CANCELADA | multa 0,00; estorno 180,00 |
| de 2 a 6 | 50% de D | CANCELADA | multa 100,00; estorno 80,00 |
| 0 ou 1 | 100% de D | CANCELADA | multa 200,00; estorno 0,00 (180 − 200 fica negativo, vira 0) |
| negativo (entrada já passou) | 100% de D | NO-SHOW | multa 200,00; estorno 0,00 |

A multa fica gravada em `CANCELAMENTO.taxa_multa_aplicada`. O estorno é lançado em `PAGAMENTO` (tipo ESTORNO) pela própria `cancelar_reserva`. A parte que o sinal não cobre é registrada em `CANCELAMENTO.valor_devido`; a cobrança em si está fora do escopo.

### 4.2 Late check-out (RN-08)

| Horário de saída no dia previsto | Taxa |
|---|---|
| até 12:00:00 | 0 |
| de 12:00:01 até 18:00:00 | 50% de D |
| a partir de 18:00:01 | 100% de D |

A taxa usa a diária cheia da reserva (sem desconto de fidelidade) e fica gravada em `RESERVA.taxa_checkout`.

### 4.3 Valor final e saldo (RN-05 e RN-09)

- Desconto % = 0, 5 ou 10, conforme a RN-05. Conta só estadias CHECK-OUT anteriores; a reserva em checkout ainda não conta.
- Valor final = noites × D × (1 − desconto%) + soma dos consumos (`CONSUMO_SERVICO.valor_total_item`) + taxa de late check-out. Fica gravado em `RESERVA.valor_final_pago`.
- Saldo = valor final − (pagamentos − estornos já registrados).
- A procedure recebe o valor entregue pelo hóspede, exige que seja maior ou igual ao saldo e registra um PAGAMENTO do valor do saldo (troco é assunto do caixa).
- Arredondar a 2 casas (`ROUND(x, 2)`).

## 5. Mapa de implementação

### 5.1 Procedures (nenhuma faz COMMIT; quem chama decide a transação)

| Procedure | Regras | Tabelas que altera | Parâmetros |
|---|---|---|---|
| `cancelar_reserva` | RN-04 | RESERVA, CANCELAMENTO, PAGAMENTO | `p_id_reserva`, `p_hoje` (opcional), `p_motivo` (opcional) |
| `fazer_checkout` | RN-05, 08, 09 | RESERVA, QUARTO, PAGAMENTO | `p_id_reserva`, `p_valor_pago`, `p_data_hora_saida` (opcional), `p_forma_pagamento` (padrão PIX) |

Cortadas: `registrar_reserva` (RN-01, 02, 03, 06, 10) e `fazer_checkin` (RN-06, 12). Sem elas, a reserva e o check-in são feitos por INSERT e UPDATE direto, e os triggers continuam validando.

Dica de teste: `cancelar_reserva` e `fazer_checkout` aceitam a data de referência como parâmetro (nulo significa agora). Assim os testes cobrem as fronteiras (7, 6, 2, 1 dias; 12:00:00 e 12:00:01) sem esperar o calendário.

### 5.2 Triggers

| Trigger | Evento | Regras |
|---|---|---|
| `trg_reserva_sobreposicao` | BEFORE INSERT OR UPDATE na RESERVA | RN-02 para quem insere direto (seção 9) |
| `trg_reserva_validacao` | BEFORE INSERT OR UPDATE na RESERVA | RN-03 (capacidade), RN-06 (manutenção) e RN-07 (transições) |

Os dois são BEFORE e rodam em ordem alfabética: se as datas conflitam, `trg_reserva_sobreposicao` responde HOTEL-005 antes da validação. Cortados: `trg_reserva_auditoria` (auditoria de status) e `trg_consumo_validacao` (RN-11).

### 5.3 Constraints no DDL (todas nomeadas)

- `ck_reserva_datas` e `ck_reserva_max_noites`: saída maior que entrada e no máximo 30 noites (RN-01).
- `ck_reserva_status`, `ck_quarto_status`, `ck_pagamento_tipo`, `ck_pagamento_forma`: valores permitidos.
- `ck_reserva_hospedes`: número de hóspedes maior que zero (RN-03).
- `ck_reserva_desconto`: percentual de desconto em 0, 5 ou 10 (RN-05).
- `ck_reserva_checkout`, `ck_reserva_valor_bruto`, `ck_reserva_taxa_checkout`, `ck_cancelamento_taxa`, `ck_cancelamento_devido`, `ck_pagamento_valor`, `ck_servico_valor`, `ck_categoria_valor`, `ck_categoria_capacidade`, `ck_consumo_quantidade`: valores numéricos e datas coerentes.
- `uk_hospede_cpf`, `uk_hospede_email`, `uk_quarto_numero`, `uk_cancelamento_reserva`: unicidade.
- `ON DELETE RESTRICT` em todas as FKs: reserva com histórico não pode sumir porque alguém apagou o hóspede, o quarto ou a própria reserva.

## 6. Códigos de erro

`RAISE EXCEPTION 'HOTEL-00x: mensagem' USING ERRCODE = 'P0001'`. A aplicação identifica o erro de negócio pelo prefixo HOTEL- na mensagem.

| Código | Significado | Usado em |
|---|---|---|
| HOTEL-001 | Parâmetro inválido (nulo, negativo, forma de pagamento inválida, saída antes do check-in) | `cancelar_reserva`, `fazer_checkout` |
| HOTEL-003 | Número de hóspedes acima da capacidade ou menor que 1 | `trg_reserva_validacao` |
| HOTEL-004 | Quarto em manutenção | `trg_reserva_validacao` |
| HOTEL-005 | Conflito de datas com outra reserva do quarto | `trg_reserva_sobreposicao` |
| HOTEL-006 | Reserva não encontrada | `cancelar_reserva`, `fazer_checkout` |
| HOTEL-007 | Transição de status inválida (inclui cancelar reserva que não está PENDENTE ou CONFIRMADA e fazer check-out de reserva que não está em CHECK-IN) | procedures e `trg_reserva_validacao` |
| HOTEL-009 | Pagamento insuficiente no check-out | `fazer_checkout` |
| HOTEL-012 | Check-out depois do dia previsto de saída | `fazer_checkout` |

Reservados e não usados: HOTEL-002 (a RN-01 é barrada por CHECK, não por procedure), HOTEL-008 (RN-12, cortada), HOTEL-010 (RN-11, cortada) e HOTEL-013 (RN-10, cortada). O número 011 fica livre de propósito.

## 7. Entidades (insumo para o DER)

Oito entidades, um N:M resolvido por entidade associativa (`CONSUMO_SERVICO`) e uma entidade com estado (`RESERVA`). O DER está em `der/hotel.puml` e o esquema completo, em `postgresql/01_ddl.sql`.

| Entidade | Atributos principais | Observação |
|---|---|---|
| HOSPEDE | id_hospede (PK), cpf (UK), nome_completo, email (UK), telefone, data_cadastro | dados fictícios |
| CATEGORIA_QUARTO | id_categoria (PK), nome_categoria, capacidade_maxima, valor_diaria_base | tarifa e capacidade pertencem à categoria, não ao quarto |
| QUARTO | id_quarto (PK), id_categoria (FK), numero_quarto (UK), andar, status_quarto | status operacional (DISPONIVEL, OCUPADO, LIMPEZA, MANUTENCAO) |
| RESERVA | id_reserva (PK), id_hospede (FK), id_quarto (FK), numero_hospedes, data_reserva, data_entrada_prevista, data_saida_prevista, data_checkin_real, data_checkout_real, status_reserva, valor_total_bruto, percentual_desconto, valor_final_pago, taxa_checkout | entidade com estado; `valor_total_bruto` é a cópia da tarifa na hora da reserva; os campos de check-out ficam nulos ou zerados até ele acontecer |
| CANCELAMENTO | id_cancelamento (PK), id_reserva (FK, UK), data_cancelamento, taxa_multa_aplicada, valor_devido, motivo_cancelamento | existe só para reserva cancelada (0..1 por reserva) |
| SERVICO | id_servico (PK), nome_servico, valor_unitario | catálogo; não tem `categoria` (ver 13.2) |
| CONSUMO_SERVICO | id_consumo (PK), id_reserva (FK), id_servico (FK), quantidade, data_consumo, valor_total_item | associativa do N:M entre RESERVA e SERVICO, com atributos próprios |
| PAGAMENTO | id_pagamento (PK), id_reserva (FK), tipo, forma, valor, data_hora | sinal, quitação e estorno |

Cardinalidades (mín., máx.): HOSPEDE (1,1) — (0,N) RESERVA; QUARTO (1,1) — (0,N) RESERVA; CATEGORIA_QUARTO (1,1) — (0,N) QUARTO; RESERVA (1,1) — (0,1) CANCELAMENTO; RESERVA (1,1) — (0,N) CONSUMO_SERVICO; SERVICO (1,1) — (0,N) CONSUMO_SERVICO; RESERVA (1,1) — (0,N) PAGAMENTO.

Decisão de modelagem: **uma reserva = um quarto.** Reserva de vários quartos exigiria outra entidade associativa; fica como evolução, fora do escopo.

## 8. Dados de fronteira para o 02_inserts.sql

Todas as datas relativas a hoje (`CURRENT_DATE`). O checklist completo por consulta está em `perguntas_de_negocio.md`; o cabeçalho do `02_inserts.sql` lista as fronteiras F1 a F8 que a carga cobre.

- Categorias: Standard (capacidade 2, D = 200,00), Superior (3, 300,00) e Suíte (4, 500,00).
- Quartos nos quatro status: DISPONIVEL, OCUPADO, LIMPEZA e MANUTENCAO.
- Reservas CONFIRMADAS com entrada em hoje+7 e hoje+8 (borda da janela da Q02), e CANCELADAS com entrada em hoje+7, hoje+6, hoje+2 e hoje+1 (as faixas do cancelamento), mais uma NO-SHOW (entrada que já passou).
- Empate no ranking (Q03), categoria com exatamente 20% de cancelamento (Q06), serviço nunca consumido e empate de receita (Q07), hóspede que usou todos os serviços menos um (Q09) e mês sem receita (Q05).
- Reserva CANCELADA dentro do período da Q04 (prova que não bloqueia o quarto).
- Consumos em reserva CHECK-IN e CHECK-OUT.
- As fronteiras que dependem de muitos hóspedes (fidelidade com 4, 5, 9 e 10 estadias, 30 e 31 noites, 12:00:00 e 12:00:01) são montadas dentro dos testes e desfeitas com ROLLBACK, para não inflar a carga.

## 9. Concorrência

Defeito clássico: duas recepcionistas reservam o mesmo quarto, nas mesmas datas, ao mesmo tempo. Sem trava, as duas veem o quarto livre e as duas inserem.

Solução: `trg_reserva_sobreposicao` trava a linha do quarto (`SELECT ... FOR UPDATE` em QUARTO) antes de procurar sobreposição. A segunda sessão espera a primeira terminar e, ao acordar, enxerga a reserva nova e responde HOTEL-005. `cancelar_reserva` e `fazer_checkout` travam a linha da reserva (`FOR UPDATE`): a segunda sessão espera e recebe HOTEL-007, sem gravar duas multas nem duas quitações.

Os testes `tests/unit/test_ct_u_concorrencia.py` usam duas conexões reais: a sessão A opera e ainda não grava; a sessão B tenta a mesma coisa; só uma pode ser atendida. Teste de mutação feito: ao tirar os `FOR UPDATE`, 5 dos 6 testes falham (o sexto, de quartos diferentes, deve continuar passando).

### 9.1 Sobreposição em trigger

O trigger protege quem faz INSERT direto na tabela: primeiro trava a linha do quarto, depois procura reserva ativa sobreposta, ignorando a própria linha.

Alternativa não adotada: constraint de exclusão com `btree_gist` e `daterange` na RESERVA. É elegante, mas exigiria a extensão e trataria só a sobreposição; o trigger também aplica a regra do status (CANCELADA e NO-SHOW não bloqueiam) e devolve o erro de negócio `HOTEL-005`. Por não existir essa constraint, a RESERVA **não ganha o índice GiST** que ela criaria sozinha, e a FK `reserva.id_quarto` precisa de índice próprio se for usada em JOIN com volume (ver `postgresql/04_indices.sql`).

## 10. Armadilhas do PostgreSQL neste domínio

| Ponto | O que fazer |
|---|---|
| Hoje | `CURRENT_DATE`; nos testes e nos dados de exemplo, sempre relativo a hoje |
| 12:00 e 18:00 do dia da saída | `data_saida + INTERVAL '12 hours'` |
| Diferença entre datas (noites) | `date − date` devolve inteiro |
| Erro dentro da transação | Aborta a transação inteira: a aplicação usa `SAVEPOINT` (ou `rollback`) para o erro de negócio desfazer só a chamada |
| Mudar a assinatura de uma procedure | `CREATE OR REPLACE` cria uma sobrecarga em vez de substituir; o arquivo faz `DROP PROCEDURE IF EXISTS` antes |
| Mensagem do servidor depende do idioma | Os testes comparam o SQLSTATE (`23514`, `23503`, `P0001`), nunca o texto |
| Valores monetários | `NUMERIC(10,2)`; na aplicação, `Decimal` (com `float`, o `CALL` não acha a procedure) |
| CRLF em `.sh` | O `.gitattributes` força LF em `.sh`, `.sql` e `.py`; sem isso o contêiner sai com código 127 |

## 11. O que isso muda para a aplicação Python

- **Fluxo de demonstração (`python/main.py`):** consultar reservas por status (SELECT com bind); fazer o check-out de uma reserva de demonstração no caminho feliz (`CALL fazer_checkout` com `Decimal`); tentar o check-out de uma reserva que não está em CHECK-IN e tratar o erro de negócio (HOTEL-007). Tudo roda em transação isolada e é desfeito no final (`ROLLBACK`), com as datas relativas a hoje, para a demonstração se repetir.
- **Bind sempre**, nunca concatenar valores no SQL.
- **Dinheiro:** `Decimal` (float faz o CALL não achar a procedure de parâmetro NUMERIC).
- **Datas:** `date` e `datetime`. O horário do check-out chega como parâmetro, o que facilita testar 12:00 e 18:00.
- **Transação:** a aplicação decide commit e rollback.
- **Erro de negócio:** identificar pelo prefixo HOTEL- na mensagem (`RaiseException` no psycopg).
- **Sem parâmetro OUT nas procedures.** A aplicação recupera a reserva recém-criada por consulta com bind.
- **A identidade não volta no rollback:** testes e aplicações nunca assumem um id fixo para a próxima reserva (a demonstração restaura a sequence com `setval`).
- **Conexão:** usuário e senha de laboratório vindos de `PG_DSN`, definida no `docker-compose.yml`, que avisa que são de laboratório.

## 12. Decisões de projeto

| # | Decisão | Resultado |
|---|---|---|
| D-01 | Sobreposição em trigger (`trg_reserva_sobreposicao`)? | **Adotado**: o trigger com `FOR UPDATE` é a garantia da RN-02 (a procedure `registrar_reserva` foi cortada). |
| D-02 | Check-out deixa o quarto em LIMPEZA ou direto em DISPONIVEL? | **LIMPEZA**, sem sobrescrever MANUTENCAO; a volta a DISPONIVEL é um UPDATE. Implementado em `fazer_checkout`. |
| D-03 | Manter o sinal de 30% (RN-10)? | **Cortado.** O sinal é registrado por INSERT direto em PAGAMENTO; `cancelar_reserva` estorna o que o sinal cobriu além da multa. |
| D-04 | Uma reserva = um quarto? | Sim. |
| D-05 | Procedures sem parâmetro OUT? | Sim, com a recuperação do id por consulta. |
| D-06 | Desconto de fidelidade aplicado no check-out ou na reserva? | No check-out, porque a base de cálculo (estadias concluídas) fica mais clara. |
| D-07 | Q05 mostra meses sem receita ou só meses com receita? | Só meses com receita. |
| D-08 | Os valores (7 e 2 dias, 12:00 e 18:00, 30 noites, 5% e 10%) ficam assim? | Mantidos; cada número aparece nos dados de fronteira e nos testes. |
| D-09 | Booleano `status_manutencao` ou `status_quarto`? | **`status_quarto`** (`ck_quarto_status`), que cobre o ciclo completo do quarto. |

## 13. Resumo das decisões de modelagem

### 13.1 Decisões que fecham pontos em aberto

| Ponto | Decisão |
|---|---|
| Multa de cancelamento | 2 a 6 dias: 50% da primeira diária; menos de 2 dias ou no-show: 100% da primeira diária (só depende de D, a antecedência em dias) |
| No-show | Status NO-SHOW, gerado por `cancelar_reserva` quando a data de entrada já passou sem check-in |
| Desconto de fidelidade | 5% (5 a 9 estadias concluídas) e 10% (10 ou mais), aplicado no check-out |
| Status do quarto | DISPONIVEL, OCUPADO, LIMPEZA e MANUTENCAO, com ciclo definido |
| Sobreposição | Trigger com `FOR UPDATE` no quarto |
| Entidade de consumo | `CONSUMO_SERVICO`, com `valor_total_item` gravado no lançamento |
| Cancelamento | Entidade própria `CANCELAMENTO` (0..1 por reserva), com multa e valor devido |

### 13.2 Ajustes no modelo exigidos pelas consultas

- `SERVICO.categoria`: a Q09 fala em serviços da categoria Extras. **Não foi criada**; a Q09 considera todos os serviços cadastrados (limitação documentada na própria consulta).
- Status NO-SHOW: a Q10 agrupa por concluída, cancelada e no-show.
- Colunas de checkout em RESERVA (`valor_final_pago`, `taxa_checkout`, `percentual_desconto`): necessárias para Q01, Q03 e Q05 sem recalcular tudo.
  - **Implementado no DDL:** `RESERVA.valor_final_pago`, `RESERVA.taxa_checkout` (`NOT NULL DEFAULT 0`, `ck_reserva_taxa_checkout`) e `RESERVA.percentual_desconto`, todas gravadas por `fazer_checkout`.
  - **Implementado no DDL:** `QUARTO.status_quarto` (`ck_quarto_status`: DISPONIVEL, OCUPADO, LIMPEZA, MANUTENCAO), no lugar do booleano `status_manutencao`. A decisão D-02 está em vigor: `fazer_checkout` leva o quarto a LIMPEZA (e não sobrescreve MANUTENCAO).
