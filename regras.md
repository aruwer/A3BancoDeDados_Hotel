# Regras de negócio: Hotel Host 

Junta o documento de regras do grupo com os rascunhos do colega (`README.md` e `perguntas_de_negocio.md`). A numeração RN-01 a RN-06 segue o README do colega, para que README e perguntas continuem válidos. As regras novas começam em RN-07. A seção 13 mostra o que veio de cada lado e o que foi decidido; pode ser apagada antes da entrega.

O Hotel Host é um hotel fictício de pequeno porte. Todos os dados de exemplo são fictícios (nada de CPF, e-mail ou telefone reais, por causa da LGPD).

## 1. O problema

A recepção controla reservas, hóspedes e cobranças em planilha e papel. Isso gera quatro falhas: duas reservas para o mesmo quarto nas mesmas datas (overbooking), reservas com mais hóspedes do que o quarto comporta, cancelamentos cobrados de forma diferente conforme quem atende, e late check-out e desconto de fidelidade dados no improviso.

**Pergunta central:** como garantir que um quarto nunca tenha duas reservas sobrepostas, que a multa de cancelamento e a taxa de late check-out sigam a regra, e que isso valha também para quem insere direto no banco, com o mesmo resultado no PostgreSQL e no Oracle?

## 2. Como ler este documento

- **Núcleo**: regras que o grupo implementa de qualquer forma. Sozinhas cobrem o que a rubrica pede (2 procedures, 1 trigger, constraints, consultas com fronteira).
- **Extra**: regras que enriquecem o projeto. Se o tempo apertar (escopo de cerca de 26 horas), cortem as extras: um modelo pequeno, completo e testado vale mais que um grande pela metade.
- Toda regra tem número-limite, fronteiras para testar, onde vira código e código de erro.
- Todo valor de fronteira vira linha em `02_inserts.sql` e teste automatizado.

## 3. Vocabulário e estados

| Conceito | Definição |
|---|---|
| Noite | Da data de entrada até a data de saída, sem contar o dia da saída. Entrada dia 10 e saída dia 13 são 3 noites. |
| Intervalo da reserva | Semiaberto: [entrada, saída). Quem sai no dia 13 libera o quarto para quem entra no dia 13. |
| Diária (D) | Valor da noite, copiado do tipo de quarto no momento da reserva. Mudar a tarifa depois não altera reservas existentes. |
| Estadia concluída | Reserva com status FINALIZADA. |
| Status da reserva | CONFIRMADA, EM_ANDAMENTO, FINALIZADA, CANCELADA, NO_SHOW |
| Status do quarto | DISPONIVEL, OCUPADO, LIMPEZA, MANUTENCAO |
| Tipo de pagamento | PAGAMENTO ou ESTORNO (valor sempre positivo; o tipo indica o sentido) |

Máquina de estados da reserva (única sequência permitida):

- CONFIRMADA → EM_ANDAMENTO (check-in)
- EM_ANDAMENTO → FINALIZADA (check-out)
- CONFIRMADA → CANCELADA (cancelamento antes da entrada)
- CONFIRMADA → NO_SHOW (hóspede não apareceu; ver RN-04)
- FINALIZADA, CANCELADA e NO_SHOW são estados finais.

Ciclo do quarto: DISPONIVEL → OCUPADO (check-in) → LIMPEZA (check-out) → DISPONIVEL (governança, por UPDATE). MANUTENCAO é definido e removido por UPDATE direto.

## 4. As regras

