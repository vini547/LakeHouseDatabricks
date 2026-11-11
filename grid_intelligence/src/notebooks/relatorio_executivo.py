# Databricks notebook source
# ruff: noqa: F821  — spark e dbutils sao injetados pelo runtime do notebook

# COMMAND ----------
# Relatorio executivo (RF-08) para "o que acontece hoje" em uma regiao, lido APENAS da camada
# gold (RN-13). O dia de referencia e o ultimo dia com movimento, nao current_date().

dbutils.widgets.text("regiao", "Campinas")
dbutils.widgets.text("usar_ia", "true")
# Os dois ultimos vem como base_parameters do job; os defaults nao apontam catalogo nenhum.
dbutils.widgets.text("catalog", "")
dbutils.widgets.text("schema_gold", "gold")

regiao = dbutils.widgets.get("regiao")
cat = dbutils.widgets.get("catalog")
schema_gold = dbutils.widgets.get("schema_gold")
if not cat:
    raise ValueError("Parametro 'catalog' vazio — o notebook roda como task do job, que passa ${var.catalog}.")

spark.sql(f"USE CATALOG `{cat}`")
spark.sql(f"USE SCHEMA `{schema_gold}`")
print(f"Catalogo: {cat} | Schema: {schema_gold} | Regiao: {regiao} | usar_ia: {dbutils.widgets.get('usar_ia')}")

# COMMAND ----------
import json

painel = spark.table("painel_operacional_dia")
sel = f"nome_conjunto LIKE '{regiao}%'"
last = painel.filter(sel).agg({"dia": "max"}).first()[0]
if last is None:
    raise ValueError(
        f"Nenhum dia com movimento para a regiao '{regiao}'. "
        "Confira o parametro 'regiao' (esperado algo como 'Campinas') e se a gold esta populada."
    )
print(f"Dia de referencia: {last}")

dia_rows = painel.filter(f"nome_conjunto LIKE '{regiao}%' AND dia = '{last}'").orderBy("id_conjunto").collect()

ag30 = (
    painel.filter(f"nome_conjunto LIKE '{regiao}%' AND dia < '{last}' AND dia >= date_sub('{last}', 30)")
    .groupBy()
    .avg("chamados", "interrupcoes", "chamados_risco_saude", "mencoes_ouvidoria")
    .first()
)
media30 = {k: (ag30[k] if ag30[k] is not None else 0.0) for k in ["avg(chamados)", "avg(interrupcoes)", "avg(chamados_risco_saude)", "avg(mencoes_ouvidoria)"]}

conjuntos = ", ".join(sorted({r["nome_conjunto"] for r in dia_rows}))

cont = spark.sql(f"""
SELECT `Conjunto` AS conjunto, MEASURE(`DEC`) AS dec, MEASURE(`FEC`) AS fec
FROM continuidade_metricas
WHERE `Conjunto` LIKE '{regiao}%'
  AND `Mes` = (SELECT max(`Mes`) FROM continuidade_metricas)
GROUP BY ALL
ORDER BY conjunto
""").collect()

prio = spark.sql(f"""
SELECT bairro, count(*) AS ucs_alta
FROM prioridade_inspecao_uc
WHERE prioridade_inspecao = 'alta' AND id_conjunto IN (
  SELECT DISTINCT id_conjunto FROM painel_operacional_dia WHERE nome_conjunto LIKE '{regiao}%')
GROUP BY bairro ORDER BY ucs_alta DESC
""").collect()

clientes = spark.sql(f"""
SELECT id_cliente, qtd_chamados, qtd_ucs_com_chamado, qtd_mencoes_ouvidoria
FROM saude_cliente
WHERE risco_ouvidoria = 'alto' AND id_conjunto IN (
  SELECT DISTINCT id_conjunto FROM painel_operacional_dia WHERE nome_conjunto LIKE '{regiao}%')
ORDER BY qtd_mencoes_ouvidoria DESC, qtd_chamados DESC LIMIT 5
""").collect()

n_clientes_alto = spark.sql(f"""
SELECT count(*) AS c FROM saude_cliente
WHERE risco_ouvidoria = 'alto' AND id_conjunto IN (
  SELECT DISTINCT id_conjunto FROM painel_operacional_dia WHERE nome_conjunto LIKE '{regiao}%')
""").first()["c"]

