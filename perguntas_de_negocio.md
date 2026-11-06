# Perguntas de negócio das 10 consultas: Hotel Host

> Arquivo de planejamento (sem SQL). Cada pergunta vira uma consulta em
> `postgresql/03_consultas.sql` e `oracle/03_consultas.sql`, com a pergunta
> copiada no comentário `-- @Qnn`. O resultado esperado deve ser o mesmo nos dois bancos.
>
> As linhas marcadas **Decisão** fixam os pontos que as perguntas deixariam em aberto
> (status NO_SHOW e LIMPEZA, desconto no check-out, colunas de checkout, ver `docs/regras.md`);
> podem ser trocadas, desde que o teste e os dados de fronteira acompanhem.

## Convenções (valem para todas as consultas)

- **Estadia concluída** = reserva com status `FINALIZADA`.
- **Reserva ativa** = `CONFIRMADA` ou `EM_ANDAMENTO`.
- **Receita de uma estadia** = `valor_final` da reserva FINALIZADA (diárias com desconto + consumos + taxa de late check-out). A receita é contada no mês da `data_saida`.
- **Receita de diárias** = noites × `valor_diaria` × (1 − `percentual_desconto`/100).
- **Cuidado com multiplicação de linhas:** juntar RESERVA com CONSUMO_RESERVA repete a diária para cada consumo. Para somar diárias e consumos juntos (Q03), calcule cada parte numa subconsulta e só depois junte.
- Datas sempre relativas a hoje (`CURRENT_DATE` no PostgreSQL, `TRUNC(SYSDATE)` no Oracle).

## Visão geral

| # | Pergunta (resumo) | Técnica | Regras ligadas | Quem usa a resposta |
|---|---|---|---|---|
| Q01 | Receita de diárias por tipo de quarto | JOIN + agregação (GROUP BY/HAVING) | RN-05 | Gerência |
| Q02 | Chegadas dos próximos 7 dias | JOIN | RN-12 | Recepção |
| Q03 | Ranking dos hóspedes que mais gastaram | JOIN + agregação + window (RANK) | RN-05, RN-11 | Marketing / fidelidade |
| Q04 | Quartos disponíveis num período | **NOT EXISTS** (anti-join) | RN-02, RN-06 | Recepção / reservas |
| Q05 | Receita acumulada mês a mês | window (SUM OVER) | RN-08 | Gerência |
| Q06 | Tipos de quarto com cancelamento alto | JOIN + agregação (GROUP BY/HAVING) | RN-04 | Gerência |
| Q07 | Participação de cada serviço na receita de consumo | JOIN + window sobre agregação | RN-11 | Gerência |
| Q08 | Última estadia concluída de cada hóspede | JOIN + window (ROW_NUMBER) | RN-05 | Fidelidade |
| Q09 | Hóspedes que já usaram todos os serviços extras | divisão relacional (NOT EXISTS duplo) | RN-11 | Marketing |
| Q10 | Reservas e receita por tipo de quarto e situação, com subtotais | JOIN + ROLLUP | RN-04 | Gerência |

**Cobertura da rubrica**
- JOIN (mín. 2): Q01, Q02, Q03, Q06, Q07, Q08, Q10
- Window function (mín. 2): Q03, Q05, Q07, Q08
- Agregação (mín. 2): Q01, Q03, Q06, Q07, Q10
- NOT EXISTS (mín. 1): Q04, Q09
- Extras que dão destaque: ROLLUP (Q10) e divisão relacional (Q09)

## As 10 perguntas

### Q01 · Receita por tipo de quarto (JOIN + agregação)
**Pergunta:** Quanto cada tipo de quarto (Standard, Luxo, Suíte...) faturou com diárias nas estadias concluídas, mostrando só os tipos que faturaram mais de zero?
**Para quê:** a gerência decide onde investir em reforma ou ajustar a tarifa.
**Dado de fronteira:** um tipo de quarto cadastrado sem nenhuma estadia concluída (não pode aparecer) e um tipo só com reservas canceladas.
**Decisão:** usar a receita de diárias das convenções (já com o desconto de fidelidade), sem consumos nem taxas.

### Q02 · Chegadas dos próximos 7 dias (JOIN)
**Pergunta:** Quais reservas confirmadas têm check-in nos próximos 7 dias, com o nome do hóspede, o quarto, o tipo e o número de noites, em ordem de chegada?
**Para quê:** a recepção prepara a limpeza e a distribuição dos quartos.
**Dado de fronteira:** uma reserva que chega exatamente em 7 dias (entra) e outra em 8 dias (fica de fora); uma reserva já cancelada dentro da janela (não entra); uma reserva que chega hoje (entra).
**Decisão:** a janela é de hoje até hoje+7, inclusive nos dois extremos.