| ID | Prior. | Regra (com números) | Fronteiras para testar | Onde vira código | Erro |
|---|---|---|---|---|---|
| RN-01 | Núcleo | Estadia de 1 a 30 noites; a saída é sempre depois da entrada. | 0 noite (recusa), 1 (aceita), 30 (aceita), 31 (recusa) | CHECK na RESERVA e conferência na procedure `registrar_reserva` | HOTEL-002 |
| RN-02 | Núcleo | Um quarto não pode ter duas reservas ativas (CONFIRMADA ou EM_ANDAMENTO) com períodos sobrepostos, usando [entrada, saída). Sair e entrar no mesmo dia é permitido. | saída = entrada da outra (aceita); sobreposição de 1 noite (recusa); reserva CANCELADA ou NO_SHOW não bloqueia | Procedure `registrar_reserva` com trava no quarto (FOR UPDATE). Destaque opcional: trigger `trg_reserva_sobreposicao` (ver seção 9.1) | HOTEL-005 |
| RN-03 | Núcleo | O número de hóspedes vai de 1 até a capacidade do tipo do quarto. | igual à capacidade (aceita), capacidade + 1 (recusa), 0 (recusa) | Trigger `trg_reserva_validacao` (vale para INSERT direto) e procedure | HOTEL-003 |
| RN-04 | Núcleo | Cancelamento só para reserva CONFIRMADA. Multa por faixa de dias até a entrada (tabela 4.1): 7 dias ou mais, sem multa; de 2 a 6 dias, 50% da primeira diária; menos de 2 dias, 100% da primeira diária. Se a entrada já passou sem check-in, a reserva vira NO_SHOW com multa de 100% da primeira diária. | 7, 6, 2, 1 e 0 dias; entrada ontem (NO_SHOW); reserva já CANCELADA (recusa) | Procedure `cancelar_reserva` (altera RESERVA e PAGAMENTO) | HOTEL-006, HOTEL-007 |
| RN-05 | Extra | Desconto de fidelidade sobre as diárias, conforme as estadias concluídas anteriores do hóspede: 0 a 4, sem desconto; 5 a 9, 5%; 10 ou mais, 10%. Aplicado no check-out. | hóspedes com exatamente 4, 5, 9 e 10 estadias concluídas | Procedure `fazer_checkout` | — |
| RN-06 | Núcleo | Quarto em MANUTENCAO não pode ser reservado. O check-in só ocorre em quarto DISPONIVEL: quarto em MANUTENCAO, LIMPEZA ou OCUPADO não recebe check-in. | reserva em quarto DISPONIVEL (aceita) e MANUTENCAO (recusa); check-in em LIMPEZA, MANUTENCAO e OCUPADO (recusa); quarto inexistente (recusa) | Procedures `registrar_reserva` e `fazer_checkin`; CHECK no status do quarto | HOTEL-004 |
| RN-07 | Núcleo | A reserva só muda de status pela sequência da seção 3. | cada transição válida e pelo menos duas inválidas (FINALIZADA → CONFIRMADA, CANCELADA → EM_ANDAMENTO) | Trigger `trg_reserva_validacao`, BEFORE UPDATE (vale para UPDATE direto) | HOTEL-007 |
| RN-08 | Núcleo | No check-out, o horário padrão é 12:00 do dia da saída. Até 12:00:00 não há taxa; depois de 12:00 e até 18:00:00, taxa de 50% da diária; depois de 18:00:00, 1 diária inteira. Saída antes do dia previsto não gera estorno. Saída depois do dia previsto é recusada (a reserva precisa ser prorrogada). | 12:00:00, 12:00:01, 18:00:00, 18:00:01, saída antecipada, dia posterior | Procedure `fazer_checkout` (altera RESERVA, QUARTO e PAGAMENTO) | HOTEL-012 |
| RN-09 | Núcleo | O check-out só finaliza se o pagamento cobrir o saldo (seção 4.3). | valor igual ao saldo (aceita), 1 centavo a menos (recusa) | Procedure `fazer_checkout` | HOTEL-009 |
| RN-10 | Extra | A reserva exige sinal de pelo menos 30% do valor das diárias (noites × D, sem desconto). O sinal é registrado como pagamento. | exatamente 30% (aceita), 30% menos 1 centavo (recusa) | Procedure `registrar_reserva` (altera RESERVA e PAGAMENTO) | HOTEL-013 |
| RN-11 | Extra | Só se lança consumo em reserva EM_ANDAMENTO. A quantidade é maior que zero e o preço unitário é copiado do serviço no lançamento. | consumo em CONFIRMADA ou FINALIZADA (recusa), quantidade 0 (recusa) | Trigger `trg_consumo_validacao` e CHECK | HOTEL-010 |
| RN-12 | Extra | O check-in ocorre a partir da data de entrada e antes da data de saída. | dia da entrada (aceita), véspera (recusa), dia da saída (recusa) | Procedure `fazer_checkin` (altera RESERVA e QUARTO) | HOTEL-008 |

