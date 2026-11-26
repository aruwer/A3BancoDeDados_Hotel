# Relatório de problemas encontrados pelos testes unitários

Escrito para: o desenvolvedor responsável por cada arquivo (banco, consultas, Docker e aplicação).

Origem: execução da suíte `tests/unit/` (pytest + psycopg) contra um PostgreSQL 17.12 criado do zero com `01_ddl.sql`, `02_inserts.sql`, `postgresql_procedures.sql` e `04_indices.sql`, na `main` já com as PRs #27, #29 e #30. Os testes seguem os requisitos (`A3_Projeto_BD.html` e `regras.md`), não o código.

**Atualização (2026-11-26): 278 testes, 278 passam, na integração dos PRs #32 e #33 (seção 7).**

**Resultado em 2026-11-25 ( após os commits `a89d648`, `cfa7a5e`, `dc1ad8f` e `f97e2a7` de João): 180 testes, 180 passam.** Na primeira execução (sobre a `main`) eram 178 passando e 2 falhando de propósito (`xfail(strict=True)`, BUG-01 e BUG-02). João corrigiu os dois; as marcas `xfail` foram removidas e o extrator de consultas de `test_ct_u_consultas.py` foi adaptado ao novo formato do `03_consultas.sql` (blocos `-- @Qnn`). Ficam abertos os problemas achados fora da suíte, em execução manual (seção 2).

