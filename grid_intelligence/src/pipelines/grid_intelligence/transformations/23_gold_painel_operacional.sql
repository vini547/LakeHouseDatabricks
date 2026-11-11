CREATE OR REFRESH MATERIALIZED VIEW ${catalogo}.${schema_gold}.painel_operacional_dia
COMMENT 'Cockpit diario do gestor de operacoes: uma linha por conjunto e dia, costurando interrupcoes, chamados, consumo, UCs em prioridade de inspecao e a acao recomendada na ordem em que um gestor olharia.'
AS
WITH interrupcoes AS (
  SELECT
    id_conjunto,
    data_evento AS dia,
    count(*) AS interrupcoes,
    sum(duracao_horas) AS horas_interrompidas,
    sum(uc_horas_interrompidas) AS uc_horas_interrompidas
  FROM ${catalogo}.${schema_silver}.interrupcoes_validas
  GROUP BY id_conjunto, data_evento
),
chamados AS (
  SELECT
    id_conjunto,
    CAST(abertura AS DATE) AS dia,
    count(*) AS chamados,
    count_if(sentimento = 'negative') AS chamados_negativos,
    count_if(ameacou_ouvidoria) AS mencoes_ouvidoria,
    count_if(risco_a_saude) AS chamados_risco_saude,
    count_if(urgencia = 'alta') AS chamados_urgencia_alta
  FROM ${catalogo}.${schema_silver}.chamados_enriquecidos
  GROUP BY id_conjunto, CAST(abertura AS DATE)
),
consumo AS (
  SELECT
    id_conjunto,
    data AS dia,
    sum(consumo_kwh) AS kwh_total,
    count(DISTINCT id_uc) AS ucs_com_leitura
  FROM ${catalogo}.${schema_silver}.consumo_diario
  GROUP BY id_conjunto, data
)
SELECT
  coalesce(coalesce(i.id_conjunto, c.id_conjunto), v.id_conjunto) AS id_conjunto,
  uc.nome_conjunto,
  uc.municipio,
  coalesce(coalesce(i.dia, c.dia), v.dia) AS dia,
  coalesce(i.interrupcoes, 0) AS interrupcoes,
  coalesce(round(i.horas_interrompidas, 2), 0) AS horas_interrompidas,
  coalesce(round(i.uc_horas_interrompidas, 1), 0) AS uc_horas_interrompidas,
  coalesce(c.chamados, 0) AS chamados,
  coalesce(c.chamados_negativos, 0) AS chamados_negativos,
  coalesce(c.mencoes_ouvidoria, 0) AS mencoes_ouvidoria,
  coalesce(c.chamados_risco_saude, 0) AS chamados_risco_saude,
  coalesce(c.chamados_urgencia_alta, 0) AS chamados_urgencia_alta,
  coalesce(round(v.kwh_total, 0), 0) AS kwh_total,
  coalesce(v.ucs_com_leitura, 0) AS ucs_com_leitura,
  coalesce(p.uc_prioridade_alta, 0) AS uc_prioridade_alta,
  CASE
    WHEN c.chamados_risco_saude > 0 THEN 'Visita ou contato imediato: ha clientes em risco a saude'
    WHEN c.mencoes_ouvidoria > 0 THEN 'Acionar ouvidoria e dar retorno ao cliente no mesmo dia'
    WHEN i.uc_horas_interrompidas > 0 THEN 'Acionar rede: interromper a causa antes do proximo ciclo; verificar conjuntos afetados'
    WHEN p.uc_prioridade_alta > 0 THEN 'Abrir inspecao tecnica nas UCs com queda e sinal no medidor'
    ELSE 'Monitorar' END AS acao_recomendada
FROM interrupcoes i
FULL OUTER JOIN chamados c
  ON c.id_conjunto = i.id_conjunto AND c.dia = i.dia
FULL OUTER JOIN consumo v
  ON v.id_conjunto = coalesce(i.id_conjunto, c.id_conjunto) AND v.dia = coalesce(i.dia, c.dia)
LEFT JOIN (
  SELECT id_conjunto, count_if(prioridade_inspecao = 'alta') AS uc_prioridade_alta
  FROM ${catalogo}.${schema_gold}.prioridade_inspecao_uc
  GROUP BY id_conjunto
) p ON p.id_conjunto = coalesce(coalesce(i.id_conjunto, c.id_conjunto), v.id_conjunto)
LEFT JOIN (
  SELECT id_conjunto, max(nome_conjunto) AS nome_conjunto, max(municipio) AS municipio
  FROM ${catalogo}.${schema_silver}.unidades_consumidoras
  GROUP BY id_conjunto
) uc ON uc.id_conjunto = coalesce(coalesce(i.id_conjunto, c.id_conjunto), v.id_conjunto)
