# Log de Uso de IA — Hotel Host

Registre aqui as interações relevantes, erros reais dos agentes e correções feitas pelo grupo.

**Ferramenta e modelo:** Claude (claude.ai), modelo Claude Sonnet 5.5. Nenhuma skill do repositório foi usada.
**Banco usado nos testes:** PostgreSQL 17.12 instalado localmente (Windows), com os scripts executados pelo `psql`.
**Branch:** `feat/procedures-e-trigger`.

## Registros

| # | Artefato | Pedido (resumo) | O que o agente errou ou omitiu | O que o grupo fez |
|---|----------|-----------------|--------------------------------|-------------------|
| 1 | `procedures/postgresql_procedures.sql` (trigger `trg_reserva_sobreposicao`) | Trigger que barre overbooking em INSERT/UPDATE direto na tabela `reserva` | O `regras.md` e o README descrevem um modelo diferente do `01_ddl.sql` (nomes de tabelas, status, `AUDITORIA_RESERVA`). O agente identificou a divergência ao ler o repositório e escreveu contra o DDL real. Nenhum erro de SQL encontrado nesta etapa | Carregou o arquivo no PostgreSQL e rodou `tests/test_trigger_sobreposicao.sql` (INSERT e UPDATE diretos, fronteiras de data, reativação de reserva cancelada): passou |
| 2 | `procedures/postgresql_procedures.sql` (`cancelar_reserva`) | Procedure de cancelamento com multa por faixa de dias (RN-04) e NO-SHOW | O DDL não tem status de quarto, então "liberar o quarto" só acontece porque a reserva deixa de ser ativa para o trigger. O agente documentou a limitação no cabeçalho em vez de inventar uma coluna. Nenhum erro de execução | Rodou `tests/test_procedures.sql` com fronteiras de 7, 6, 2, 1 e 0 dias e NO-SHOW: passou |
| 3 | `procedures/postgresql_procedures.sql` (`fazer_checkout`, 1ª versão) | Procedure de check-out (late check-out, fidelidade, pagamento) alterando 2 ou mais tabelas | **Erro real de omissão:** a 1ª versão gravava em uma única tabela (`Reserva`), reprovando o item "pelo menos 2 tabelas" da issue. O agente avisou a limitação ao entregar, mas entregou assim mesmo | Conferiu a entrega contra o checklist da issue e pediu a correção. Foi adicionada a tabela `Pagamento` (já prevista no `regras.md`) e o check-out passou a lançar a quitação nela. Recriou o banco do zero e os testes passaram |
| 4 | `procedures/postgresql_procedures.sql` (assinatura de `fazer_checkout`) | Acrescentar o parâmetro `p_forma_pagamento` ao check-out | Mudar a assinatura com `CREATE OR REPLACE` cria uma sobrecarga em vez de substituir, o que tornaria a chamada com 3 argumentos ambígua num banco já carregado. O agente percebeu antes de entregar e incluiu `DROP PROCEDURE IF EXISTS` | Recarregou o arquivo num banco recriado e rodou os testes: passaram |
| 5 | `postgresql/01_ddl.sql` (tabela `Pagamento`) | Tabela de pagamentos para o check-out gravar em duas tabelas | **Erro real de diagnóstico:** ao ver a saída de um `findstr` com linhas soltas do arquivo, o agente interpretou como `Pagamento` colado no lugar errado do DDL (alarme falso) | O grupo abriu o arquivo no VS Code e verificou que o `Pagamento` estava completo, com 6 colunas e 5 constraints, no final do arquivo. Nada foi alterado |
| 6 | `tests/test_procedures.sql` | Testes com valores de fronteira para as procedures | **Erro real:** os testes das constraints de `Pagamento` comparavam o texto da mensagem em inglês (`new row...`), mas o servidor do grupo responde em português (`a nova linha da relação ... viola a restrição de verificação`). O teste falhou na linha 234 mesmo com a constraint funcionando. Os demais casos (12:00:00 x 12:00:01, 18:00:00 x 18:00:01, fidelidade 4/5/9/10, sinal, estorno, erros `HOTEL-001/006/007/009/012`) já tinham passado | Mostrou a saída da falha ao agente. O teste passou a comparar o SQLSTATE (`23514`, `23503`), que não depende do idioma, e foi rodado de novo: `TODOS OS TESTES DAS PROCEDURES PASSARAM` |
| 7 | `tests/casos-de-teste/roteiro-ct.md` | Casos de teste BDD de todos os requisitos (Claude Code, Sonnet 5.5) | **Erro:** resultados esperados da Q03 com nomes do comentário do `02_inserts.sql` que não existem entre os hóspedes, e contadores do resumo escritos de cabeça (109 CT-U e 31 CT-M reais) | Nomes e contagens reconferidos no banco e com `grep`; roteiro corrigido. Detalhes em `docs/log-AI-Amanda.md` |
| 8 | `tests/unit/test_ct_u_consultas.py` | Testes das 10 consultas com valor esperado calculado à mão | **Erro:** rodar o arquivo como uma só instrução escondeu que só a Q08 estava quebrada; a regex com escapes gerou `SyntaxError: unterminated string literal` | Cada consulta passou a rodar isolada; Q01 a Q07, Q09 e Q10 batem com o valor à mão; Q08 ficou `xfail` (BUG-01) |
| 9 | `tests/unit/` (helpers e check-out) | Dados de apoio para os testes do check-out | **Erro de teste:** duas reservas CHECK-IN no mesmo quarto e período; o trigger recusou com HOTEL-005 | Helper com parâmetro `quarto`; teste corrigido |
| 10 | `tests/casos-de-teste/relatorio-problemas.md` | Relatório de problemas da PR #27 | **Erro de afirmação:** "o BOM pode quebrar o `pip install`", sem testar | Testado: nada quebra; relatório corrigido para baixa gravidade |
| 11 | Banco de laboratório (Docker) | Subir o banco pelo compose | `docker compose up` falhou com `required file not found` (código 127): `postgres-init.sh` com CRLF; o Git Bash alterou o caminho de volume do `docker run` | Banco criado com `docker run` e `docker cp`; o CRLF virou o problema P-03 do relatório |
| 12 | `tests/casos-de-teste/problemas-por-responsavel.md` | Separar os problemas por responsável pelo histórico do Git | Autor do commit foi tratado como origem do defeito antes de ler o `docs/Log-IA-Joao` | Aviso de limitação no arquivo; relatório atualizado com o log de João |