### 4.1 Multa de cancelamento (RN-04)

Base: D = diária da reserva. Dias até a entrada = data de entrada − hoje. Estorno do sinal = maior valor entre (sinal pago − multa) e 0.

| Dias até a entrada | Multa | Status final | Exemplo (3 noites, D = 200,00, sinal = 180,00) |
|---|---|---|---|
| 7 ou mais | 0 | CANCELADA | multa 0,00; estorno 180,00 |
| de 2 a 6 | 50% de D | CANCELADA | multa 100,00; estorno 80,00 |
| 0 ou 1 | 100% de D | CANCELADA | multa 200,00; estorno 0,00 (180 − 200 fica negativo, vira 0) |
| negativo (entrada já passou) | 100% de D | NO_SHOW | multa 200,00; estorno 0,00 |

A multa fica gravada na reserva. A parte que o sinal não cobre é registrada como valor devido; a cobrança em si está fora do escopo.

### 4.2 Late check-out (RN-08)

| Horário de saída no dia previsto | Taxa |
|---|---|
| até 12:00:00 | 0 |
| de 12:00:01 até 18:00:00 | 50% de D |
| a partir de 18:00:01 | 100% de D |

A taxa usa a diária cheia da reserva (sem desconto de fidelidade).

### 4.3 Valor final e saldo (RN-05 e RN-09)

- Desconto % = 0, 5 ou 10, conforme a RN-05. Conta só estadias FINALIZADAS anteriores; a reserva em checkout ainda não conta.
- Valor final = noites × D × (1 − desconto%) + soma dos consumos (quantidade × preço unitário) + taxa de late check-out.
- Saldo = valor final − (pagamentos − estornos já registrados).
- A procedure recebe o valor entregue pelo hóspede, exige que seja maior ou igual ao saldo e registra um PAGAMENTO do valor do saldo (troco é assunto do caixa).
- Arredondar a 2 casas (`ROUND(x, 2)`) nos dois bancos.

## 5. Mapa de implementação

### 5.1 Procedures (nenhuma faz COMMIT; quem chama decide a transação)

| Procedure | Prior. | Regras | Tabelas que altera | Parâmetros |
|---|---|---|---|---|
| registrar_reserva | Núcleo | RN-01, 02, 03, 06, 10 | RESERVA, PAGAMENTO | hóspede, quarto, entrada, saída, nº de hóspedes, sinal, forma de pagamento |
| cancelar_reserva | Núcleo | RN-04 | RESERVA, PAGAMENTO | reserva, hoje (opcional) |
| fazer_checkin | Extra | RN-06, 12 | RESERVA, QUARTO | reserva, hoje (opcional) |
| fazer_checkout | Núcleo | RN-05, 08, 09 | RESERVA, QUARTO, PAGAMENTO | reserva, data e hora da saída, valor pago, forma de pagamento |

A rubrica pede 2 procedures. Sugestão: entregar `registrar_reserva` e `fazer_checkout` como as duas principais, mais `cancelar_reserva` (a tabela de multa rende boa demonstração). `fazer_checkin` só se sobrar tempo: sem ele, o check-in é feito por UPDATE direto, que o trigger da RN-07 continua validando.

Dica de teste: `cancelar_reserva`, `fazer_checkin` e `fazer_checkout` aceitam a data de referência como parâmetro (nulo significa agora). Assim os testes cobrem as fronteiras (7, 6, 2, 1 dias; 12:00:00 e 12:00:01) sem esperar o calendário.

### 5.2 Triggers

| Trigger | Prior. | Evento | Regras |
|---|---|---|---|
| trg_reserva_validacao | Núcleo | BEFORE INSERT OR UPDATE na RESERVA | RN-03 (capacidade) e RN-07 (transições) |
| trg_reserva_auditoria | Núcleo | AFTER INSERT OR UPDATE OF status na RESERVA | grava status antes e depois, usuário do banco e data e hora em AUDITORIA_RESERVA |
| trg_reserva_sobreposicao | Destaque | BEFORE INSERT OR UPDATE na RESERVA (Oracle: trigger composto) | RN-02 para quem insere direto (seção 9.1) |
| trg_consumo_validacao | Extra | BEFORE INSERT na CONSUMO_RESERVA | RN-11 |

