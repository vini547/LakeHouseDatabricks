-- Teto fisico de consumo por classe de ligacao: acima disso a telemetria esta errada.
-- Definido aqui, no consumidor: quem recebe a medida estabelece o que e plausivel.
CREATE OR REFRESH MATERIALIZED VIEW ${catalogo}.${schema_silver}.consumo_diario
TBLPROPERTIES ('delta.feature.timestampNtz' = 'supported')
AS SELECT
  c.id_uc,
  c.data,
  c.consumo_kwh,
  c.horas_com_leitura,
  c.sinal_violacao_medidor,
  c.origem,
  c.ingerido_em,
  c.arquivo_origem,
  c.ingerido_bronze_em,
  c._rescued_data,
  u.id_conjunto,
  u.nome_conjunto,
  u.bairro,
  u.classe_consumo
FROM ${catalogo}.${schema_bronze}.consumo_diario c
JOIN ${catalogo}.${schema_silver}.unidades_consumidoras u ON u.id_uc = c.id_uc
WHERE c.consumo_kwh IS NOT NULL
  AND c.consumo_kwh > 0
  AND c.consumo_kwh <= CASE lower(trim(u.classe_consumo))
    WHEN 'residencial'   THEN 500
    WHEN 'rural'          THEN 1500
    WHEN 'poder_publico'  THEN 6000
    WHEN 'comercial'      THEN 2500
    WHEN 'industrial'     THEN 20000
    ELSE 50000 END
QUALIFY row_number() OVER (PARTITION BY c.id_uc, c.data ORDER BY c.ingerido_em DESC) = 1;

-- Baseline de consumo ancorado na maior data do dataset (nunca em current_date()):
-- a janela recente sao os ultimos 30 dias; a baseline os 90 dias imediatamente anteriores.
-- Baseline sobre toda a serie acusaria alta de ~50% em qualquer UC, porque a carga cresce
-- ~30% ao ano — a comparacao precisa de janelas comparaveis.
CREATE OR REFRESH MATERIALIZED VIEW ${catalogo}.${schema_silver}.baseline_consumo
AS
SELECT
  id_uc,
  id_conjunto,
  nome_conjunto,
  bairro,
  classe_consumo,
  consumo_medio_baseline_kwh,
  dias_no_baseline,
  consumo_medio_recente_kwh,
  dias_no_periodo_recente,
  (consumo_medio_recente_kwh - consumo_medio_baseline_kwh) / nullif(consumo_medio_baseline_kwh, 0) AS variacao_da_uc,
  avg(consumo_medio_baseline_kwh) OVER w AS consumo_medio_conjunto_baseline_kwh,
  avg(consumo_medio_recente_kwh) OVER w AS consumo_medio_conjunto_recente_kwh,
  (avg(consumo_medio_recente_kwh) OVER w - avg(consumo_medio_baseline_kwh) OVER w)
    / nullif(avg(consumo_medio_baseline_kwh) OVER w, 0) AS variacao_do_conjunto
FROM (
  SELECT
    u.id_uc,
    u.id_conjunto,
    u.nome_conjunto,
    u.bairro,
    u.classe_consumo,
    avg(c.consumo_kwh) FILTER (WHERE c.data BETWEEN d.inicio_baseline AND d.fim_baseline) AS consumo_medio_baseline_kwh,
    count(*) FILTER (WHERE c.data BETWEEN d.inicio_baseline AND d.fim_baseline) AS dias_no_baseline,
    avg(c.consumo_kwh) FILTER (WHERE c.data BETWEEN d.inicio_recente AND d.fim_recente) AS consumo_medio_recente_kwh,
    count(*) FILTER (WHERE c.data BETWEEN d.inicio_recente AND d.fim_recente) AS dias_no_periodo_recente
  FROM ${catalogo}.${schema_silver}.unidades_consumidoras u
  JOIN ${catalogo}.${schema_silver}.consumo_diario c ON c.id_uc = u.id_uc
  CROSS JOIN (
    SELECT
      max(data) AS fim_recente,
      max(data) - INTERVAL 29 DAYS AS inicio_recente,
      max(data) - INTERVAL 30 DAYS AS fim_baseline,
      max(data) - INTERVAL 119 DAYS AS inicio_baseline
    FROM ${catalogo}.${schema_silver}.consumo_diario
  ) d
  GROUP BY u.id_uc, u.id_conjunto, u.nome_conjunto, u.bairro, u.classe_consumo
)
WINDOW w AS (PARTITION BY id_conjunto)