## Dificuldades do grupo (não foram erros da IA)

- O `psql` ficou em transação abortada (prompt `hotel=!>`) depois que um script parou no meio com `ON_ERROR_STOP`. Os comandos seguintes foram ignorados e o `CALL` acusou que a procedure não existia. Resolvido com `ROLLBACK;`.
- O `02_inserts.sql` foi carregado duas vezes e a segunda falhou com violação de `pk_categoria_quarto`. Resolvido ao recriar o esquema (`DROP SCHEMA public CASCADE; CREATE SCHEMA public;`) e carregar cada arquivo uma única vez.
- A tentativa de `DROP DATABASE hotel` falhou por estar conectado ao próprio banco, e `CREATE DATABASE` falhou por falta de permissão do usuário `hotel`. Resolvido com `DROP SCHEMA`, sem trocar de usuário.
- Caracteres acentuados saem quebrados no console do Windows (página de código 850). É só exibição e não afeta o banco nem os testes.
- O Docker ainda não foi usado para validar o `docker-compose.yml`. Essa verificação precisa ser feita antes da entrega final.

## Reflexão

- **Onde a IA mais ajudou:** montar os casos de fronteira dos testes (7, 6, 2, 1 e 0 dias; 12:00:00 e 12:00:01; fidelidade 4, 5, 9 e 10), manter os códigos de erro `HOTEL-00x` consistentes e antecipar o problema da sobrecarga de procedure.
- **Onde mais errou:** em cumprir o requisito literal da issue (duas tabelas por procedure), porque a 1ª versão do check-out ficou aquém e só foi corrigida na conferência. Também errou ao diagnosticar um arquivo correto como defeituoso e ao escrever um teste que dependia do idioma da mensagem do PostgreSQL. Nenhum desses erros apareceu lendo o código: todos apareceram ao executar.
- **O que faríamos diferente:** conferir o checklist da issue item a item antes de aceitar a entrega, rodar os testes logo após cada mudança de assinatura ou de DDL, e verificar o conteúdo do arquivo antes de concluir que há erro.
