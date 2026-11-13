# Diretrizes e Governança de Agentes de IA

## Regras de Interrompimento e Controle
- **Push negado**: A ferramenta de IA não possui permissão para executar comandos git push.
- **Validação humana obrigatória**: Todas as sugestões de DDL, DML, consultas e procedures devem ser validadas contra as regras descritas em docs/regras.md.
- **Rastreabilidade**: Todas as interações relevantes, erros da IA e correções manuais devem ser registradas em docs/ia-log.md e na seção 7 do README.md.

## Tecnologias Oficiais do Projeto
- **Linguagem de programação**: Python.
- **SGBD**: PostgreSQL 17

## Diretrizes Técnicas
- A aplicação oficial do projeto deve ser desenvolvida exclusivamente em Python.
- O banco de dados oficial do projeto deve utilizar PostgreSQL 17.
- Todos os scripts DDL, DML, consultas e procedures devem ser compatíveis com PostgreSQL 17.
- Não utilizar scripts, arquivos ou configurações específicas do Oracle.
- Não manter estruturas ou arquivos Java, pois a aplicação oficial é desenvolvida em Python.
- Todas as alterações relacionadas ao banco de dados devem respeitar as regras definidas em docs/regras.md.

## Governança e Validação ##
- Toda sugestão de alteração no banco de dados deve passar por validação humana antes de ser aplicada.
- A IA não possui permissão para executar comandos git push.
- As interações relevantes com a IA, erros identificados e correções manuais devem ser registradas em docs/ia-log.md e na seção 7 do README.md.
