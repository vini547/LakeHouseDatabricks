-- Apenas eventos com 3 minutos ou mais entram aqui (RN-01):
-- abaixo disso o religador desarma e religa sozinho — galho na rede, desarme e
-- religamento automatico em segundos. O consumidor viu a luz piscar, nao ficou sem energia.
-- Os eventos curtos continuam na bronze; o limiar vem da configuration do pipeline.
CREATE OR REFRESH STREAMING TABLE ${catalogo}.${schema_silver}.interrupcoes_validas
TBLPROPERTIES ('delta.feature.timestampNtz' = 'supported')
AS SELECT
  id_interrupcao,
  id_conjunto,
  inicio,
  fim,
  duracao_minutos,
  tipo,
  causa,
  equipamento,
  qtd_ucs_afetadas,
  origem,
  ingerido_em,
  arquivo_origem,
  ingerido_bronze_em,
  _rescued_data,
  to_date(inicio) AS data_evento,
  to_date(date_trunc('MONTH', inicio)) AS mes_apuracao,
  duracao_minutos / 60.0 AS duracao_horas,
  duracao_minutos / 60.0 * qtd_ucs_afetadas AS uc_horas_interrompidas,
  causa = 'climatica' AS causa_climatica
FROM STREAM(${catalogo}.${schema_bronze}.interrupcoes)
WHERE duracao_minutos >= ${duracao_minima_interrupcao_min}
