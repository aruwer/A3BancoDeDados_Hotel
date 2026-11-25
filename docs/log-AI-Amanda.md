# Log de Uso de IA: casos de teste e testes unitários (Hotel Host)

Registro do que foi feito com a IA na frente de testes: roteiro de casos de teste BDD, testes unitários em pytest e relatório de problemas. Para juntar ao `docs/ia-log.md` e à seção 7 do `README.md` (o `AGENTS.md` pede os dois): as linhas 7 a 12 da tabela já foram acrescentadas em `docs/ia-log.md`.

O registro mede transparência e senso crítico: só entra o que de fato aconteceu nesta sessão. Onde diz "validação humana pendente", ninguém do grupo conferiu ainda o resultado (o `AGENTS.md` exige essa conferência antes de aplicar qualquer sugestão no banco).

## 1. Ferramenta e modelo

| Item | Valor |
|---|---|
| Ferramenta | Claude Code (extensão do VS Code) |
| Modelo | Claude Sonnet 5.5 (`claude-sonnet-5-5`) |
| Skills do repositório | nenhuma |
| Banco usado nos testes | PostgreSQL 17.12 em container Docker (`postgres:17`) descartável, porta 55432; o PostgreSQL local do Windows não foi usado |
| Dados | só os dados fictícios do `02_inserts.sql`; nenhum dado pessoal real foi enviado |
| Git | a IA fez commits locais a pedido (`7931778`, `bb46c6d`) e nenhum `git push` (proibido pelo `AGENTS.md`) |

## 2. Resumo da conversa (em ordem)

1. **Análise da PR #27.** A IA leu o diff, o `regras.md` e as procedures e listou 10 problemas. O texto do comentário para a PR foi preparado e **não foi postado**, por pedido do grupo.
2. **Roteiro de casos de teste.** Leu o enunciado (`A3_Projeto_BD.html`), o `regras.md`, o DDL, as procedures, os inserts e as PRs #27, #29 e #30, e escreveu `tests/casos-de-teste/roteiro-ct.md`: cerca de 190 CTs em BDD (Given/When/Then em inglês, texto em português), com status IMPL, PARCIAL ou LACUNA frente ao código. Quatro decisões foram perguntadas antes: tratamento das lacunas, pasta, nomes do branch e dos prefixos, e escopo das PRs.
3. **Testes unitários.** Sobe o banco do zero em container, escreve `tests/unit/` (pytest + psycopg) para os CTs já implementados e roda a suíte: 178 passam e 2 falham de propósito (`xfail` estrito).
4. **Teste de mutação.** Aplica 5 alterações propositais nas procedures e no trigger e confere que a suíte as detecta (as 5 foram detectadas).
5. **Relatório de problemas.** Escreve `relatorio-problemas.md` e, a pedido, `problemas-por-responsavel.md`, usando `git log -S` e `git blame` para ligar cada problema ao commit que o introduziu.

## 3. Registros

