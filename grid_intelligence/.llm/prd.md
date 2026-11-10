# Grid Intelligence — PRD

> Documento de referência do projeto. Todos os prompts seguintes (01 a 07) consultam este arquivo.
> Última atualização: prompt 00 — setup.

## 1. Visão geral

**Grid Intelligence** é a plataforma de dados e IA da **Luz do Vale Distribuidora S.A.**, uma
distribuidora de energia elétrica fictícia, operando sob regulação da ANEEL. O projeto é construído
ao vivo, em aula, em 8 etapas (prompts 00 a 07), cada uma entregando uma feature completa com
deploy e resultado visível.

| # | Prompt | Entrega |
|---|---|---|
| 00 | Setup e planejamento | Este documento, catálogos, schemas e volume |
| 01 | Camada bronze | Ingestão fiel do volume, sem regra de negócio |
| 02 | Silver — os números | Cadastro limpo, a regra dos 3 minutos, dedup e baseline |
| 03 | Silver — o texto | Anonimização e enriquecimento das transcrições |
| 04 | Camada gold | As quatro entregas de negócio e a metric view de DEC/FEC |
| 05 | Dashboard | Painel AI/BI sobre a gold |
| 06 | Agente | Copiloto conversacional em português |
| 07 | Relatório e demonstração | Relatório executivo e as queries que provam tudo |

## 2. Contexto de negócio — três dores mensuráveis

1. **Continuidade do fornecimento.** Interromper além do limite regulatório gera compensação
   financeira automática ao consumidor. Em 2024 as distribuidoras brasileiras pagaram mais de
   R$ 1,1 bilhão em compensações.
2. **Perdas não técnicas.** Energia distribuída e não faturada — furto, fraude e erro de
   medição. Em 2025 somaram ~R$ 11,5 bilhões, dos quais ~R$ 7,9 bilhões foram repassados
   à tarifa.
3. **Atendimento ao cliente.** Milhares de ligações viram transcrição e ninguém lê. Dentro
   delas está o aviso antecipado da reclamação na ouvidoria.

## 3. Glossário — use estes termos, sem sinônimo aproximado

| Termo | Definição |
|---|---|
| **UC — Unidade Consumidora** | O ponto de entrega de energia. **Não é sinônimo de cliente**: um cliente pode ter várias UCs |
| **Conjunto** | Subdivisão geográfica da área de concessão. É a unidade de agregação do regulador |
| **DEC** | Duração Equivalente de Interrupção por UC — tempo médio, em horas, sem fornecimento |
| **FEC** | Frequência Equivalente de Interrupção por UC — número médio de interrupções |
| **PNT** | Perdas Não Técnicas |
| **Prioridade de inspeção** | Classificação de quanto uma UC merece visita técnica |

## 4. Regras de negócio

> **Nota de completude:** o prompt 00 define dez regras, numeradas até RN-14. As regras
> **RN-02, RN-03, RN-05 e RN-08 não foram definidas** e **não são inventadas aqui** — serão
> fixadas nos prompts em que se aplicarem (01 a 04). Enquanto isso, a numeração é preservada
> para não renumerar o documento depois.

- **RN-01** — Só interrupções com **3 minutos ou mais** entram na apuração de DEC e FEC.
  A regra vive na camada de transformação, nunca no relatório.
- **RN-04** — DEC e FEC têm **uma única definição** no sistema, consumida por dashboard,
  agente e relatório.
- **RN-06** — Uma UC é candidata a inspeção quando o consumo cai em **dois eixos
  simultâneos**: contra o próprio baseline **e** enquanto a vizinhança permanece estável.
  Só o primeiro eixo apontaria o bairro inteiro depois de um apagão.
- **RN-07** — A saída da detecção é **prioridade de inspeção** — alta, média, baixa.
  **Nunca** um rótulo de fraude, furto ou culpa. Queda de consumo também é mudança de
  morador, imóvel desocupado, defeito de medidor e erro de leitura. Em setor regulado a
  diferença é jurídica. Nenhuma coluna, variável ou comentário do projeto pode usar as
  palavras "fraude", "furto" ou "culpado" como rótulo de saída.
- **RN-09** — Dado pessoal em transcrição é **mascarado antes** de qualquer análise de
  conteúdo.
- **RN-10** — O texto original identificado é preservado com **acesso restrito**. Duas
  proteções que coexistem: uma na leitura, outra na análise.
- **RN-11** — A camada de ingestão **não filtra, não corrige e não aplica regra de
  negócio**. Leitura inválida de medidor é um fato sobre o medidor. Filtrar na ingestão
  parece limpeza; é destruição de evidência.
- **RN-12** — Todo registro ingerido carrega origem e momento de ingestão.
- **RN-13** — O agente conversacional acessa **apenas a camada de negócio**.
- **RN-14** — As entidades da **camada gold** carregam descrição em linguagem de negócio —
  é o que o agente lê. Bronze e silver não precisam: são passagem.

## 5. Modelo de informação

### 5.1 Bases de origem (sintéticas, em Parquet)

Quatro bases, quatro anos de histórico, crescimento de **30% ao ano** na carga e
**sazonalidade de verão** no atendimento (dezembro a março recebem quase o dobro de
ligações).

| Base | Grão | Volume |
|---|---|---|
| `unidades_consumidoras` | uma por ponto de entrega | 4.000 |
| `interrupcoes` | uma por evento de rede | 1.383 |
| `consumo_diario` | uma por UC por dia | ~5,85 milhões (4 anos) |
| `chamados` | uma por ligação, com transcrição | 2.801 |

