-- Prioridade de inspecao por UC: dois eixos (caiu contra o proprio baseline E
-- vizinhanca estavel) + sinal fisico no medidor como agravante. A saida e sempre
-- prioridade alta/media/baixa, nunca acusacao — queda de consumo tambem e mudanca
-- de morador, imovel desocupado, defeito de medidor e erro de leitura.
CREATE OR REFRESH MATERIALIZED VIEW ${catalogo}.${schema_gold}.prioridade_inspecao_uc
COMMENT 'UCs candidatas a visita tecnica, em prioridade de inspecao (alta, media, baixa). Resultado de regra explicavel linha a linha — nunca uma acusacao.'
AS
SELECT
  id_uc,
  id_conjunto,
  nome_conjunto,
  bairro,
  classe_consumo,
  CASE
    WHEN atende_os_dois_eixos AND sinal_violacao_recente THEN 'alta'
    WHEN atende_os_dois_eixos THEN 'media'
    WHEN sinal_violacao_recente THEN 'media'
    ELSE 'baixa' END AS prioridade_inspecao,
  caiu_contra_si,
  vizinhanca_estavel,
  atende_os_dois_eixos,
  sinal_violacao_recente,
  round(variacao_da_uc, 4) AS variacao_da_uc,
  round(variacao_do_conjunto, 4) AS variacao_do_conjunto,
  round(consumo_medio_baseline_kwh, 2) AS consumo_medio_baseline_kwh,
  round(consumo_medio_recente_kwh, 2) AS consumo_medio_recente_kwh,
  dias_no_baseline,
  dias_no_periodo_recente,
  concat(
    'Consumo da UC caiu ', format_number(-variacao_da_uc * 100, 1), '% contra o proprio baseline (',
    format_number(consumo_medio_baseline_kwh, 1), ' -> ', format_number(consumo_medio_recente_kwh, 1), ' kWh/dia), ',
    CASE WHEN vizinhanca_estavel
         THEN 'com a vizinhanca estavel'
         ELSE concat('com a vizinhanca variando ', format_number(variacao_do_conjunto * 100, 1), '%') END,
    CASE WHEN sinal_violacao_recente
         THEN '; sinal registrado no medidor no periodo'
         ELSE '' END
  ) AS motivo_observado
FROM (
  SELECT
    b.*,
    coalesce(s.sinais_recentes, 0) > 0 AS sinal_violacao_recente,
    b.variacao_da_uc <= -${eixo1_queda_minima_uc} AS caiu_contra_si,
    abs(b.variacao_do_conjunto) <= ${eixo2_faixa_estavel_conjunto} AS vizinhanca_estavel,
    b.variacao_da_uc <= -${eixo1_queda_minima_uc}
      AND abs(b.variacao_do_conjunto) <= ${eixo2_faixa_estavel_conjunto} AS atende_os_dois_eixos
  FROM ${catalogo}.${schema_silver}.baseline_consumo b
  LEFT JOIN (
    SELECT id_uc, count_if(sinal_violacao_medidor) AS sinais_recentes
    FROM ${catalogo}.${schema_silver}.consumo_diario
    WHERE data > (SELECT max(data) - INTERVAL 30 DAYS FROM ${catalogo}.${schema_silver}.consumo_diario)
    GROUP BY id_uc
  ) s ON s.id_uc = b.id_uc
)
WHERE caiu_contra_si OR sinal_violacao_recente
