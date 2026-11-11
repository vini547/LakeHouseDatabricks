# AGENTS.md — convenções para quem continuar o Grid Intelligence

Projeto construído ao vivo em aula, no Databricks, em 8 etapas (prompts 00–07).
Documento mestre: `.llm/prd.md`. Leitura obrigatória antes de mexer em qualquer coisa.

## Regras que você (agente) não pode violar

1. **RN-07 — nunca acusar.** A saída da detecção de consumo baixo é **prioridade de
   inspeção** (alta/média/baixa). Nenhuma coluna, valor, comentário ou texto do projeto pode
   rotular uma UC como fraude, furto, roubo ou irregularidade. A diferença é jurídica em setor
   regulado — o consumidor também é seu público.
2. **RN-13 — o agente e o relatório leem apenas a gold.** Bronze e silver não entram
   em respostas nem texto, nem "só para checar".
3. **RN-04 — DEC e FEC só existem num lugar:** a metric view `continuidade_metricas`.
   Toda consulta usa `MEASURE(`DEC`)` / `MEASURE(`FEC`)` com `GROUP BY ALL`.
   Nunca recalcule a divisão em outro lugar.
4. **RN-11 — a ingestão não filtra.** Bronze copia fielmente, com `arquivo_origem` e
   `ingerido_bronze_em`. Correção/dedup/teto físico acontecem na silver, com `WHERE` visível.
5. **RN-09/RN-10 — dado pessoal.** Transcrições são mascaradas na silver (`[MASCARADO]`);
   a `bronze.chamados` fica atrás de column mask (`grupo atendimento`); ajuste texto apenas
   no anonimizado.
6. **RN-01** — só interrupções ≥ 3 minutos entram na apuração; vive na silver
   (`interrupcoes_validas`), nunca no relatório.

## Convenção de nome e código

- Texto do projeto em **português do Brasil**; nomes sem acentuação (`unidades_consumidoras`).
- **Nenhum catálogo/schema literal em código.** Bundle: `${var.catalog}` +
  `${resources.schemas.<camada>.name}`. SQL fora do bundle (genie): marcadores `${catalogo}`/`${schema_gold}`.
  Aplicação: `python src/genie/aplicar.py --catalogo <alvo>`.

- **Diretriz de simplicidade:** sem expectations, sem `CONSTRAINT`, sem `TBLPROPERTIES`
  (exceção já registrada: `delta.feature.timestampNtz` — dados têm `TIMESTAMP_NTZ` e a escrita
  falha sem isso), sem `COMMENT` em bronze/silver. Gold e metric view levam COMMENT — é o
  que o agente lê.
- **Um SELECT direto vence um WITH de quatro CTEs** quando o CTE não for necessário.
- Nada de tratamento "e se…" para dado que não existe. Dataset finito e sintético.

## Fluxo de trabalho

- Perfil da CLI: `grid_intelligence`. Ambiente isolado por **catálogo**: dev `grid_dev`,
  prod `grid_intelligence`. Schemas têm os nomes exatos `raw`/`bronze`/`silver`/`gold` em ambos.
- Pipeline serverless (`resources/grid_bronze.pipeline.yml`); job `Grid Intelligence - Pipeline e metricas`
  (`resources/grid_job.yml`) com quatro tasks: pipeline → governança → metric view → relatório (notebook).
- `databricks bundle validate --profile grid_intelligence` antes de qualquer deploy.
- Ruff line-length 120. `uv run ruff check` e `uv run pytest`.