O dataset carrega **defeitos propositais** — consumo nulo, negativo, fisicamente impossível,
linhas duplicadas e interrupções abaixo de 3 minutos. **Não são bug**: existem para as
validações de qualidade e a RN-01 terem o que fazer.

### 5.2 Contrato de pastas no volume

Uma pasta por base, com um único arquivo Parquet dentro — inclusive `consumo_diario`, com
5,85 milhões de linhas. É a **pasta**, e não o arquivo, que é o contrato com a camada bronze:
se um dia uma base precisar ser particionada, o pipeline não muda.

```
/Volumes/<catalogo>/raw/landing/unidades_consumidoras/
/Volumes/<catalogo>/raw/landing/interrupcoes/
/Volumes/<catalogo>/raw/landing/consumo_diario/
/Volumes/<catalogo>/raw/landing/chamados/
```

### 5.3 Camadas

| Camada | Papel | Regra |
|---|---|---|
| `raw` | Pouso dos arquivos (volume `raw.landing`) | Nenhuma transformação |
| `bronze` | Ingestão fiel do volume | **Não filtra, não corrige, não aplica regra de negócio** (RN-11). Todo registro carrega origem e momento de ingestão (RN-12) |
| `silver` | Dados limpos e enriquecidos | Regra dos 3 minutos (RN-01), dedup, baseline por UC, mascaramento de transcrições (RN-09, RN-10) |
| `gold` | Entregas de negócio, com descrição em linguagem de negócio (RN-14) | Única definição de DEC/FEC (RN-04). Consumida por dashboard, agente e relatório (RN-13) |

Um schema por camada — o nome do schema já é a camada; as tabelas dentro dele não repetem o
prefixo (`bronze.chamados`, nunca `bronze_chamados`).

### 5.4 Ambientes — isolamento por catálogo

| Ambiente | Catálogo | Quem usa |
|---|---|---|
| `dev` | `grid_dev` | desenvolvimento, no dia a dia |
| `prod` | `grid_intelligence` | o ambiente final, depois de validado em dev |

Os schemas mantêm os nomes exatos `raw`, `bronze`, `silver` e `gold` nos dois ambientes, para
que o mesmo SQL rode em qualquer ambiente sem uma linha diferente. **O catálogo é a única
coisa que o bundle não cria** — é recurso de conta, criado por SQL antes do deploy.

Catálogo vem de `${var.catalog}` no `databricks.yml`; schema vem de
`${resources.schemas.<camada>.name}`. Nunca escritos literalmente fora do `databricks.yml`
(onde a variável recebe o valor) e do `resources/grid_schemas.yml` (onde os schemas são
definidos).

## 6. As quatro entregas de negócio previstas

> Síntese a partir do contexto do prompt 00 — as dores mapeadas nas três frentes, mais a
> camada de acesso (agente/relatório). Se a numeração mudar num prompt seguinte, este
> documento é atualizado junto.

1. **Continuidade do fornecimento** — DEC e FEC apurados por conjunto, com a regra dos
   3 minutos (RN-01), definição única (RN-04) e metric view consumível. Alimenta a leitura
   regulatória e o cálculo de compensação (R$ 1,1 bilhão em 2024 no setor).
2. **Perdas não técnicas** — detecção por dois eixos simultâneos (baseline da própria UC +
   vizinhança estável, RN-06), com saída exclusivamente como **prioridade de inspeção**
   alta/média/baixa (RN-07). Nunca rótulo de fraude, furto ou culpa.
3. **Atendimento ao cliente** — transcrições mascaradas antes da análise (RN-09), texto
   original preservado com acesso restrito (RN-10), sinalização do aviso antecipado da
   reclamação na ouvidoria.
4. **Acesso ao negócio** — copiloto conversacional em português sobre a camada gold
   (RN-13, RN-14), com a gold descrita em linguagem de negócio, mais dashboard AI/BI e
   relatório executivo (prompts 05 a 07).

## 7. Convenções obrigatórias

- Todo texto e todo nome em **português do Brasil**; nomes de entidades, colunas e
  arquivos **sem acentuação**.
- **Nenhum nome de catálogo fixado em código.** Catálogo vem de `${var.catalog}`;
  schema vem de `${resources.schemas.<camada>.name}`.
- **Nenhum nome de modelo de IA fixado no código.** Usar as funções `ai_*` do Databricks.
- Perfil da CLI: `grid_intelligence`. Todo comando leva `--profile grid_intelligence`.

## 8. Diretriz de simplicidade — vale para todos os prompts

Este projeto é construído **ao vivo, em aula**. Código que ninguém consegue ler na tela em
dez segundos não serve, mesmo que seja mais robusto.

- **Sem expectations e sem `CONSTRAINT`** nas tabelas. Regra de negócio vira `WHERE`.
- **Sem `COMMENT` em bronze e silver.** Só a **gold** e a **metric view** levam descrição
  (RN-14).
- **Sem `TBLPROPERTIES`, `CLUSTER BY` e afins**, a menos que sem eles quebre.
- **Sem tratamento de caso que o dataset não tem.**
- **Um `SELECT` direto vence um `WITH` de quatro CTEs.**

Comentário no código só onde a decisão **não é óbvia pelo código**. Se algo parecer pedir
validação extra, ela **não** deve ser acrescentada sem decisão explícita.

## 9. Fora de escopo do prompt 00

Não construir agora — cada item tem seu prompt: transformação (01–03), camada gold e
metric view (04), dashboard (05), agente (06), relatório e demonstração (07).
