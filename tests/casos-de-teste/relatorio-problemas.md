# Relatório de problemas encontrados pelos testes unitários

Escrito para: o desenvolvedor responsável por cada arquivo (banco, consultas, Docker e aplicação).

Origem: execução da suíte `tests/unit/` (pytest + psycopg) contra um PostgreSQL 17.12 criado do zero com `01_ddl.sql`, `02_inserts.sql`, `postgresql_procedures.sql` e `04_indices.sql`, na `main` já com as PRs #27, #29 e #30. Os testes seguem os requisitos (`A3_Projeto_BD.html` e `regras.md`), não o código.

**Resultado:** 180 testes, 178 passam e 2 falham de propósito (marcados `xfail(strict=True)` com o id do problema; viram erro assim que o problema for corrigido, para ninguém esquecer de tirar a marca). Além disso há problemas achados fora da suíte, em execução manual (seção 2).

Cada problema tem: onde está, evidência, impacto na nota ou na regra, correção sugerida e CT afetado. A correção é sugestão: quem decide e valida é o grupo (AGENTS.md).

---

## 1. Problemas que fazem teste falhar

### P-01 · Q08 não executa (SQL inválido) · Gravidade alta · **CORRIGIDO**

> **Corrigido:** o `SELECT` externo da Q08 agora usa `t.` nas duas cópias da consulta. O CT-U177 deixou de ser `xfail` e passa.

- **Onde:** `postgresql/03_consultas.sql`, consulta Q08 (a mesma falha existe na versão anterior, commit `2ef6357`).
- **Evidência:** `ERROR: missing FROM-clause entry for table "r"` (SQLSTATE 42P01). O `SELECT` externo lê `r.data_entrada_prevista`, `r.data_saida_prevista`, `r.valor_final_pago`, mas `r` só existe dentro da subconsulta; no nível de fora o alias é `t`.
- **Impacto:** a rubrica (critério 3, 10 pontos) diz "10 consultas, resultado conferido". Hoje são 9. Como `03_consultas.sql` é uma única instrução com `UNION ALL`, **uma consulta quebrada derruba o arquivo inteiro**: rodar o arquivo no `psql` ou no pgAdmin não devolve nenhum resultado.
- **Correção sugerida:** no `SELECT` externo da Q08, trocar `r.data_entrada_prevista`, `r.data_saida_prevista` e `r.valor_final_pago` por `t.`, e `CURRENT_DATE - r.data_saida_prevista` por `CURRENT_DATE - t.data_saida_prevista`.
- **Verificação feita:** com essa troca a Q08 devolve 7 linhas, idênticas ao valor calculado à mão no teste (Luciana 4 dias, Mariana 7, Ricardo 10, Carlos 12, Ana 18, Fernanda 21, João 56).
- **CT:** CT-U177 (`test_ct_u177_q08_ultima_estadia_de_cada_hospede`, antes marcado BUG-01, agora passa).

### P-02 · `03_consultas.sql` foi substituído por um arquivo gerado e perdeu o conteúdo · Gravidade alta · **CORRIGIDO (parcial)**

> **Corrigido:** o cabeçalho enganoso ("NAO EDITE A MAO", gerador inexistente) foi substituído por uma explicação do formato, e cada Q01 a Q10 tem `-- @Qnn Objetivo` e `-- @Qnn Técnica`. O CT-U181 deixou de ser `xfail` e passa. **Não restaurado:** os comentários "Resultado esperado" de cada consulta, que existiam em `2ef6357` (os valores esperados continuam nos testes). Para recuperá-los: `git show 2ef6357:postgresql/03_consultas.sql`.

