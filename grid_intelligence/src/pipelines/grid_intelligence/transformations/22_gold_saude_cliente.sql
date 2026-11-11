CREATE OR REFRESH MATERIALIZED VIEW ${catalogo}.${schema_gold}.saude_cliente
TBLPROPERTIES ('delta.feature.timestampNtz' = 'supported')
COMMENT 'Visao por cliente (nao por UC) de quem esta em rota de reclamacao na ouvidoria. Mencoes a ouvidoria ANEEL ou Procon pesam primeiro; reincidencia com tom negativo e risco a saude vem logo atras. Fala transcrita sempre no texto anonimizado (RN-09).'
AS
SELECT
  id_cliente,
  max(id_conjunto) AS id_conjunto,
  max(nome_conjunto) AS nome_conjunto,
  max(bairro) AS bairro,
  count(*) AS qtd_chamados,
  count(DISTINCT id_uc) AS qtd_ucs_com_chamado,
  count_if(sentimento = 'negative') AS qtd_chamados_negativos,
  count_if(sentimento = 'negative') / count(*) AS proporcao_negativa,
  count_if(ameacou_ouvidoria) AS qtd_mencoes_ouvidoria,
  count_if(risco_a_saude) AS qtd_chamados_risco_saude,
  count_if(urgencia = 'alta') AS qtd_urgencia_alta,
  count_if(abertura >= d.fim - INTERVAL 30 DAYS) >= 3 AS reincidente,
  mode(motivo) AS motivo_predominante,
  max_by(equipamento_citado, abertura) AS ultimo_equipamento_citado,
  max_by(transcricao_anonimizada, abertura) AS ultima_fala,
  min(abertura) AS primeiro_chamado_em,
  max(abertura) AS ultimo_chamado_em,
  CASE
    WHEN count_if(ameacou_ouvidoria) > 0 OR count_if(risco_a_saude) > 0 THEN 'alto'
    WHEN count_if(abertura >= d.fim - INTERVAL 30 DAYS) >= 3 AND count_if(sentimento = 'negative') > 0 THEN 'medio'
    ELSE 'baixo' END AS risco_ouvidoria
FROM ${catalogo}.${schema_silver}.chamados_enriquecidos
CROSS JOIN (SELECT max(abertura) AS fim FROM ${catalogo}.${schema_silver}.chamados_enriquecidos) d
GROUP BY id_cliente
