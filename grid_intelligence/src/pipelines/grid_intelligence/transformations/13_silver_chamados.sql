-- Extracao por REGRA, nao por modelo. O que esta rota NAO pega:
-- - ironia e negacao ("que otimo, mais um dia sem luz" vira positive)
-- - sinonimo fora da lista ("fiquei no breu" nao casa com 'escuro|sem luz')
-- - motivo composto (falta de energia E conta alta recebe um rotulo so)
-- - nome escrito diferente da coluna (apelido no texto passa identificado)
--   -> este ultimo e risco de LGPD, nao de qualidade: medir e reportar
CREATE OR REFRESH MATERIALIZED VIEW ${catalogo}.${schema_silver}.chamados_anonimizados
TBLPROPERTIES ('delta.feature.timestampNtz' = 'supported')
AS SELECT
  c.id_chamado,
  c.id_uc,
  u.id_cliente,
  u.id_conjunto,
  u.nome_conjunto,
  u.bairro,
  u.classe_consumo,
  CAST(c.abertura AS DATE) AS data_chamado,
  date_format(c.abertura, 'HH:mm') AS hora_chamado,
  c.abertura,
  c.canal,
  regexp_replace(
    regexp_replace(
      replace(c.transcricao, c.nome_solicitante, '[MASCARADO]'),
      '[0-9]{3}\\.[0-9]{3}\\.[0-9]{3}-[0-9]{2}',
      '[MASCARADO]'),
    '\\([0-9]{2}\\)\\s*9?[0-9]{4}-?[0-9]{4}',
    '[MASCARADO]') AS transcricao_anonimizada,
  'regras_de_texto' AS anonimizado_por,
  c.origem,
  c.ingerido_em,
  c.arquivo_origem,
  c.ingerido_bronze_em
FROM ${catalogo}.${schema_bronze}.chamados c
JOIN ${catalogo}.${schema_silver}.unidades_consumidoras u ON u.id_uc = c.id_uc;

CREATE OR REFRESH MATERIALIZED VIEW ${catalogo}.${schema_silver}.chamados_enriquecidos
TBLPROPERTIES ('delta.feature.timestampNtz' = 'supported')
AS
SELECT *,
  CASE WHEN risco_a_saude THEN 'alta'
       WHEN motivo IN ('falta_energia', 'religacao_urgente', 'poste_avariado') THEN 'media'
       ELSE 'baixa' END AS urgencia
FROM (
  SELECT *,
    CASE WHEN transcricao_anonimizada RLIKE '(?i)dialise|oxigenio|remedio|crianca|hospital|faisca|incendio|idoso'
           THEN 'religacao_urgente'
         WHEN transcricao_anonimizada RLIKE '(?i)escuro|sem energia|apagou|falta de energia|sem luz'
           THEN 'falta_energia'
         WHEN transcricao_anonimizada RLIKE '(?i)piscando|oscila|queimou|tensao'
           THEN 'oscilacao_tensao'
         WHEN transcricao_anonimizada RLIKE '(?i)releitura|estimativa|nao bate'
           THEN 'erro_leitura'
         WHEN transcricao_anonimizada RLIKE '(?i)conta veio|dobro|fatura subiu|trezentos reais'
           THEN 'fatura_alta'
         WHEN transcricao_anonimizada RLIKE '(?i)poste|galho|lampada da rua'
           THEN 'poste_avariado'
         WHEN transcricao_anonimizada RLIKE '(?i)religacao|religar|paguei'
           THEN 'religacao'
         ELSE 'duvida_cadastral' END AS motivo,
    (transcricao_anonimizada RLIKE '(?i)dialise|oxigenio|remedio|crianca|hospital|faisca|incendio|idoso') AS risco_a_saude,
    (transcricao_anonimizada RLIKE '(?i)ouvidoria|aneel|procon|processo') AS ameacou_ouvidoria,
    nullif(regexp_extract(transcricao_anonimizada, '(?i)medidor|transformador|poste|cabo|fio|disjuntor|quadro|padrao|lampada', 0), '') AS equipamento_citado,
    CASE WHEN transcricao_anonimizada RLIKE '(?i)insatisf|revolt|irrit|pessimo|horrivel|absurdo|infelizmente|nao funciona|reclam'
           THEN 'negative'
         WHEN transcricao_anonimizada RLIKE '(?i)obrigad|agrade|excelente|perfeito|rapido|otimo|bom atendimento'
           THEN 'positive'
         ELSE 'neutral' END AS sentimento,
    'regras_de_texto' AS enriquecido_por
  FROM ${catalogo}.${schema_silver}.chamados_anonimizados
)
