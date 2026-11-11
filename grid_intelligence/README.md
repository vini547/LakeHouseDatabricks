# Grid Intelligence

Plataforma de dados e IA da **Luz do Vale Distribuidora S.A.** — uma distribuidora de energia
eletrica ficticia, sob regulacao da ANEEL — construida no Databricks em oito etapas (prompts 00–07
em `prompts/`). Apresentacao de negocio: tres dores mensuraveis — continuidade do fornecimento
(DEC/FEC), perdas nao tecnicas e atendimento ao cliente.

Documento mestre do projeto: [`.llm/prd.md`](.llm/prd.md) (dominio, glossario, regras RN-01..RN-14).
Prompts: [`prompts/`](prompts/) (`00-setup` a `07-relatorio-e-demonstracao`).

## Arquitetura

```
Volume raw.landing (parquet por pasta)
  → bronze   (Lakeflow Declarative Pipeline: ingestao fiel, RN-11)
  → silver   (RN-01, dedup, baseline, anonimização RN-09/RN-10)
  → gold     (as quatro entregas; COMMENT em linguagem de negócio, RN-14)
  → metric view gold.continuidade_metricas (definição única de DEC/FEC, RN-04)
  → dashboard AI/BI (Operação do dia; Perdas e clientes)
  → Genie space (copiloto em português, RN-13)
  → notebook relatorio_executivo (RF-08)
```

## Pre-requisitos

- Databricks CLI >= 1.0 instalada e autenticada no perfil `grid_intelligence`
  (`databricks auth profiles`).
- `uv` instalado (https://docs.astral.sh/uv/).
- Warehouse Serverless Starter (usada pelos sql_task do job e pelo Genie).

## Setup do zero

1. **Crie os catálogos por SQL** (bundle não cria catálogo):

   ```bash
   databricks experimental aitools tools query --profile grid_intelligence \
     "CREATE CATALOG IF NOT EXISTS grid_dev COMMENT 'Catalogo de desenvolvimento da Grid Intelligence'"
   databricks experimental aitools tools query --profile grid_intelligence \
     "CREATE CATALOG IF NOT EXISTS grid_intelligence COMMENT 'Catalogo de producao da Grid Intelligence'"
   ```

2. **Conceda permissão** (troque o e-mail):
   ```bash
   databricks grants update CATALOG grid_dev --json '{"changes":[{"principal":"SEU-EMAIL","add":["ALL_PRIVILEGES"]}]}' --profile grid_intelligence
   databricks grants update CATALOG grid_intelligence --json '{"changes":[{"principal":"SEU-EMAIL","add":["ALL_PRIVILEGES"]}]}' --profile grid_intelligence
   ```

3. **Deploy em dev**:
   ```bash
   databricks bundle validate --profile grid_intelligence
   databricks bundle deploy -t dev --profile grid_intelligence
   ```

4. **Suba os dados** (uma pasta por base, um Parquet dentro):
   ```bash
   databricks fs cp -r <PASTA_LOCAL>/landing dbfs:/Volumes/grid_dev/raw/landing --overwrite --profile grid_intelligence
   ```

5. **Rode o job** (pipeline + máscaras + metric view + relatório):
   ```bash
   databricks bundle run grid_intelligence -t dev --profile grid_intelligence
   ```

6. **Dashboard**: publicar com `databricks lakeview publish <DASHBOARD_ID> --warehouse-id 955067506c83b4e8 --profile grid_intelligence`.

7. **Genie space**: `python src/genie/aplicar.py --catalogo grid_dev` (ou `--catalogo grid_intelligence` para prod).

### Recomeçar do zero — comando DESTRUTIVO

> ⚠️ **DESTRUTIVO — não tem confirmação.** `CASCADE` remove o catálogo e **tudo** dentro dele:
> schemas, tabelas, volumes e os arquivos de dados no volume. Só rode se tiver certeza.

```bash
databricks experimental aitools tools query --profile grid_intelligence \
  "DROP CATALOG IF EXISTS grid_dev CASCADE"
```

## Estrutura de pastas

```
prompts/          prompts que constroem o projeto (00–07)
.llm/prd.md       documento mestre
src/pipelines/grid_intelligence/transformations/   01..23 — transformações SQL
src/notebooks/relatorio_executivo.py               relatório executivo (RF-08)
src/genie/genie_space.json                         definição do Genie (${catalogo}/${schema_gold} como marcadores)
src/genie/aplicar.py                               aplica/atualiza o space
src/sql/governanca_dado_pessoal.sql                column masks (RN-09/RN-10)
src/sql/metric_view_continuidade.sql               metric view DEC/FEC (RN-04)
src/sql/demonstracao.sql                           8 queries que provam as afirmações
src/dashboards/grid_intelligence.lvdash.json       AI/BI dashboard (declarado no bundle)
resources/                                         recursos do bundle
```

## Regras que valem repetir

- **RN-01** 3 minutos ou mais de interrupção entram na apuração; vive na silver, nunca no relatório.
- **RN-04** DEC/FEC têm uma única definição — a metric view; tudo consome com `MEASURE()`.
- **RN-07** Saída da detecção é **prioridade de inspeção** (alta/média/baixa),
  nunca rótulo de fraude, furto ou culpado.
- **RN-09/10** Transcrição é mascarada (`[MASCARADO]`) antes da análise; o original
  fica atrás de column mask (grupo `atendimento` vê o original).
- **RN-11** A ingestão não filtra nem corrige; quem descarta é a silver, com `WHERE` nomeado.
- **RN-12** Todo registro carrega `arquivo_origem` e `ingerido_bronze_em`.
- **RN-13** O agente e o relatório leem apenas a camada gold.
- **RN-14** Só a gold e a metric view levam COMMENT; bronze e silver são passagem.
- Nenhum catálogo/schema literal no código: `${var.catalog}`, `${resources.schemas.<camada>.name}`,
  `${resources.pipelines.*.id}`, marcadores `${catalogo}`/`${schema_gold}` no Genie.
- Perfil da CLI: `grid_intelligence`. Ambiente isolado por **catálogo**, nunca por nome de schema.