A rubrica pede 1 trigger. Ter validação e auditoria permite mostrar o que o trigger registrou na apresentação.

### 5.3 Constraints no DDL (todas nomeadas)

- `ck_reserva_estadia`: saída maior que entrada e no máximo 30 noites (RN-01).
- `ck_reserva_status`, `ck_quarto_status`, `ck_pagamento_tipo`, `ck_servico_categoria`: valores permitidos.
- `ck_reserva_hospedes`: número de hóspedes maior que zero.
- `ck_consumo_qtd`: quantidade maior que zero.
- `ck_reserva_desconto`: percentual de desconto em 0, 5 ou 10.
- `uk_hospede_documento`, `uk_quarto_numero`, `uk_tipo_quarto_nome`, `uk_servico_nome`.
- `ON DELETE`: todas as FKs bloqueiam (RESTRICT no PostgreSQL; no Oracle, omitir a cláusula). Reserva com histórico não pode sumir porque alguém apagou o hóspede ou o quarto.

## 6. Códigos de erro (iguais nos dois bancos)

No PostgreSQL: `RAISE EXCEPTION 'HOTEL-00x: mensagem' USING ERRCODE = 'P0001'`. No Oracle: `RAISE_APPLICATION_ERROR(-200xx, 'HOTEL-0xx: mensagem')`. A aplicação identifica o erro de negócio pelo prefixo HOTEL- na mensagem, igual nos dois.

| Código | Significado | Oracle |
|---|---|---|
| HOTEL-001 | Parâmetro inválido (nulo, negativo, hóspede inexistente) | -20001 |
| HOTEL-002 | Estadia fora de 1 a 30 noites ou datas invertidas | -20002 |
| HOTEL-003 | Número de hóspedes acima da capacidade ou menor que 1 | -20003 |
| HOTEL-004 | Quarto inexistente, em manutenção ou sem estar DISPONIVEL no check-in | -20004 |
| HOTEL-005 | Conflito de datas com outra reserva do quarto | -20005 |
| HOTEL-006 | Reserva não encontrada | -20006 |
| HOTEL-007 | Transição de status inválida | -20007 |
| HOTEL-008 | Check-in fora da janela de datas | -20008 |
| HOTEL-009 | Pagamento insuficiente no check-out | -20009 |
| HOTEL-010 | Consumo em reserva que não está EM_ANDAMENTO | -20010 |
| HOTEL-012 | Check-out depois do dia previsto de saída | -20012 |
| HOTEL-013 | Sinal abaixo de 30% das diárias | -20013 |

O número 011 fica livre de propósito, para uma regra que surgir.

## 7. Entidades (insumo para o DER)

Oito entidades, um N:M resolvido por entidade associativa (CONSUMO_RESERVA) e uma entidade com estado (RESERVA).

| Entidade | Atributos principais | Observação |
|---|---|---|
| HOSPEDE | hospede_id (PK), nome, documento (UK), email, telefone | dados fictícios |
| TIPO_QUARTO | tipo_id (PK), nome (UK), capacidade, valor_diaria | tarifa e capacidade pertencem ao tipo, não ao quarto |
| QUARTO | quarto_id (PK), numero (UK), andar, tipo_id (FK), status | status operacional (DISPONIVEL, OCUPADO, LIMPEZA, MANUTENCAO) |
| RESERVA | reserva_id (PK), hospede_id (FK), quarto_id (FK), data_entrada, data_saida, num_hospedes, status, valor_diaria, percentual_desconto, multa_cancelamento, taxa_checkout, valor_final, data_hora_checkout, data_criacao | entidade com estado; valor_diaria é cópia da tarifa na hora da reserva; os campos de checkout ficam nulos ou zerados até ele acontecer |
| SERVICO | servico_id (PK), nome (UK), categoria, preco_unitario | `categoria` (por exemplo ALIMENTACAO ou EXTRA) é necessária para a pergunta Q09 |
| CONSUMO_RESERVA | consumo_id (PK), reserva_id (FK), servico_id (FK), quantidade, preco_unitario, data_hora | associativa do N:M entre RESERVA e SERVICO, com atributos próprios |
| PAGAMENTO | pagamento_id (PK), reserva_id (FK), tipo, forma, valor, data_hora | sinal, quitação e estorno |
| AUDITORIA_RESERVA | aud_id (PK), reserva_id, status_antes, status_depois, usuario_banco, data_hora | alimentada só por trigger; sem FK, para sobreviver a qualquer remoção |