# COMMAND ----------
contexto = {
    "dia": str(last),
    "regiao": regiao,
    "conjuntos_no_dia": [
        {
            "conjunto": r["nome_conjunto"],
            "interrupcoes": r["interrupcoes"],
            "horas_interrompidas": round(r["horas_interrompidas"], 2),
            "uc_horas_interrompidas": round(r["uc_horas_interrompidas"], 1),
            "chamados": r["chamados"],
            "chamados_negativos": r["chamados_negativos"],
            "chamados_risco_saude": r["chamados_risco_saude"],
            "mencoes_ouvidoria": r["mencoes_ouvidoria"],
            "uc_prioridade_alta": r["uc_prioridade_alta"],
            "acao_recomendada": r["acao_recomendada"],
        }
        for r in dia_rows
    ],
    "media_30_dias_anteriores": {
        "chamados": round(media30["avg(chamados)"], 1),
        "interrupcoes": round(media30["avg(interrupcoes)"], 1),
        "chamados_risco_saude": round(media30["avg(chamados_risco_saude)"], 1),
        "mencoes_ouvidoria": round(media30["avg(mencoes_ouvidoria)"], 1),
    },
    "continuidade_do_mes": [
        {"conjunto": r["conjunto"], "dec": round(r["dec"], 2), "fec": round(r["fec"], 2)} for r in cont
    ],
    "bairros_prioridade_alta": [{"bairro": r["bairro"], "ucs_alta": r["ucs_alta"]} for r in prio],
    "clientes_em_risco_ouvidoria_total": n_clientes_alto,
    "clientes_em_risco_ouvidoria_top5": [
        {"id_cliente": r["id_cliente"], "chamados": r["qtd_chamados"],
         "ucs": r["qtd_ucs_com_chamado"], "mencoes_ouvidoria": r["qtd_mencoes_ouvidoria"]}
        for r in clientes
    ],
}
print(json.dumps(contexto, ensure_ascii=False, indent=2))

# COMMAND ----------
prompt = f"""Voce e o redator do relatorio executivo da Luz do Vale Distribuidora. Escreva para um diretor com dois minutos.
Use EXCLUSIVAMENTE os numeros fornecidos abaixo. Nao estime, nao arredonde para efeito, nao invente valor nenhum.
UCs com consumo atipico sao prioridade de inspecao — NUNCA escreva fraude, furto, roubo ou irregularidade.
Estrutura em tres partes: o que aconteceu; impacto em numeros; o que precisa de acao. Tom direto, sem adjetivo de marketing. Maximo de 250 palavras.
A parte de impacto em numeros DEVE citar: quantidade de chamados e de interrupcoes do dia, comparados com a media dos 30 dias anteriores; e DEC e FEC do mes, por conjunto, exatamente como fornecidos.

NUMEROS:
{json.dumps(contexto, ensure_ascii=False, indent=2)}"""
_escapado = prompt.replace("'", "''")

usar_ia = dbutils.widgets.get("usar_ia") == "true"
if usar_ia:
    texto = spark.sql(f"SELECT ai_gen('{_escapado}') AS r").first()["r"]
else:
    c = contexto
    dia_px = c["dia"]
    conjuntos_txt = "; ".join(
        f"{d['conjunto']}: {d['interrupcoes']} interrupcoes, {d['uc_horas_interrompidas']} UCxh sem energia, "
        f"{d['chamados']} chamados ({d['chamados_risco_saude']} com risco a saude)" for d in c["conjuntos_no_dia"]
    )
    media_px = c["media_30_dias_anteriores"]
    cont_txt = "; ".join(f"{d['conjunto']}: DEC {d['dec']} h, FEC {d['fec']}" for d in c["continuidade_do_mes"])
    prio_txt = ", ".join(f"{d['bairro']} ({d['ucs_alta']} UCs)" for d in c["bairros_prioridade_alta"]) or "nenhum"
    texto = (
        f"O que aconteceu — {dia_px}, regiao {c['regiao']}: {conjuntos_txt}.\n"
        f"Impacto em numeros — Dia contra a media dos 30 dias anteriores: "
        f"chamados {sum(d['chamados'] for d in c['conjuntos_no_dia'])} vs {media_px['chamados']}; "
        f"interrupcoes {sum(d['interrupcoes'] for d in c['conjuntos_no_dia'])} vs {media_px['interrupcoes']}. "
        f"Continuidade do mes: {cont_txt}.\n"
        f"O que precisa de acao — Bairros com prioridade alta de inspecao: {prio_txt}. "
        f"Clientes em risco de ouvidoria: {c['clientes_em_risco_ouvidoria_total']}. "
        f"Acoes: {'; '.join(d['acao_recomendada'] for d in c['conjuntos_no_dia'])}."
    )

print("=" * 72)
print(f"RELATORIO EXECUTIVO — {regiao.upper()} — {contexto['dia']}")
print("=" * 72)
print(texto)
dbutils.notebook.exit(texto)
