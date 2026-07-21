# Evaluations — qualidade das respostas do Copilot (dt-evals)

Os pilares anteriores (FinOps, SRE, Adoção) respondem "quanto custou" e "quão rápido
foi". Este documento cobre um quinto pilar, opcional: **a resposta do Copilot foi boa?**

Isso é feito com [`dt-evals`](https://github.com/dynatrace-oss/dt-evals), toolkit
open-source da Dynatrace que roda um **LLM-as-judge** sobre os spans `gen_ai.*` já
capturados por este projeto e grava o resultado de volta no Dynatrace como bizevent.
Não precisa trocar nada na captura do Copilot — ele lê os spans que o coletor já
está recebendo (ver [01-arquitetura.md](01-arquitetura.md)).

Dashboard de referência (dados de exemplo, tenant público da Dynatrace):
https://wkf10640.apps.dynatrace.com/ui/apps/dynatrace.dashboards/dashboard/monaco-2cf9a79b-8b32-3244-aed1-e9d8c6e3e6a8

## Como funciona

```mermaid
flowchart LR
    Col[OTel Collector<br/>já existente] -->|gen_ai.* spans| DT[(Dynatrace Grail)]
    DT -->|fetch spans<br/>DQL read| Evals[dt-evals CLI<br/>LLM judge]
    Evals -->|bizevent<br/>gen_ai.evaluation.result| DT
    DT --> Dash[Dashboard /<br/>Notebook]
```

`dt-evals` não fica no caminho do Copilot Chat: ele roda **fora**, sob demanda ou
agendado, lendo spans recentes via DQL e escrevendo os scores como bizevents.

## Setup

Requer Node.js ≥20 e um judge provider (OpenAI, Anthropic, Google, Bedrock ou Azure
OpenAI) — usar o mesmo provider que a Boa Vista já aprovou é o caminho mais simples.

```bash
npx @dynatrace-oss/dt-evals doctor      # cria/valida o platform token do Dynatrace
npx @dynatrace-oss/dt-evals configure   # aponta pro tenant e pro judge provider
npx @dynatrace-oss/dt-evals run --since 2h --sample 20
```

O token do Dynatrace usado pelo `dt-evals` é **diferente** do `DT_INGEST_TOKEN` do
collector (ver [06-troubleshooting.md](06-troubleshooting.md)): precisa de escopos de
leitura de spans e leitura/escrita de bizevents — `dt-evals doctor create-token` já
gera o token com o escopo certo.

Para rodar continuamente (em vez de manual), `dt-evals schedule add` ou `dt-evals
deploy --provider aws|gcp|azure` — ver README do projeto para detalhes de deploy.

## Schema do evento gravado no Dynatrace

Cada avaliação vira um bizevent `gen_ai.evaluation.result`, com estes campos (são os
mesmos usados pelos filtros do dashboard `dt-evals`: Service, Provider, JudgeModel,
Metric, EvalType, ScoreLabel, RunId):

| Campo no evento | Filtro no dashboard | Exemplo |
|---|---|---|
| `dt.service.name` | Service | `copilot-chat` |
| `gen_ai.provider.name` | Provider | `openai` (provider do **judge**, não do Copilot) |
| `gen_ai.request.model` | JudgeModel | `gpt-4.1` |
| `gen_ai.evaluation.name` | Metric | `faithfulness`, `relevance`, `user-frustration` |
| `gen_ai.evaluation.type` | EvalType | `ready_made` ou `custom` |
| `gen_ai.evaluation.score.label` | ScoreLabel | `pass` / `fail` |
| `dt.eval.run_id` | RunId | id do batch de `dt-evals run` |
| `gen_ai.evaluation.score.value` | — | número (0–1, 0–5, 0–10 ou 0–100 conforme `scoring_format`) |
| `trace_id` / `span_id` | — | permite clicar do score direto para o trace original do Copilot |

## DQL — validação e análises

Rode no Notebook do tenant, igual às queries de [05-dql-queries.md](05-dql-queries.md).

### Sanity check — evals estão chegando?

```dql
fetch bizevents, from:now()-24h
| filter event.type == "gen_ai.evaluation.result"
| summarize count = count() by gen_ai.evaluation.name, gen_ai.evaluation.score.label
```

### Score médio por métrica (últimas 24h)

```dql
fetch bizevents, from:now()-24h
| filter event.type == "gen_ai.evaluation.result"
| summarize avg_score = avg(gen_ai.evaluation.score.value),
            evaluations = count(),
            pass_rate = countIf(gen_ai.evaluation.score.label == "pass") * 100.0 / count()
  by gen_ai.evaluation.name
| sort avg_score asc
```

### Taxa de falha por modelo do Copilot avaliado

Junta os scores (bizevents) com o span original do Copilot (via `trace_id`) para saber
**qual modelo do Copilot** gerou as respostas reprovadas — não confundir com
`gen_ai.request.model` do bizevent, que aqui é o modelo do *judge*.

```dql
fetch bizevents, from:now()-24h
| filter event.type == "gen_ai.evaluation.result"
| filter isNotNull(trace_id)
| join [
    fetch spans, from:now()-24h
    | filter gen_ai.provider.name == "github" and span.name == "chat"
    | fields trace_id, copilot_model = gen_ai.request.model
  ], on:{trace_id}, kind:leftOuter
| summarize evaluations = count(),
            fails = countIf(gen_ai.evaluation.score.label == "fail")
  by copilot_model, gen_ai.evaluation.name
| fieldsAdd fail_rate = round(toDouble(fails) / toDouble(evaluations) * 100, 1)
| sort fail_rate desc
```

### Drift — score ao longo do tempo por run

```dql
timeseries avg_score = avg(gen_ai.evaluation.score.value),
  by:{gen_ai.evaluation.name}, from:now()-7d, interval:1h,
  filter:{event.type == "gen_ai.evaluation.result"}
```

## LGPD

`dt-evals` lê o `input`/`output` do span para mandar ao judge, mas isso só existe se
`captureContent=true` estiver habilitado no Copilot (ver
[04-lgpd-privacy.md](04-lgpd-privacy.md)). Sem `captureContent`, os evaluators que
dependem de texto completo (ex: `faithfulness`, que compara resposta com contexto)
não têm o que avaliar — rodam vazio ou pulam o span. Métricas baseadas só em
metadados (latência, uso de ferramentas) continuam funcionando normalmente.

## Referência

- [dt-evals no GitHub](https://github.com/dynatrace-oss/dt-evals)
- [Post da comunidade Dynatrace](https://community.dynatrace.com/t5/Open-Source/dt-evals-an-open-source-continuous-evaluation-tool-for-LLM-apps/ba-p/300057)