### Q03 · Ranking de hóspedes por gasto total (JOIN + agregação + window RANK)
**Pergunta:** Quais são os 5 hóspedes que mais gastaram no hotel, somando diárias e consumos, e em que posição ficou cada um (empates na mesma posição)?
**Para quê:** o marketing escolhe quem convidar para o programa de fidelidade.
**Dado de fronteira:** dois hóspedes com exatamente o mesmo gasto no 5º lugar, para mostrar a diferença entre RANK e ROW_NUMBER (o resultado traz 6 linhas); um hóspede sem nenhum consumo extra.
**Decisão:** gasto total = `valor_final` das reservas FINALIZADAS. Se preferirem somar diárias e consumos à mão, atenção à multiplicação de linhas descrita nas convenções.

### Q04 · Quartos disponíveis no período (NOT EXISTS, anti-join)
**Pergunta:** Quais quartos estão livres para quem quer entrar no dia X e sair no dia Y, ou seja, não têm nenhuma reserva ativa que se sobreponha a esse período?
**Para quê:** é a pergunta mais frequente da recepção e do site de reservas (regra RN-02).
**Dado de fronteira:** reserva que termina exatamente no dia X (quarto liberado, não bloqueia) e reserva que começa exatamente no dia Y (também não bloqueia); reserva cancelada ou NO_SHOW no mesmo período (não bloqueia); quarto em manutenção.
**Decisão:** quarto com status MANUTENCAO fica fora da lista (RN-06); quarto em LIMPEZA ou OCUPADO entra, porque a disponibilidade aqui depende só das datas das reservas. A condição de sobreposição é a mesma da procedure: `entrada_existente < Y` e `saida_existente > X`.

### Q05 · Receita acumulada mês a mês (window SUM OVER)
**Pergunta:** Em cada mês do ano, quanto o hotel faturou e quanto já tinha acumulado desde janeiro?
**Para quê:** a gerência acompanha a meta anual e a sazonalidade.
**Dado de fronteira:** um mês sem nenhuma receita no meio da série e uma estadia que atravessa a virada de mês.
**Decisão:** a receita de uma estadia conta no mês da `data_saida`, então a estadia que atravessa a virada vai inteira para o mês seguinte. Meses sem receita: a proposta é mostrar só meses com receita; mostrar o mês zerado exige um gerador de meses que muda entre os bancos (`generate_series` no PostgreSQL, `CONNECT BY LEVEL` no Oracle), bom para a tabela de diferenças do README.

### Q06 · Tipos de quarto com muito cancelamento (JOIN + GROUP BY/HAVING)
**Pergunta:** Quais tipos de quarto têm taxa de cancelamento acima de 20% das reservas feitas?
**Para quê:** a gerência revisa a política de cancelamento (RN-04) para os tipos problemáticos.
**Dado de fronteira:** um tipo com taxa exatamente igual a 20% (não entra, a regra é "acima de") e um tipo com 0 cancelamentos.
**Decisão:** taxa = reservas CANCELADAS dividido por todas as reservas do tipo (em qualquer situação). NO_SHOW não conta como cancelamento aqui; aparece só na Q10. Cuidado com divisão de inteiros: multiplicar por 100.0 antes de dividir.

### Q07 · Participação de cada serviço na receita de consumo (JOIN + window sobre agregação)
**Pergunta:** Que percentual da receita de consumos (restaurante, frigobar, lavanderia, spa...) vem de cada serviço?
**Para quê:** a gerência vê quais serviços valem a pena manter.
**Dado de fronteira:** dois serviços com o mesmo valor total e um serviço que existe no catálogo mas nunca foi consumido.
**Decisão:** o serviço nunca consumido aparece com 0% (LEFT JOIN). Receita de consumo = quantidade × `preco_unitario` da própria CONSUMO_RESERVA (o preço copiado no lançamento), não o preço atual do catálogo.

### Q08 · Última estadia de cada hóspede (JOIN + window ROW_NUMBER)
**Pergunta:** Para cada hóspede, qual foi a estadia concluída mais recente (quarto, datas e valor) e há quantos dias ela terminou?
**Para quê:** a recepção reconhece o cliente que volta; o marketing identifica quem sumiu.
**Dado de fronteira:** hóspede com uma única estadia; hóspede com duas estadias que terminam no mesmo dia; hóspede sem nenhuma estadia concluída (não aparece).
**Decisão:** desempate pelo maior `reserva_id` (`ORDER BY data_saida DESC, reserva_id DESC`).

