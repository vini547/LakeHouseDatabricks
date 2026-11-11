-- RN-10: quem esta no atendimento ve nome, telefone e transcricao originais de bronze.chamados
-- (precisa do telefone para retornar a ligacao). Todo o resto ve [RESTRITO].
-- LIMITACAO: um full refresh do pipeline recria bronze.chamados e derruba as mascaras;
-- por isso esta task roda DEPOIS do pipeline, a cada execucao.
USE CATALOG IDENTIFIER(:catalogo);
USE SCHEMA IDENTIFIER(:schema_bronze);

CREATE OR REPLACE FUNCTION mascara_dado_pessoal(v STRING)
RETURNS STRING
RETURN CASE WHEN is_member('atendimento') THEN v ELSE '[RESTRITO]' END;

ALTER TABLE chamados ALTER COLUMN nome_solicitante SET MASK mascara_dado_pessoal;
ALTER TABLE chamados ALTER COLUMN telefone_solicitante SET MASK mascara_dado_pessoal;
ALTER TABLE chamados ALTER COLUMN transcricao SET MASK mascara_dado_pessoal;