Cardinalidades para conferir no DER: HOSPEDE (1,1) — (0,N) RESERVA; QUARTO (1,1) — (0,N) RESERVA; TIPO_QUARTO (1,1) — (0,N) QUARTO; RESERVA (1,1) — (0,N) CONSUMO_RESERVA; SERVICO (1,1) — (0,N) CONSUMO_RESERVA; RESERVA (1,1) — (0,N) PAGAMENTO.

Decisão de modelagem a justificar no README: **uma reserva = um quarto.** Reserva de vários quartos exigiria outra entidade associativa; fica como evolução, fora do escopo.

## 8. Dados de fronteira para o 02_inserts.sql

Todas as datas relativas a hoje (`CURRENT_DATE` no PostgreSQL, `TRUNC(SYSDATE)` no Oracle). O checklist completo por consulta está em `docs/perguntas_de_negocio.md`; abaixo, o que vem das regras.

- Tipos de quarto: um de capacidade 2 (D = 200,00), um de capacidade 4 (350,00) e um de capacidade 3 (500,00).
- Quartos nos quatro status: DISPONIVEL, OCUPADO, LIMPEZA e MANUTENCAO.
- Reservas em quartos vizinhos com saída de uma no mesmo dia da entrada da outra (back-to-back).
- Reserva com saída hoje e reserva com entrada hoje.
- Reservas CONFIRMADAS com entrada em hoje+7, hoje+6, hoje+2, hoje+1 e hoje (as faixas do cancelamento), mais uma CONFIRMADA com entrada ontem (NO_SHOW).
- Reserva de exatamente 30 noites e uma de 1 noite.
- Reserva com sinal exatamente igual a 30% das diárias.
- Hóspedes com exatamente 4, 5, 9 e 10 estadias FINALIZADAS (fronteiras da fidelidade).
- Reserva CANCELADA e reserva NO_SHOW nas mesmas datas de uma reserva ativa no mesmo quarto (prova que não bloqueiam).
- Consumos em reserva EM_ANDAMENTO.

## 9. Concorrência

Defeito clássico: duas recepcionistas reservam o mesmo quarto, nas mesmas datas, ao mesmo tempo. Sem trava, as duas veem o quarto livre e as duas inserem.

Solução: `registrar_reserva` trava a linha do quarto (`SELECT ... FOR UPDATE` em QUARTO) antes de procurar sobreposição. A segunda sessão espera a primeira terminar e, ao acordar, enxerga a reserva nova e responde HOTEL-005. O teste usa duas conexões: a sessão A reserva e ainda não grava; a sessão B tenta o mesmo quarto e as mesmas datas; só uma pode ser atendida.

Teste de mutação recomendado: apagar o FOR UPDATE ou trocar a comparação de datas (`<` por `<=`) e conferir que algum teste falha. Se nada falhar, falta dado de fronteira.

### 9.1 Sobreposição em trigger (destaque, com cuidado no Oracle)

O rascunho do colega previa o trigger `trg_reserva_sobreposicao`. A ideia é boa (protege quem faz INSERT direto), mas tem uma armadilha:

- **PostgreSQL:** funciona com um trigger comum BEFORE INSERT OR UPDATE. Primeiro trava a linha do quarto (`SELECT ... FOR UPDATE`), depois procura reserva ativa sobreposta, ignorando a própria linha.
- **Oracle:** um trigger de linha que consulta a própria tabela RESERVA dá **ORA-04091 (tabela mutante)**. A saída correta é um **trigger composto** (`COMPOUND TRIGGER`): a seção BEFORE EACH ROW trava o quarto e guarda os dados da linha numa coleção; a seção AFTER STATEMENT confere as sobreposições. Evitem `PRAGMA AUTONOMOUS_TRANSACTION`, que esconde o problema e quebra a atomicidade.
- Alternativa só do PostgreSQL: constraint de exclusão com `btree_gist` e `daterange`. É elegante, mas o Oracle não tem equivalente e as regras deixariam de ser simétricas.

