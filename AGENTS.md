# Diretrizes e Governança de Agentes de IA

## Regras de Interrompimento e Controle
- **Push negado**: A ferramenta de IA não possui permissão para executar comandos git push.
- **Validação humana obrigatória**: Todas as sugestões de DDL, DML, consultas e procedures devem ser validadas contra as regras descritas em docs/regras.md.
- **Rastreabilidade**: Todas as interações relevantes, erros da IA e correções manuais devem ser registradas em docs/ia-log.md e na seção 7 do README.md.
