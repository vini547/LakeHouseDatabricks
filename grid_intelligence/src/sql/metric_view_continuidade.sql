-- A definicao unica de DEC e FEC do sistema (RN-04). Dashboard, agente e
-- relatorio consomem apenas daqui — nunca recalculam a divisao.
-- Tres armadilhas registradas:
-- 1. O corpo YAML fica dentro de $$ e NAO passa por substituicao de parametro;
--    CATALOGO e ESQUEMA sao posicionados antes, com USE CATALOG e USE SCHEMA.
-- 2. Nenhum ';' dentro do bloco $$, nem em prosa de comment: o executor de script
--    divide instrucoes pelo ';' e nao entende o literal $$. Redacao sem ';'.
-- 3. Ao agregar varios meses, o denominador se repete uma vez por mes e DEC de
--    somas devolve media mensal, nao acumulado; DEC Acumulado e Total de UCs
--    dividem pelo numero de meses distintos — DEC e DEC Acumulado NAO sao a mesma formula.
USE CATALOG IDENTIFIER(:catalogo);
USE SCHEMA IDENTIFIER(:schema_gold);

CREATE OR REPLACE VIEW continuidade_metricas
COMMENT 'Metricas de continuidade do fornecimento (DEC e FEC) por mes e conjunto. Serve tanto consulta operacional quanto acumulado do periodo. Fonte unica dos indicadores — nao recalcular a divisao fora daqui.'
WITH METRICS
LANGUAGE YAML
AS $$
version: 1.1
comment: "Metricas de DEC e FEC por conjunto e mes de apuracao"
source: continuidade_conjunto_mes
dimensions:
  - name: Conjunto
    expr: nome_conjunto
    comment: "Nome legivel do conjunto, subdivisao geografica da area de concessao"
    synonyms:
      - conjunto
      - regiao
      - distrito
      - area
  - name: Codigo do Conjunto
    expr: id_conjunto
    comment: "Codigo do conjunto"
    synonyms:
      - codigo do conjunto
      - sigla do conjunto
      - id conjunto
  - name: Municipio
    expr: municipio
    comment: "Municipio atravessado pelo conjunto"
    synonyms:
      - cidade
      - municipio
  - name: Mes
    expr: mes_apuracao
    comment: "Mes de apuracao dos indicadores"
    synonyms:
      - mes
      - mes de apuracao
      - competencia
      - periodo
measures:
  - name: DEC
    expr: SUM(uc_horas_interrompidas) / SUM(total_ucs)
    comment: "Quantas horas em media uma UC do conjunto ficou sem energia no recorte"
    synonyms:
      - dec
      - duracao equivalente de interrupcao
      - horas sem luz
      - horas sem energia
    format:
      type: number
      decimal_places:
        type: exact
        places: 2
  - name: FEC
    expr: SUM(uc_interrupcoes) / SUM(total_ucs)
    comment: "Quantas vezes em media uma UC do conjunto ficou sem energia no recorte"
    synonyms:
      - fec
      - frequencia equivalente de interrupcao
      - numero de interrupcoes
      - vezes sem luz
    format:
      type: number
      decimal_places:
        type: exact
        places: 2
  - name: DEC Acumulado
    expr: SUM(uc_horas_interrompidas) / (SUM(total_ucs) / COUNT(DISTINCT mes_apuracao))
    comment: "Quantas horas o conjunto deixou uma UC tipica sem energia no periodo acumulado"
    synonyms:
      - dec acumulado
      - dec acumulado do periodo
      - dec anual
      - total de horas sem energia
    format:
      type: number
      decimal_places:
        type: exact
        places: 2
  - name: Interrupcoes
    expr: SUM(qtd_interrupcoes)
    comment: "Numero de eventos de interrupcao no recorte"
    synonyms:
      - interrupcoes
      - numero de eventos
    format:
      type: number
      decimal_places:
        type: exact
        places: 0
  - name: Interrupcoes Climaticas
    expr: SUM(qtd_interrupcoes_climaticas)
    comment: "Eventos com causa climatica como tempestade e raio"
    synonyms:
      - climaticas
      - interrupcoes por tempo
      - eventos climaticos
    format:
      type: number
      decimal_places:
        type: exact
        places: 0
  - name: Interrupcoes Programadas
    expr: SUM(qtd_interrupcoes_programadas)
    comment: "Eventos programados com aviso previo ao consumidor"
    synonyms:
      - programadas
      - interrupcoes com aviso
      - manutencao programada
    format:
      type: number
      decimal_places:
        type: exact
        places: 0
  - name: Proporcao Climatica
    expr: SUM(qtd_interrupcoes_climaticas) / NULLIF(SUM(qtd_interrupcoes), 0)
    comment: "Parte dos eventos atribuida a causas climaticas"
    synonyms:
      - proporcao climatica
      - percentual climatico
      - participacao do clima
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 1
  - name: Horas UC Interrompidas
    expr: SUM(uc_horas_interrompidas)
    comment: "Soma das horas de interrupcao ponderadas pelas UCs afetadas"
    synonyms:
      - horas uc
      - horas interrompidas
      - horas-uci
    format:
      type: number
      decimal_places:
        type: exact
        places: 1
  - name: Maior Interrupcao
    expr: MAX(maior_duracao_horas)
    comment: "Duracao do pior evento de interrupcao do recorte em horas"
    synonyms:
      - maior interrupcao
      - pior evento
      - maior duracao
    format:
      type: number
      decimal_places:
        type: exact
        places: 2
  - name: Total de UCs
    expr: SUM(total_ucs) / COUNT(DISTINCT mes_apuracao)
    comment: "Numero medio de unidades consumidoras do conjunto no periodo"
    synonyms:
      - total de ucs
      - ucs do conjunto
      - unidades consumidoras
    format:
      type: number
      decimal_places:
        type: exact
        places: 0
$$
