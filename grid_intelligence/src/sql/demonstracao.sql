-- Demonstracao — as oito afirmacoes que o projeto faz, com o resultado esperado.
-- Rode cada bloco contra a gold (e a bronze, quando indicado).
-- ${catalogo} = o catalogo do ambiente (grid_dev em dev, grid_intelligence em prod).

-- 1) RN-01 tem efeito — 1.383 na bronze contra 1.073 na silver (310 descartadas, 22,4%)
SELECT 'bronze' AS camada, count(*) AS interrupcoes FROM ${catalogo}.bronze.interrupcoes
UNION ALL
SELECT 'silver', count(*) FROM ${catalogo}.silver.interrupcoes_validas;

-- 2) A qualidade tem efeito — por motivo de descarte
SELECT 'bronze (total)' AS origem, count(*) AS linhas FROM ${catalogo}.bronze.consumo_diario
UNION ALL
SELECT '  nulo', count_if(consumo_kwh IS NULL) FROM ${catalogo}.bronze.consumo_diario
UNION ALL
SELECT '  negativo', count_if(consumo_kwh < 0) FROM ${catalogo}.bronze.consumo_diario
UNION ALL
SELECT '  acima do teto fisico por classe', count_if(consumo_kwh > CASE lower(trim(u.classe_consumo))
  WHEN 'residencial' THEN 500 WHEN 'rural' THEN 1500 WHEN 'poder_publico' THEN 6000
  WHEN 'comercial' THEN 2500 WHEN 'industrial' THEN 20000 ELSE 50000 END)
FROM ${catalogo}.bronze.consumo_diario c JOIN ${catalogo}.bronze.unidades_consumidoras u USING (id_uc)
UNION ALL
SELECT '  chaves duplicadas na bronze', count(*) - count(DISTINCT id_uc, data) FROM ${catalogo}.bronze.consumo_diario
UNION ALL
SELECT 'silver (depois de tudo)', count(*) FROM ${catalogo}.silver.consumo_diario;
-- Esperado: descarte = 23.478 + 8.799 + 2.384 + chaves duplicadas; silver = 5.805.424

-- 3) RN-04 e real — DEC vem da metric view e bate com o calculo manual
SELECT 'metric view' AS fonte, `Conjunto`, MEASURE(`DEC`) AS dec
FROM ${catalogo}.gold.continuidade_metricas
GROUP BY ALL ORDER BY `Conjunto`;

SELECT 'manual' AS fonte, id_conjunto, sum(uc_horas_interrompidas) / sum(total_ucs) AS dec
FROM ${catalogo}.gold.continuidade_conjunto_mes
GROUP BY id_conjunto ORDER BY id_conjunto;
-- Esperado: os dois batem conjunto a conjunto (media por mes)

-- 4) Os dois eixos funcionam — prioridade alta com as duas variacoes lado a lado
SELECT id_uc, bairro, variacao_da_uc, variacao_do_conjunto, consumo_medio_baseline_kwh, consumo_medio_recente_kwh
FROM ${catalogo}.gold.prioridade_inspecao_uc
WHERE prioridade_inspecao = 'alta'
ORDER BY variacao_da_uc;
-- Esperado: 22 UCs; variacao_da_uc bem negativa (abaixo de -20%), vizinhanca entre -10% e +10%

-- 5) A anonimizacao funciona — uma transcricao dos dois lados
SELECT b.transcricao AS bronze, a.transcricao_anonimizada AS silver
FROM ${catalogo}.bronze.chamados b
JOIN ${catalogo}.silver.chamados_anonimizados a USING (id_chamado)
WHERE contains(b.transcricao, 'CPF')
LIMIT 2;

-- 6) O evento narrativo esta la — chamados por hora na noite da cascata vs outros dias
SELECT CAST(abertura AS DATE) AS dia, count(*) AS chamados_21_23
FROM ${catalogo}.bronze.chamados
WHERE HOUR(abertura) BETWEEN 21 AND 23
GROUP BY 1 ORDER BY 1 DESC LIMIT 5;
-- Esperado: 2026-07-30 com ~14 contra 1-2 nos demais dias

SELECT date_format(abertura, 'HH') AS hora, count(*) AS chamados
FROM ${catalogo}.bronze.chamados
WHERE CAST(abertura AS DATE) = DATE '2026-07-30'
GROUP BY 1 ORDER BY 1;
-- Esperado: pico as 21-23h (caso a noite da cascata de 2026-07-30: interrupcao de 1.398 UCxh)

-- 7) A tendencia esta la — consumo por ano, ~30% de crescimento ao ano
SELECT year(data) AS ano, round(sum(consumo_kwh) / 1e6, 1) AS milhoes_kwh
FROM ${catalogo}.silver.consumo_diario
GROUP BY 1 ORDER BY 1;
-- Esperado: 2022 ~25 (ano parcial), 2023 70.6, 2024 91.8 (+30%), 2025 118.8 (+29%), 2026 parcial

-- 8) A sazonalidade esta la — chamados por mes, verao perto do dobro
SELECT month(abertura) AS mes, count(*) AS chamados
FROM ${catalogo}.bronze.chamados
GROUP BY 1 ORDER BY 1;
-- Esperado: dez (335), jan (376), fev (317), mar (338) vs ~150-210 no resto do ano
