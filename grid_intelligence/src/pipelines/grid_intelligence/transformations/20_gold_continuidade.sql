CREATE OR REFRESH MATERIALIZED VIEW ${catalogo}.${schema_gold}.continuidade_conjunto_mes
COMMENT 'Insumos aditivos de DEC e FEC por conjunto e mes de apuracao. A definicao do indicador vive na metric view continuidade_metricas; esta tabela so guarda as somas (RN-04).'
AS
SELECT
  i.id_conjunto,
  uc.nome_conjunto,
  uc.municipio,
  i.mes_apuracao,
  uc.total_ucs,
  sum(i.uc_horas_interrompidas) AS uc_horas_interrompidas,
  sum(i.qtd_ucs_afetadas) AS uc_interrupcoes,
  count(*) AS qtd_interrupcoes,
  count_if(i.causa_climatica) AS qtd_interrupcoes_climaticas,
  count_if(i.tipo = 'programada') AS qtd_interrupcoes_programadas,
  max(i.duracao_horas) AS maior_duracao_horas
FROM ${catalogo}.${schema_silver}.interrupcoes_validas i
JOIN (
  SELECT
    id_conjunto,
    count(*) AS total_ucs,
    max(nome_conjunto) AS nome_conjunto,
    max(municipio) AS municipio
  FROM ${catalogo}.${schema_silver}.unidades_consumidoras
  GROUP BY id_conjunto
) uc ON uc.id_conjunto = i.id_conjunto
GROUP BY i.id_conjunto, i.mes_apuracao, uc.nome_conjunto, uc.municipio, uc.total_ucs