Sem o trigger, a RN-02 continua garantida pela procedure, mas não para INSERT direto. Decidam na D-01 (seção 12).

## 10. Armadilhas PostgreSQL × Oracle neste domínio

| Ponto | PostgreSQL | Oracle |
|---|---|---|
| Consulta à própria tabela dentro de trigger de linha | permitido | ORA-04091 (tabela mutante); usar trigger composto |
| Hoje | CURRENT_DATE | TRUNC(SYSDATE) (SYSDATE traz hora) |
| 12:00 e 18:00 do dia da saída | data_saida + INTERVAL '12 hours' | data_saida + 12/24 (literal TIME dá ORA-01861, erro que o exemplo de referência já teve) |
| Diferença entre datas (noites) | date − date devolve inteiro | date − date devolve número (dias); use TRUNC nos dois lados |
| Maior valor entre dois | GREATEST | GREATEST |
| Série de meses (Q05) | generate_series | CONNECT BY LEVEL |
| ON DELETE RESTRICT | existe | não existe: omitir a cláusula (ORA-00905 se escrever) |
| Erro dentro da transação | aborta a transação inteira (SAVEPOINT na aplicação) | desfaz só o comando que falhou |
| Comentário depois do `;` na mesma linha | ok | ORA-00933 no sqlplus: comentário na linha de cima |
| Valores monetários | NUMERIC(10,2) | NUMBER(10,2) |

## 11. O que isso muda para as aplicações Java e Python

- **Fluxo de demonstração (igual nas duas linguagens e nos dois bancos):** buscar quartos livres para um período (bind e NOT EXISTS); registrar reserva; tentar acima da capacidade (HOTEL-003); tentar datas em conflito (HOTEL-005); cancelar uma reserva; fazer check-out com valor insuficiente (HOTEL-009) e depois suficiente. Por padrão, tudo é desfeito no final (rollback); uma opção como `--efetivar` grava.
- **Bind sempre**, nunca concatenar valores no SQL.
- **Dinheiro:** `Decimal` no Python (float faz o CALL não achar a procedure de parâmetro NUMERIC no PostgreSQL) e `BigDecimal` no Java.
- **Datas:** `date` e `datetime` no Python; `java.sql.Date` e `Timestamp` no Java. O horário do check-out chega como parâmetro, o que facilita testar 12:00 e 18:00.
- **Transação:** a aplicação decide commit e rollback. No PostgreSQL, um SAVEPOINT antes de cada chamada, para o erro de negócio desfazer só a chamada.
- **Erro de negócio:** identificar pelo prefixo HOTEL- na mensagem (`RaiseException` no psycopg; códigos -20000 a -20999 no oracledb; `SQLException` com a mensagem no JDBC).
- **Sem parâmetro OUT nas procedures.** OUT e INOUT se comportam de modo diferente em psycopg, python-oracledb e JDBC. A aplicação recupera a reserva recém-criada por consulta com bind (hóspede e quarto, maior `reserva_id`) dentro da mesma transação.
- **A identidade não volta no rollback:** testes e aplicações nunca assumem um id fixo para a próxima reserva.
- **Conexão:** usuário e senha de laboratório vindos de variável de ambiente, definidos no `docker-compose.yml`, que avisa que são de laboratório.

## 12. Decisões em aberto para o grupo