- **Onde:** `postgresql/03_consultas.sql` (PR #29, commit `4a45258`).
- **Evidência:** a primeira linha agora diz `GERADO por scripts/gerar_consultas_pgadmin.py a partir de postgresql/03_consultas.sql. NAO EDITE A MAO.`
  - O gerador `scripts/gerar_consultas_pgadmin.py` **não existe no repositório**.
  - O arquivo diz ser gerado "a partir de" si mesmo (referência circular): a fonte original foi sobrescrita pela saída.
  - Os comentários `-- @Q01 · ...` com a pergunta, o objetivo e o **"Resultado esperado"** de cada consulta (existiam na versão `2ef6357`) sumiram. O próprio cabeçalho manda "comparar com os 'Resultado esperado' dos comentários de 03_consultas.sql", que não existem mais.
- **Impacto:** o enunciado exige "cada consulta com o objetivo em um comentário" e "resultado conferido por um teste com o valor esperado calculado à mão". Hoje o valor esperado só existe nos testes novos. Na defesa oral, o professor abre o arquivo e vê SQL de máquina.
- **Contexto no histórico:** o `docs/Log-IA-Joao` (linha 7 do resumo da conversa) diz que um gerador das 10 consultas para o pgAdmin foi criado; ele provavelmente está só na máquina de quem o escreveu e não foi commitado.
- **Correção sugerida:** restaurar a versão com comentários (`git show 2ef6357:postgresql/03_consultas.sql`), aplicar a correção do P-01 e, se o grupo quiser o formato para pgAdmin, manter o gerador e a saída em outro caminho (por exemplo `scripts/` e `performance/`), nunca no lugar do arquivo oficial.
- **CT:** CT-U181 (`test_ct_u181_cada_consulta_tem_objetivo_em_comentario`, antes marcado BUG-02, agora passa).
- **Contraprova positiva:** as outras 9 consultas (Q01 a Q07, Q09 e Q10) devolvem exatamente os valores calculados à mão (CT-U170 a CT-U179), então a lógica delas está correta. O problema é de organização e de Q08.

---

## 2. Problemas achados na execução manual (ainda sem teste automatizado)

### P-03 · O banco não sobe pelo Docker em checkout no Windows (CRLF) · Gravidade alta

- **Onde:** `docker/postgres-init.sh` (PR #27) e ausência de `.gitattributes`.
- **Evidência:** com `core.autocrlf=true` (padrão do Git para Windows), o checkout converte o script para CRLF (`git ls-files --eol` mostra `i/lf w/crlf`). O contêiner `postgres:17` então falha:
  ```
  /docker-entrypoint-initdb.d/00-init.sh: cannot execute: required file not found
  container ... exited (127)
  ```
  porque a primeira linha vira `#!/bin/sh\r`. Reproduzido com `docker compose up -d --wait postgres` em um volume novo.
- **Impacto:** é o critério transversal da A3 ("script que não roda = zero na etapa"; "quem avalia roda `docker compose up -d --wait`"). Quem clonar no Windows não sobe o banco. Um avaliador que descompacta o zip no Windows pode cair no mesmo problema.
- **Correção sugerida:** criar `.gitattributes` com `*.sh text eol=lf` (e, por segurança, `*.sql text eol=lf`), recomitar o script já normalizado e documentar no README. Alternativa: `command: ["sh","/scripts/..."]` não resolve o shebang, então o `.gitattributes` é o caminho certo.
- **Contexto no histórico:** o `docs/Log-IA-Joao` (linha 7 da tabela) registra que esse mesmo erro 127 foi diagnosticado e corrigido localmente com um `.gitattributes` (`*.sh text eol=lf`). Esse arquivo **nunca chegou à `main`** (`git ls-files` não o lista), então o problema continua para quem clonar. Basta versionar o `.gitattributes` que já existe na máquina de quem o criou.
- **CT:** CT-R14 e CT-I10 (ainda sem teste automatizado; a verificação exige o Docker real).
- **Como foi contornado nos testes:** o banco de laboratório foi criado com `docker run postgres:17` e os scripts carregados com `psql` na ordem do `postgres-init.sh`.

### P-04 · A demonstração da aplicação não se repete · Gravidade média

- **Onde:** `python/main.py` (PR #27), função `caminho_feliz_checkout`.
- **Evidência:** a primeira execução faz o check-out real da reserva 10 e confirma (`commit`). Na segunda execução:
  ```
  [Aviso de Negócio no Caminho Feliz]: HOTEL-007: a reserva 10 está CHECK-OUT e só uma reserva em CHECK-IN pode fazer check-out
  ```
  Quem avalia roda `docker compose run --rm app` mais de uma vez, ou na frente do professor depois de ter ensaiado.
- **Efeito colateral nos testes:** a demonstração altera os dados de exemplo que os testes usam (reserva 10 em CHECK-IN). Rodar `app` e depois `testes` sem recriar o volume quebra vários CTs. Os testes da suíte restauram o banco com ROLLBACK, a demonstração não.
- **Correção sugerida:** na demonstração, usar uma reserva criada pela própria aplicação na mesma transação e terminar com `rollback()` (o `regras.md`, seção 11, diz que por padrão a demonstração desfaz tudo e `--efetivar` grava), ou documentar que o volume precisa ser recriado.
- **CT:** CT-A13.

### P-05 · BOM (U+FEFF) em arquivos novos e no `.gitignore` · Gravidade baixa

- **Onde:** `python/main.py`, `python/requirements.txt` e `.gitignore` (os três começam com `EF BB BF`).
- **Evidência e correção de um alerta anterior:** testei os três: o Python executa `main.py` normalmente, o `pip install -r` lê a primeira linha sem erro e `git check-ignore` confirma que `.env` continua ignorado. **O BOM não quebra nada aqui.** Meu alerta anterior de que ele "pode quebrar o `pip install`" estava exagerado.
- **Impacto:** só higiene; ferramentas mais antigas ou outros editores podem se confundir. Pode ser regravado em UTF-8 sem BOM quando for conveniente.
- **CT:** CT-A15, CT-R13 (baixa prioridade).

### P-06 · O serviço `testes` do compose não executa nenhum teste · Gravidade média

- **Onde:** `docker-compose.yml` (PR #27), serviço `testes`: `command: ["pytest", "-q", "tests"]`.
- **Evidência:** antes desta suíte, `tests/` só tinha `.sql`, então o pytest terminava com código 5 (nenhum teste coletado). Com a suíte nova, o serviço passa a funcionar, mas **depende do `PG_DSN` do compose** (`host=postgres ...`), que é o mesmo do serviço `app`.
- **Pendências para fechar o CT-I16:**
  1. confirmar `docker compose run --rm testes` do zero (ainda não rodei o serviço pelo compose, só o pytest direto, por causa do P-03);
  2. decidir se os dois `.sql` de `tests/` (que já existiam) entram na verificação automatizada (CT-I17);
  3. resolver o P-04, para a ordem `app` e `testes` não importar.

### P-07 · Comentário do `02_inserts.sql` cita nomes que não existem nos dados · Gravidade baixa

- **Onde:** `postgresql/02_inserts.sql`, linhas de cabeçalho `F1` e "Totais gastos".
- **Evidência:** o comentário lista "Diego 2420,00 | Bruno 2250,00 | Elisa 800,00 = Fábio 800,00 | Gabriela 400,00" e fala em "Luciana em 7º", mas os hóspedes inseridos são Ana, Carlos, Fernanda, João, Mariana, Ricardo, Luciana e Gabriel. Os valores batem; os nomes não.
- **Impacto:** quem conferir o ranking à mão usando o comentário se confunde.
- **Correção sugerida:** trocar os nomes do comentário pelos reais (João 2420, Carlos 2250, Ana 1550, Fernanda 1200, Mariana 800 = Ricardo 800, Luciana 400).

### P-08 · Dados de fronteira previstos no planejamento que os inserts não trazem · Gravidade baixa

Os testes das consultas passam, mas **não provam** estas fronteiras porque os dados não as contêm (checklist de `perguntas_de_negocio.md`):

| Consulta | Fronteira prevista | O que existe hoje |
|---|---|---|
| Q02 | reserva CONFIRMADA em exatamente D+7 (entra) e em D+8 (fica fora) | só D+5 (entra) e D+10 (fora); a reserva 13, em D+7, está CANCELADA |
| Q06 | categoria com taxa exatamente 20% (não entra) | taxas de 25%, 33,3% e 14,3% |
| Q07 | serviço nunca consumido (0%) e empate de valor | todos os serviços têm consumo, sem empate |
| Q09 | hóspede que usou todos menos um | ninguém chega perto; o resultado é vazio |
| Q05 | mês sem receita e estadia que cruza a virada de mês | depende do dia em que se executa |

O CT-U178 compensa a Q09 inserindo consumos dentro do teste (sempre com ROLLBACK). Para as outras, vale acrescentar linhas a `02_inserts.sql`.

---

## 3. Divergências entre os requisitos e o código (já listadas no roteiro, seção 8.1)

Não há teste novo por elas: o roteiro (`roteiro-ct.md`) registra os CTs com status LACUNA, que devem falhar até serem implementados. Resumo para o desenvolvedor:

| Requisito | Situação no código |
|---|---|
| RN-01 (máximo de 30 noites) | só `saída > entrada`; 31 noites é aceito |
| RN-03 (capacidade) | a tabela `reserva` nem tem número de hóspedes |
| RN-06 (manutenção) | reserva em quarto `status_manutencao = TRUE` é aceita |
| RN-07 (máquina de estados) | qualquer `UPDATE` de status passa (só o CHECK de domínio protege) |
| RN-10 (sinal de 30%), RN-11 (consumo), RN-12 (check-in) | não implementadas |
| Estorno no cancelamento (tabela 4.1 do `regras.md`) | `cancelar_reserva` grava só a multa; o estorno do `02_inserts.sql` foi inserido à mão |
| `ck_reserva_desconto` | aceita 0 a 100; o `regras.md` fala em 0, 5 ou 10 |
| `ON DELETE` | `consumo_servico` e `cancelamento` usam `CASCADE`; o `regras.md` diz que todas as FKs bloqueiam |
| Nomes de status (**corrigido**, ver `problemas-por-responsavel.md`) | banco usa `CHECK-IN`/`CHECK-OUT`/`NO-SHOW`; `regras.md` e `perguntas_de_negocio.md` usam `EM_ANDAMENTO`/`FINALIZADA`/`NO_SHOW` |
| Caminhos (**corrigido**) | `AGENTS.md` cita `docs/regras.md`, mas o arquivo está em `regras.md`; `regras.md` cita `docs/perguntas_de_negocio.md`, que está na raiz |
| Q09 | consulta considera **todos** os serviços; `perguntas_de_negocio.md` pede só a categoria "Extras", que não existe no DDL |

---

## 4. O que foi verificado e está correto

Para o desenvolvedor saber o que não precisa mexer:

- **Constraints** (CT-U01 a CT-U28): todos os CHECK, UNIQUE, NOT NULL e FKs se comportam como documentado; todas têm nome com prefixo `pk_`, `uk_`, `fk_` ou `ck_`; toda FK declara `ON DELETE`; os valores monetários são `numeric(10,2)`; os scripts não têm sintaxe Oracle; os inserts usam datas relativas.
- **Trigger de sobreposição** (CT-U30 a CT-U37): intervalo `[entrada, saída)` correto nas 7 formas de sobreposição, status ativos e inativos, `INSERT` e `UPDATE` direto, e a própria linha não conflita consigo mesma. A mensagem cita o quarto e a reserva em conflito.
- **`cancelar_reserva`** (CT-U50 a CT-U60): fronteiras de 7, 6, 2, 1 e 0 dias e NO-SHOW; arredondamento (33,33 e 16,67); duas tabelas alteradas; não duplica a multa; libera o quarto.
- **`fazer_checkout`** (CT-U70 a CT-U115): fidelidade (4, 5, 9 e 10 estadias), taxa de late check-out (12:00:00, 12:00:01, 18:00:00, 18:00:01), saída antecipada sem estorno, saída tardia recusada, saldo com pagamentos e estornos anteriores, 1 centavo a menos recusado, formas de pagamento e erros de parâmetro.
- **Contrato** (CT-U150 a CT-U157): erros `HOTEL-nnn` com SQLSTATE `P0001`, nenhuma rotina faz COMMIT/ROLLBACK, comentários citam a RN, e o dado financeiro de exemplo é consistente (pagamentos menos estornos = valor final nas estadias e = multa nos cancelamentos).
- **Consultas** Q01 a Q07, Q09 e Q10 e **índices**: valores esperados calculados à mão batem com a saída.

---

## 5. Teste de mutação (os testes pegam defeitos?)

Cinco alterações propositais nas procedures e no trigger, cada uma aplicada ao banco, com a suíte rodada e o original restaurado em seguida:

| Mutação | Testes que falharam |
|---|---|
| `v_dias >= 7` para `v_dias > 7` (faixa sem multa) | 1 |
| `<= ... + 12 hours` para `<` (fronteira de 12:00:00) | 1 |
| fidelidade de 5 estadias para 6 | 3 |
| trigger: `<` para `<=` na entrada (back-to-back) | 2 |
| pagamento aceita 1 centavo a menos | 1 |

As 5 mutações foram detectadas. Com o código original restaurado, a suíte volta a 178 passando e 2 `xfail`. Isso atende à recomendação do `regras.md` (seção 9) e do enunciado ("rodar um teste de mutação ou ao menos quebrar o SQL de propósito").

## 6. Como reproduzir

```bash
# banco de laboratório (porta 55432 para não colidir com o PostgreSQL local do Windows)
docker run -d --name hotel_teste -e POSTGRES_USER=hotel -e POSTGRES_PASSWORD=hotel_lab_pwd \
  -e POSTGRES_DB=hotel -p 55432:5432 postgres:17
docker cp postgresql hotel_teste:/scripts/postgresql ; docker cp procedures hotel_teste:/scripts/procedures
for f in postgresql/01_ddl.sql postgresql/02_inserts.sql procedures/postgresql_procedures.sql postgresql/04_indices.sql; do
  docker exec hotel_teste psql -v ON_ERROR_STOP=1 -q -U hotel -d hotel -f /scripts/$f; done

pip install pytest "psycopg[binary]"
PG_DSN="host=localhost port=55432 dbname=hotel user=hotel password=hotel_lab_pwd" pytest tests/unit -q -rx
```

Pela regra do `AGENTS.md`, o agente não rodou `git push`; nada foi enviado ao repositório remoto.
