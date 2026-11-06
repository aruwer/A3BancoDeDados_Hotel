# Memória e Log de Uso do Agente (AGENTS.md)

Este arquivo mantém o histórico e as configurações das interações com o agente de IA durante o desenvolvimento do Projeto Integrador de Banco de Dados (A3).

## Configuração do Agente

* **Ferramenta Principal:** Google Gemini 3.1 Pro (Interface Web).
* **Skills/Técnicas Utilizadas:**
  * Geração e formatação de código SQL (DDL, DML, Consultas).
  * Criação de diagramas entidade-relacionamento (UML/PlantUML).
  * Revisão de estrutura de repositórios baseada em regras (PDF da disciplina).

## Log de Sessões

### Sessão 1: 06/11/2026 - Modelagem e DDL
* **Objetivo:** Criar o Diagrama Entidade-Relacionamento (DER) e os scripts de inicialização (DDL) para Oracle e PostgreSQL.
* **Contexto Fornecido:** Regras de negócio do Hotel Host, critérios de aceite da tarefa e o PDF de regras da A3.
* **Resultados e Ajustes:**
  * O agente gerou as 7 entidades necessárias (incluindo `Servico` e `Consumo_Servico` para a relação N:M).
  * **Correção humana:** Foi necessário forçar o agente a gerar o arquivo no formato `.puml` (PlantUML) e renomear o diretório de `postgres/` para `postgresql/` conforme as regras da disciplina.
  * Os scripts DDL (`01_ddl.sql`) foram criados aplicando `CHECK` nos estados das reservas, `ON DELETE CASCADE` e tipos primitivos correspondentes para Oracle (`VARCHAR2`, `NUMBER`, `IDENTITY`) e PostgreSQL (`VARCHAR`, `SERIAL`).