### Q09 · Hóspedes que usaram todos os serviços extras (divisão relacional)
**Pergunta:** Quais hóspedes já consumiram todos os serviços da categoria "Extras" do catálogo (por exemplo spa, translado e lavanderia)?
**Para quê:** o marketing monta uma lista de clientes de alto engajamento.
**Dado de fronteira:** hóspede que usou todos menos um (não entra); hóspede que usou um serviço várias vezes mas não todos (não entra); um serviço novo no catálogo que ninguém usou (o resultado pode ficar vazio, e isso precisa ser testado).
**Decisão:** o modelo precisa de `SERVICO.categoria`, atributo que não existia (ver `docs/regras.md`, seção 7). Valor sugerido: `EXTRA`.

### Q10 · Reservas e receita por tipo e situação, com subtotais (JOIN + ROLLUP)
**Pergunta:** Quantas reservas e quanto de receita existem por tipo de quarto e por situação (concluída, cancelada, no-show), com subtotal de cada tipo e total geral?
**Para quê:** visão única para a diretoria, com o peso das perdas por cancelamento e no-show.
**Dado de fronteira:** um tipo sem reservas canceladas (a linha some, mas o subtotal continua certo) e conferência de que o total geral bate com a soma dos subtotais.
**Decisão:** situações = FINALIZADA, CANCELADA e NO_SHOW (reservas CONFIRMADA e EM_ANDAMENTO ficam fora). Receita das FINALIZADAS = `valor_final`; das CANCELADAS e NO_SHOW = `multa_cancelamento`. Na saída do ROLLUP, rotular as linhas de subtotal e total (`COALESCE(..., 'TOTAL')`).

## Banco de reserva (se alguma pergunta cair)

Ideias a partir do `docs/regras.md` que podem substituir uma das 10 ou virar teste extra:

- Taxa de ocupação por tipo de quarto no mês (JOIN + agregação).
- Próxima reserva de cada quarto (ROW_NUMBER com PARTITION BY).
- Reservas na faixa de multa de 2 a 6 dias nos próximos dias (JOIN + aritmética de datas).
- Hóspedes que mudam de faixa de fidelidade na próxima estadia, com 4 ou 9 concluídas (HAVING).
- Receita de late check-out por mês (agregação sobre `taxa_checkout`).

## Dados de fronteira que o `02_inserts.sql` precisa conter

- [ ] Reserva que chega em exatamente 7 dias, outra em 8 dias e outra hoje (Q02)
- [ ] Reservas encostadas: saída no dia X e entrada no mesmo dia X, no mesmo quarto (Q04)
- [ ] Reserva CANCELADA e reserva NO_SHOW em período que se sobrepõe a uma ativa (Q04)
- [ ] Quartos nos quatro status: DISPONIVEL, OCUPADO, LIMPEZA, MANUTENCAO (Q04)
- [ ] Empate de gasto total no 5º lugar do ranking (Q03)
- [ ] Hóspede com uma estadia só e hóspede com estadias no mesmo dia final (Q08)
- [ ] Tipo de quarto com taxa de cancelamento exatamente igual a 20% (Q06)
- [ ] Mês sem receita no meio do ano e estadia que atravessa a virada de mês (Q05)
- [ ] Serviço nunca consumido e serviço com total empatado (Q07)
- [ ] Hóspede que usou todos os extras menos um (Q09)
- [ ] Reservas nas três situações (FINALIZADA, CANCELADA, NO_SHOW) nos tipos principais (Q10)
- [ ] Hóspedes com exatamente 4, 5, 9 e 10 estadias concluídas, para os descontos de 0%, 5% e 10% (Q01, Q03)
- [ ] Reservas CONFIRMADAS com entrada em hoje+7, +6, +2, +1, hoje e ontem, para as faixas de cancelamento e o NO_SHOW
- [ ] Reserva de 30 noites, reserva de 1 noite e reserva com sinal exatamente igual a 30%
- [ ] Datas **relativas a hoje** (hoje - 30, hoje + 7...), para o resultado ser o mesmo em qualquer dia

## Resultados esperados (preencher depois de rodar, iguais nos dois bancos)

| Consulta | Resultado esperado | O que prova |
|---|---|---|
| Q01 | _preencher_ | tipo sem estadia concluída não aparece |
| Q02 | _preencher_ | janela inclusiva de 7 dias |
| Q03 | _preencher_ | RANK com empate (6 linhas) |
| Q04 | _preencher_ | saída no dia X não bloqueia |
| Q05 | _preencher_ | acumulado correto |
| Q06 | _preencher_ | "acima de 20%", não "a partir de" |
| Q07 | _preencher_ | percentuais somam 100% |
| Q08 | _preencher_ | ROW_NUMBER = 1 com desempate |
| Q09 | _preencher_ | divisão relacional |
| Q10 | _preencher_ | total geral = soma dos subtotais |