| Id | Situação |
|---|---|
| P-01 | **Resolvido** (`a89d648`) |
| P-02 | **Resolvido** (`a89d648`, `cfa7a5e`, `f97e2a7`); sobra detalhe menor, ver nota no item |
| P-03 | **Resolvido** (PR #31, `f91fe0c`; mergeado na branch de testes (`13fe246`, PR #31)); ainda não está na `main` |
| P-04 | **Resolvido** (PR #31, `f91fe0c` + `ab8a272`): a demo é repetível e o caminho feliz funciona |
| P-05 | **Resolvido** (PR #31) |
| P-06 | **Resolvido** (verificado pelo compose: 180 passando; ver nota sobre CRLF em clones antigos) |
| P-07 | **Resolvido** (PR #33, Yuri): o cabeçalho do `02_inserts.sql` usa os nomes reais |
| P-08 | **Resolvido** (PR #33, Yuri): fronteiras F1 a F8 nos dados; os testes das consultas foram recalculados à mão |
| Integração PR #32 + #33 | **Resolvida** na branch `integracao-teste` (ver seção 7) |
| Caminho do `AGENTS.md` | **Resolvido** (PR #31) |

Cada problema tem: onde está, evidência, impacto na nota ou na regra, correção sugerida e CT afetado. A correção é sugestão: quem decide e valida é o grupo (AGENTS.md).

---

## 1. Problemas que fazem teste falhar

### P-01 · Q08 não executa (SQL inválido) · Gravidade alta · RESOLVIDO

> **Resolvido em `a89d648` (João).** O `SELECT` externo da Q08 agora usa `t.`. Reteste: CT-U177 passa (sem `xfail`), com as 7 linhas calculadas à mão. O texto abaixo guarda o problema original.

- **Onde:** `postgresql/03_consultas.sql`, consulta Q08 (a mesma falha existe na versão anterior, commit `2ef6357`).
- **Evidência:** `ERROR: missing FROM-clause entry for table "r"` (SQLSTATE 42P01). O `SELECT` externo lê `r.data_entrada_prevista`, `r.data_saida_prevista`, `r.valor_final_pago`, mas `r` só existe dentro da subconsulta; no nível de fora o alias é `t`.
- **Impacto:** a rubrica (critério 3, 10 pontos) diz "10 consultas, resultado conferido". Hoje são 9. Como `03_consultas.sql` é uma única instrução com `UNION ALL`, **uma consulta quebrada derruba o arquivo inteiro**: rodar o arquivo no `psql` ou no pgAdmin não devolve nenhum resultado.
- **Correção sugerida:** no `SELECT` externo da Q08, trocar `r.data_entrada_prevista`, `r.data_saida_prevista` e `r.valor_final_pago` por `t.`, e `CURRENT_DATE - r.data_saida_prevista` por `CURRENT_DATE - t.data_saida_prevista`.
- **Verificação feita:** com essa troca a Q08 devolve 7 linhas, idênticas ao valor calculado à mão no teste (Luciana 4 dias, Mariana 7, Ricardo 10, Carlos 12, Ana 18, Fernanda 21, João 56).
- **CT:** CT-U177 (`test_ct_u177_q08_ultima_estadia_de_cada_hospede`, antes marcado BUG-01, agora passa).

### P-02 · `03_consultas.sql` foi substituído por um arquivo gerado e perdeu o conteúdo · Gravidade alta · RESOLVIDO

> **Resolvido em `a89d648`, `cfa7a5e` e `f97e2a7` (João).** `03_consultas.sql` voltou a ter os 10 blocos `-- @Qnn` com objetivo e "Resultado esperado"; a versão para o pgAdmin ficou em `postgresql/03_consultas_todas_pgadmin.sql`; o gerador foi versionado em `python/gerar_consultas_pgadmin.py`. Reteste: CT-U180 e CT-U181 passam (sem `xfail`) e as 10 consultas batem com os valores à mão. **Sobras menores (baixa gravidade):** (a) o cabeçalho do `03_consultas.sql` ainda diz "Q01 a Q05"; (b) a docstring do gerador manda rodar `scripts/gerar_consultas_pgadmin.py`, mas ele está em `python/`; (c) o gerador não foi executado nem comparado com o arquivo gerado por esta verificação. O texto abaixo guarda o problema original.

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

### P-03 · O banco não sobe pelo Docker em checkout no Windows (CRLF) · Gravidade alta · RESOLVIDO

> **Resolvido no PR #31 (`f91fe0c`, Rafaela), mergeado na branch de testes (`13fe246`, PR #31).** `.gitattributes` com `* text=auto` e `eol=lf` para `*.sh`, `*.sql` e `*.py`. Checado num worktree com `core.autocrlf=true`: `docker/postgres-init.sh` ficou com LF e o índice não tem arquivo CRLF. **Não rodei `docker compose up` com a correção**, só conferi o fim de linha. Falta integrar na `main`. O texto abaixo guarda o problema original.

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

### P-04 · A demonstração da aplicação não se repete · Gravidade média · RESOLVIDO

> **Resolvido no PR #31 (`f91fe0c` e `ab8a272`, Rafaela), mergeado na branch de testes (`13fe246`, PR #31).** Reverificado em 2026-11-26 depois do `ab8a272`: rodei `python/main.py` duas vezes e o passo [2] diz `Sucesso! Check-out ... validado (status='CHECK-OUT', valor_final_pago=R$ 200.00)` nas duas; o passo [3] segue capturando o HOTEL-007; o banco ficou igual (18 reservas, sequence 18) e a suíte continua em 180 passando. Ela aplicou datas relativas (entrada hoje, saída amanhã, check-in real uma hora atrás), quarto sem reserva ativa no período e `Decimal("200.00")`, como pedido na revisão. **Histórico:** na 1ª versão (`f91fe0c`) a demo ficou repetível, mas o passo [2] falhava com HOTEL-001. A descrição abaixo é a da 1ª versão da demo isolada. A demo agora cria a própria reserva, reverte e restaura a sequence: rodei `python/main.py` duas vezes e o banco ficou igual (18 reservas, sequence 18), com a suíte em 180 passando. **Mas o passo [2] (caminho feliz) agora termina em `HOTEL-001: a saída (...) é anterior ao check-in real (2099-01-10 14:00:00)`**, porque a reserva da demo tem check-in real em 2099 e o check-out usa a data de hoje. Correção validada por mim numa transação com rollback: entrada hoje, saída amanhã, check-in real uma hora atrás, quarto sem reserva ativa no período e valor pago igual ao bruto (R$ 200,00 deu `CHECK-OUT`). Já pedida na revisão do PR #31. O texto abaixo guarda o problema original.

- **Onde:** `python/main.py` (PR #27), função `caminho_feliz_checkout`.
- **Evidência:** a primeira execução faz o check-out real da reserva 10 e confirma (`commit`). Na segunda execução:
  ```
  [Aviso de Negócio no Caminho Feliz]: HOTEL-007: a reserva 10 está CHECK-OUT e só uma reserva em CHECK-IN pode fazer check-out
  ```
  Quem avalia roda `docker compose run --rm app` mais de uma vez, ou na frente do professor depois de ter ensaiado.
- **Efeito colateral nos testes:** a demonstração altera os dados de exemplo que os testes usam (reserva 10 em CHECK-IN). Rodar `app` e depois `testes` sem recriar o volume quebra vários CTs. Os testes da suíte restauram o banco com ROLLBACK, a demonstração não.
- **Correção sugerida:** na demonstração, usar uma reserva criada pela própria aplicação na mesma transação e terminar com `rollback()` (o `regras.md`, seção 11, diz que por padrão a demonstração desfaz tudo e `--efetivar` grava), ou documentar que o volume precisa ser recriado.
- **CT:** CT-A13.

### P-05 · BOM (U+FEFF) em arquivos novos e no `.gitignore` · Gravidade baixa · RESOLVIDO

> **Resolvido no PR #31 (`f91fe0c`, Rafaela), mergeado na branch de testes (`13fe246`, PR #31).** BOM removido de `python/main.py`, `python/requirements.txt` e `.gitignore`. O texto abaixo guarda o problema original.

- **Onde:** `python/main.py`, `python/requirements.txt` e `.gitignore` (os três começam com `EF BB BF`).
- **Evidência e correção de um alerta anterior:** testei os três: o Python executa `main.py` normalmente, o `pip install -r` lê a primeira linha sem erro e `git check-ignore` confirma que `.env` continua ignorado. **O BOM não quebra nada aqui.** Meu alerta anterior de que ele "pode quebrar o `pip install`" estava exagerado.
- **Impacto:** só higiene; ferramentas mais antigas ou outros editores podem se confundir. Pode ser regravado em UTF-8 sem BOM quando for conveniente.
- **CT:** CT-A15, CT-R13 (baixa prioridade).

### P-06 · O serviço `testes` do compose não executa nenhum teste · Gravidade média · RESOLVIDO

> **Verificado em 2026-11-26** na branch com o PR #31 mergeado: `docker compose up -d --wait` (projeto e porta separados) sobe o banco do zero e `docker compose run --rm testes` dá **180 passed**. Uma segunda rodada depois de `docker compose run --rm app` (demo com `Sucesso! ... CHECK-OUT`) também deu 180 passed, então a ordem entre `app` e `testes` não importa. O serviço não precisou de alteração. **Atenção para quem já tinha o repositório clonado antes do `.gitattributes`:** o arquivo `postgres-init.sh` continua em CRLF no disco e o container sai com código 127 de novo (aconteceu no meu checkout). O índice do Git está certo; é preciso regravar os arquivos (apagar `*.sh`, `*.sql` e `*.py` e rodar `git checkout -- <arquivos>`, ou clonar de novo). Clone novo não tem o problema. Pendente só o CT-I17 (decidir se os dois `.sql` de `tests/` entram na verificação). O texto abaixo guarda o problema original.

- **Onde:** `docker-compose.yml` (PR #27), serviço `testes`: `command: ["pytest", "-q", "tests"]`.
- **Evidência:** antes desta suíte, `tests/` só tinha `.sql`, então o pytest terminava com código 5 (nenhum teste coletado). Com a suíte nova, o serviço passa a funcionar, mas **depende do `PG_DSN` do compose** (`host=postgres ...`), que é o mesmo do serviço `app`.
- **Pendências para fechar o CT-I16:**
  1. confirmar `docker compose run --rm testes` do zero (ainda não rodei o serviço pelo compose, só o pytest direto, por causa do P-03);
  2. decidir se os dois `.sql` de `tests/` (que já existiam) entram na verificação automatizada (CT-I17);
  3. (P-04, resolvido no PR #31: a demo não suja mais o banco, então a ordem `app` e `testes` não importa)

### P-07 · Comentário do `02_inserts.sql` cita nomes que não existem nos dados · Gravidade baixa · RESOLVIDO

PR #33 (Yuri): o cabeçalho agora lista os hóspedes reais (João 2420, Carlos 2250, Ana 1550, Fernanda 1200, Mariana 800 = Ricardo 800, Larissa 675, Luciana 400).

### P-08 · Dados de fronteira previstos no planejamento que os inserts não trazem · Gravidade baixa · RESOLVIDO

PR #33 (Yuri) acrescentou as fronteiras (F1 a F8 no cabeçalho do `02_inserts.sql`) e os testes das consultas foram recalculados à mão (não copiados da saída) sobre os dados novos:

| Consulta | Fronteira | Como ficou |
|---|---|---|
| Q02 | D+7 entra, D+8 fica fora | reservas 19 (D+7, entra) e 20 (D+8, fora) |
| Q06 | taxa exatamente 20% não entra | Standard com 2 de 10 canceladas; só a Suíte (33,3%) aparece |
| Q07 | serviço nunca consumido e empate | Passeio turístico com 0%; Lavanderia e Translado empatam em 90,00 |
| Q09 | hóspede que usou todos menos um | Larissa usou 7 de 8; o resultado é vazio e o CT-U178 prova o caso positivo |
| Q05 | mês sem receita | a reserva 21 (Larissa) sai em hoje - 119 |

Sobra a Q09 considerar **todos** os serviços (o planejamento pede só a categoria "Extras", que o DDL não tem).

---

## 3. Divergências entre os requisitos e o código (já listadas no roteiro, seção 8.1)

Não há teste novo por elas: o roteiro (`roteiro-ct.md`) registra os CTs com status LACUNA, que devem falhar até serem implementados. Resumo para o desenvolvedor:

| Requisito | Situação no código |
|---|---|
| RN-01 (máximo de 30 noites) | **Resolvido** (PR #33): `ck_reserva_max_noites`; CT-U03 |
| RN-03 (capacidade) | **Resolvido** (PR #32): `numero_hospedes` e `trg_reserva_validacao`; CT-U40 a U43 |
| RN-06 (manutenção) | **Resolvido** (PR #32): reserva em quarto MANUTENCAO é recusada; CT-U80 a U82 |
| RN-07 (máquina de estados) | **Resolvido** (PR #32): o trigger valida a transição; CT-U94 a U96 |
| RN-10, RN-11, RN-12, auditoria, `registrar_reserva`, `fazer_checkin` | **Cortadas e documentadas** em `regras.md` (PR #32) |
| Estorno no cancelamento | **Resolvido** (PR #32): `cancelar_reserva` lança o estorno e o valor devido; CT-U61 e U62 |
| `ck_reserva_desconto` | **Resolvido** (PR #33): só 0, 5 ou 10; CT-U05 |
| `ON DELETE` | **Resolvido** (PR #33): `cancelamento` e `consumo_servico` usam RESTRICT; CT-U24 |
| Nomes de status e caminhos | **Resolvido** (PR #32 e PR #31) |
| Q09 | consulta considera **todos** os serviços; `perguntas_de_negocio.md` pede só a categoria "Extras", que não existe no DDL |

---

## 4. O que foi verificado e está correto

Para o desenvolvedor saber o que não precisa mexer:

- **Constraints** (CT-U01 a CT-U28): todos os CHECK, UNIQUE, NOT NULL e FKs se comportam como documentado; todas têm nome com prefixo `pk_`, `uk_`, `fk_` ou `ck_`; toda FK declara `ON DELETE`; os valores monetários são `numeric(10,2)`; os scripts não têm sintaxe Oracle; os inserts usam datas relativas.
- **Trigger de sobreposição** (CT-U30 a CT-U37): intervalo `[entrada, saída)` correto nas 7 formas de sobreposição, status ativos e inativos, `INSERT` e `UPDATE` direto, e a própria linha não conflita consigo mesma. A mensagem cita o quarto e a reserva em conflito.
- **`cancelar_reserva`** (CT-U50 a CT-U60): fronteiras de 7, 6, 2, 1 e 0 dias e NO-SHOW; arredondamento (33,33 e 16,67); duas tabelas alteradas; não duplica a multa; libera o quarto.
- **`fazer_checkout`** (CT-U70 a CT-U115): fidelidade (4, 5, 9 e 10 estadias), taxa de late check-out (12:00:00, 12:00:01, 18:00:00, 18:00:01), saída antecipada sem estorno, saída tardia recusada, saldo com pagamentos e estornos anteriores, 1 centavo a menos recusado, formas de pagamento e erros de parâmetro.
- **Contrato** (CT-U150 a CT-U157): erros `HOTEL-nnn` com SQLSTATE `P0001`, nenhuma rotina faz COMMIT/ROLLBACK, comentários citam a RN, e o dado financeiro de exemplo é consistente (pagamentos menos estornos = valor final nas estadias e = multa nos cancelamentos).
- **Consultas** Q01 a Q10 (a Q08 desde `a89d648`) e **índices**: valores esperados calculados à mão batem com a saída.

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

As 5 mutações foram detectadas. Com o código original restaurado, a suíte voltou ao estado anterior à mutação (naquela data, 178 passando e 2 `xfail`; hoje, 180 passando). Isso atende à recomendação do `regras.md` (seção 9) e do enunciado ("rodar um teste de mutação ou ao menos quebrar o SQL de propósito").

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

---

## 7. Integração dos PRs #32 (Pedro) e #33 (Yuri) (2026-11-26)

Feita na branch local `integracao-teste` (a partir da branch de testes), sem alterar os PRs. Resultado: **278 testes, 278 passam**, também pelo compose do zero (`docker compose up -d --wait` e `docker compose run --rm testes`) e com a demonstração do `app` repetida duas vezes.

Incompatibilidades que apareceram ao juntar tudo, e como cada uma foi resolvida:

| Incompatibilidade | Causa | Correção |
|---|---|---|
| `python/main.py` quebrava | usava `status_manutencao`, que o PR #32 trocou por `status_quarto` | `WHERE status_quarto <> 'MANUTENCAO'` |
| Q04 de `03_consultas.sql` e do arquivo do pgAdmin quebravam | mesma coluna | mesma troca |
| Conflito em `03_consultas.sql` | Pedro versionou o formato gerado (instrução única); João restaurou os blocos `-- @Qnn` com o resultado esperado | ficou o formato de João (o do pgAdmin continua em `03_consultas_todas_pgadmin.sql`, regenerado pelo gerador, que reproduz o arquivo versionado) |
| Conflito em `01_ddl.sql` | Yuri (`CHECK` 30 noites, desconto 0/5/10, RESTRICT) e Pedro (`numero_hospedes`, `taxa_checkout`, `valor_devido`, `status_quarto`) alteraram as mesmas linhas | ficaram as duas séries de constraints, com `ON DELETE RESTRICT` em `cancelamento` |
| Conflito em `.gitattributes` | Pedro tinha só `*.sh` | ficou a versão com `* text=auto` e LF para `.sh`, `.sql`, `.py` |
| 10 testes falhavam | valores esperados das consultas e CT-U156 (14 reservas) eram dos dados antigos | recalculados à mão contra `02_inserts.sql` do Yuri (conferidos também contra a saída) |
| Sem cobertura das regras novas do Yuri | | testes novos: desconto fora de 0/5/10 (CT-U05), 30 e 31 noites (CT-U03) e RESTRICT em `cancelamento` e `consumo_servico` (CT-U24) |
| Sobras de João | cabeçalho "Q01 a Q05" e caminho `scripts/` no gerador | corrigidos para "Q01 a Q10" e `python/` |

Ainda em aberto: Q09 sem a categoria "Extras"; `testes/conftest.py` (pasta do Yuri) não é usado pelo compose, que roda `tests`; o README cita Oracle, Java e serviços que não existem no compose.