| # | Decisão | Proposta |
|---|---|---|
| D-01 | Sobreposição também em trigger (`trg_reserva_sobreposicao`)? | Entregar primeiro a procedure com FOR UPDATE. O trigger entra depois, como destaque, só se sobrar tempo (Oracle exige trigger composto). |
| D-02 | Check-out deixa o quarto em LIMPEZA (proposto) ou direto em DISPONIVEL? | LIMPEZA, que dá uso ao status do rascunho do colega; a volta a DISPONIVEL é um UPDATE. |
| D-03 | Manter o sinal de 30% (RN-10)? | Manter como Extra; é fácil de cortar. Sem ele, o estorno do cancelamento é sempre 0 e a regra de estorno perde graça. |
| D-04 | Uma reserva = um quarto? | Sim. |
| D-05 | Procedures sem parâmetro OUT? | Sim, com a recuperação do id por consulta. |
| D-06 | Desconto de fidelidade aplicado no check-out (rascunho do colega) ou na reserva? | No check-out, porque a base de cálculo (estadias concluídas) fica mais clara e o sinal usa a diária cheia. |
| D-07 | Q05 mostra meses sem receita (exige gerador de meses, diferente nos dois bancos) ou só meses com receita? | Só meses com receita, a menos que o grupo queira o desafio de dialeto. |
| D-08 | Os valores (30%, 7 e 2 dias, 12:00 e 18:00, 30 noites, 5% e 10%) ficam assim? | Qualquer troca é simples, desde que cada número apareça nos dados de fronteira e nos testes. |
| D-09 | Quem fica com cada procedure e cada trigger? | Cada integrante precisa saber explicar qualquer trecho na defesa. |

## 13. Reconciliação: o que veio de cada lado

### 13.1 Em comum (mantido)

- As mesmas 8 entidades e o N:M resolvido pela entidade associativa de consumo.
- Estadia de 1 a 30 noites e intervalo [entrada, saída), com sair e entrar no mesmo dia permitido.
- Capacidade do quarto, cancelamento com faixas de 7 e 2 dias, fidelidade em 5 e 10 estadias, status de quarto em manutenção.
- Procedures sem COMMIT, ON DELETE explícito, datas relativas a hoje, índices em arquivo separado, dupla defesa (procedure e trigger).

### 13.2 Conflitos e como foram resolvidos

| Ponto | Rascunho do colega | Doc do grupo | Resolvido |
|---|---|---|---|
| Multa de cancelamento | 2 a 6 dias: 50% da primeira diária; menos de 2 dias ou no-show: 100% | 2 a 6 dias: 1 diária; 0 a 1 dia: 50% do total | Valores do colega, mais simples (só dependem de D) |
| No-show | citado na multa e na Q10, sem regra | não existia | Novo status NO_SHOW, gerado por `cancelar_reserva` quando a entrada já passou |
| Desconto de fidelidade | 5% (5 a 9) e 10% (10 ou mais), no check-out | 10% e 15%, na reserva | Valores e momento do colega |
| Status do quarto | MANUTENCAO e LIMPEZA | DISPONIVEL, OCUPADO, MANUTENCAO | União dos quatro, com ciclo definido |
| Sobreposição em trigger | `trg_reserva_sobreposicao` | só na procedure | Procedure no núcleo; trigger como destaque, com o aviso do ORA-04091 |
| Nome do check-in | `fazer_checkin` | `registrar_checkin` | `fazer_checkin` |
| Entidade de consumo | CONSUMO_RESERVA, `preco_unitario` | CONSUMO, `valor_unitario` | Nomes do colega |
| Erro de digitação no README | RN-06 citava `fazer_checkout` para check-in | — | Corrigido para `fazer_checkin` |

### 13.3 Só em um dos lados e mantido

- Do colega: as 10 perguntas de negócio com dados de fronteira, os índices sugeridos, a divisão relacional (Q09) e o ROLLUP (Q10).
- Do grupo: máquina de estados, check-out com horário e taxa, quitação, sinal de 30%, códigos de erro HOTEL-xxx, trigger de capacidade, análise de concorrência, armadilhas PG × Oracle e orientações para Java e Python.

### 13.4 Ajustes que as perguntas do colega exigiram no modelo

- `SERVICO.categoria`: a Q09 fala em serviços da categoria Extras, que não existia.
- Status NO_SHOW: a Q10 agrupa por concluída, cancelada e no-show.
- Colunas de checkout em RESERVA (`valor_final`, `taxa_checkout`, `percentual_desconto`): necessárias para Q01, Q03 e Q05 sem recalcular tudo.