| # | Artefato | Pedido (resumo) | O que o agente errou ou omitiu | O que o grupo fez |
|---|---|---|---|---|
| 1 | `tests/casos-de-teste/roteiro-ct.md` | Casos de teste BDD de todos os requisitos, baseados no enunciado e no `regras.md`, não no código | **Erro:** os resultados esperados da Q03 foram escritos com os nomes do comentário do `02_inserts.sql` ("Diego Costa", "Bruno"), que não existem na lista de hóspedes. Os contadores do resumo ("cerca de 130" CT-U, "25" CT-M) também foram escritos de cabeça e estavam errados | O agente reconferiu os nomes na tabela `hospede` e contou os CTs com `grep` (109 CT-U, 31 CT-M), corrigindo o roteiro. Validação humana pendente |
| 2 | `tests/unit/test_ct_u_consultas.py` | Testes das 10 consultas com valor esperado calculado à mão | **Erro:** a primeira versão executava `03_consultas.sql` inteiro como uma instrução. Como a Q08 tem SQL inválido, as 10 consultas deram erro de uma vez (`missing FROM-clause entry for table "r"`) e escondiam quais estavam corretas. Depois, o escape de `\d`/`\n` na regex gerou `SyntaxError: unterminated string literal` ao coletar o módulo | Os testes passaram a executar cada consulta isolada, extraída do arquivo, e o `SyntaxError` foi corrigido. Os valores à mão (Q01 a Q07, Q09 e Q10) bateram com o banco. A Q08 ficou `xfail` com o id BUG-01 |
| 3 | `tests/helpers.py`, `test_ct_u_fazer_checkout.py` | Dados de apoio para o check-out (hóspede com N estadias, reserva em CHECK-IN) | **Erro de teste, não do banco:** `test_ct_u75` criava duas reservas CHECK-IN no mesmo quarto e período, e o trigger recusou com HOTEL-005, o que mostrou que o trigger funcionava | O helper ganhou o parâmetro `quarto` e o teste passou a usar quartos diferentes |
| 4 | `tests/casos-de-teste/relatorio-problemas.md` (P-05) | Listar problemas da PR #27 | **Erro de afirmação:** a IA afirmou que o BOM nos arquivos Python "pode quebrar o `pip install`", sem testar | Rodou `pip install --dry-run`, `python main.py` e `git check-ignore .env`: nada quebra com o BOM. O relatório foi corrigido para "baixa gravidade, higiene" e registra o erro |
| 5 | Execução do banco de laboratório | Subir o banco pelo compose | **Omissão:** o compose falhou com `required file not found` / código 127 (`postgres-init.sh` com CRLF no checkout do Windows). A primeira conexão tentada foi ao PostgreSQL local do Windows com a senha do laboratório, e falhou na autenticação; não se tentou adivinhar outras senhas. Também, a montagem de volume do `docker run` foi alterada pelo Git Bash (`C:/Program Files/Git/scripts/...`) | O banco passou a ser criado com `docker run postgres:17` e `docker cp` dos scripts, carregados na ordem do `postgres-init.sh`. O CRLF virou o problema P-03 do relatório. Validação humana pendente |
| 6 | `tests/casos-de-teste/problemas-por-responsavel.md` | Separar os problemas por responsável pelo histórico | **Risco de interpretação:** autor do commit não é o autor do erro (IA em todas as etapas, commits "Parte pessoa 2"). Na primeira passada a IA ainda não tinha lido o `docs/Log-IA-Joao`, que já registra o CRLF e a criação do `.gitattributes` e do gerador de consultas (nunca commitados) | O arquivo avisa a limitação no início, e o relatório foi atualizado com a informação do log de João. Validação humana pendente |

Erros reais encontrados **pela IA no código do grupo** (não no trabalho da IA), para a tabela de IA do README: Q08 inválida (P-01), `03_consultas.sql` substituído por arquivo gerado (P-02) e CRLF no `postgres-init.sh` (P-03). A origem de cada um (IA ou mão humana) só o grupo sabe e precisa confirmar.

## 4. Reflexão

- **Onde a IA mais ajudou:** montar as fronteiras dos testes (7, 6, 2, 1 e 0 dias; 12:00:00 e 12:00:01; 4, 5, 9 e 10 estadias), calcular à mão os resultados esperados das consultas e achar defeitos que só aparecem ao executar (Q08 inválida, demo que não se repete, CRLF).
- **Onde mais errou:** em afirmações que não verificou antes de escrever (nomes de hóspedes copiados de um comentário desatualizado, "o BOM quebra o pip") e em detalhes de ambiente (regex com escapes dentro do arquivo, caminho convertido pelo Git Bash).
- **O que faríamos diferente:** pedir à IA que verifique cada afirmação de risco com um comando antes de escrevê-la, rodar os testes logo após escrever cada arquivo e não usar comentário de cabeçalho como fonte do valor esperado.
- **Regra que vale para esta frente:** a IA propõe e o grupo valida; nenhum teste foi aplicado em banco que não seja o de laboratório e nada foi enviado ao remoto.
