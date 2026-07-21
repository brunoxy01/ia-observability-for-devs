# DQL Queries — validação e análises

Todas as queries a seguir devem ser executadas no **Notebook** do tenant
`https://fov31014.apps.dynatrace.com` (Ctrl+K → Notebooks).

## Sanity check — spans estão chegando?

```dql
fetch spans, from:now()-5m
| filter gen_ai.provider.name == "github"
| summarize count = count() by service.name, gen_ai.agent.name
```

Deve retornar linhas com `copilot-chat` ou `github-copilot`. Se vazio, ver
[06-troubleshooting.md](06-troubleshooting.md).

## Sanity check — atributos completos?

```dql
fetch spans, from:now()-5m
| filter gen_ai.provider.name == "github"
| filter span.name == "chat"
| fields timestamp,
         gen_ai.agent.name,
         gen_ai.request.model,
         gen_ai.usage.input_tokens,
         gen_ai.usage.output_tokens,
         gen_ai.usage.cache_read.input_tokens,
         duration
| sort timestamp desc
| limit 20
```

## FinOps — custo estimado (últimas 24h)

O Copilot Chat não emite custo diretamente, então calculamos a partir dos tokens e
uma tabela de pricing hardcoded na query. Ajustar valores conforme necessário.

```dql
fetch spans, from:now()-24h
| filter gen_ai.provider.name == "github"
| filter span.name == "chat"
| fieldsAdd inp = toDouble(gen_ai.usage.input_tokens)
| fieldsAdd out = toDouble(gen_ai.usage.output_tokens)
| fieldsAdd cost_usd =
    if(contains(gen_ai.request.model, "gpt-4o-mini"),
       (inp * 0.00000015) + (out * 0.0000006),
    else: if(contains(gen_ai.request.model, "gpt-4o"),
       (inp * 0.0000025) + (out * 0.00001),
    else: if(contains(gen_ai.request.model, "claude"),
       (inp * 0.000003) + (out * 0.000015),
    else: if(contains(gen_ai.request.model, "o1"),
       (inp * 0.000015) + (out * 0.00006),
       (inp * 0.000002) + (out * 0.00001)))))
| summarize total_cost = sum(cost_usd),
            total_input_tokens = sum(inp),
            total_output_tokens = sum(out),
            requests = count()
  by gen_ai.request.model
| sort total_cost desc
```

## FinOps — custo por dev

```dql
fetch spans, from:now()-24h
| filter gen_ai.provider.name == "github"
| filter span.name == "chat"
| fieldsAdd inp = toDouble(gen_ai.usage.input_tokens)
| fieldsAdd out = toDouble(gen_ai.usage.output_tokens)
| fieldsAdd cost_usd =
    if(contains(gen_ai.request.model, "gpt-4o-mini"),
       (inp * 0.00000015) + (out * 0.0000006),
    else: if(contains(gen_ai.request.model, "gpt-4o"),
       (inp * 0.0000025) + (out * 0.00001),
    else: if(contains(gen_ai.request.model, "claude"),
       (inp * 0.000003) + (out * 0.000015),
       (inp * 0.000002) + (out * 0.00001))))
| summarize cost = sum(cost_usd),
            tokens = sum(inp + out),
            chats = count(),
            modelos = collectDistinct(gen_ai.request.model)
  by user.email, user.name, user.team
| sort cost desc
| limit 50
```

Se `user.*` estiver vazio, o `OTEL_RESOURCE_ATTRIBUTES` não foi configurado — voltar
ao [03-dev-user-settings.md](03-dev-user-settings.md#enriquecimento-com-identidade-opcional).

## FinOps — custo por time

```dql
fetch spans, from:now()-7d
| filter gen_ai.provider.name == "github"
| filter span.name == "chat"
| filter isNotNull(user.team)
| fieldsAdd inp = toDouble(gen_ai.usage.input_tokens)
| fieldsAdd out = toDouble(gen_ai.usage.output_tokens)
| fieldsAdd cost_usd =
    if(contains(gen_ai.request.model, "mini"),
       (inp * 0.00000015) + (out * 0.0000006),
    else: (inp * 0.0000025) + (out * 0.00001))
| summarize cost = sum(cost_usd),
            tokens = sum(inp + out),
            devs = countDistinct(user.email),
            chats = count()
  by user.team
| fieldsAdd cost_por_dev = cost / devs
| sort cost desc
```

## SRE — latência por modelo

```dql
fetch spans, from:now()-24h
| filter gen_ai.provider.name == "github"
| filter span.name == "chat"
| fieldsAdd duration_ms = duration / 1000000
| summarize p50 = percentile(duration_ms, 50),
            p95 = percentile(duration_ms, 95),
            p99 = percentile(duration_ms, 99),
            requests = count()
  by gen_ai.request.model
| sort p95 desc
```

## SRE — time to first token (TTFT)

```dql
fetch spans, from:now()-24h
| filter isNotNull(copilot_chat.time_to_first_token)
| fieldsAdd ttft_ms = toDouble(copilot_chat.time_to_first_token)
| summarize p50 = percentile(ttft_ms, 50),
            p95 = percentile(ttft_ms, 95),
            avg = avg(ttft_ms)
  by gen_ai.request.model
| sort p95 desc
```

## SRE — taxa de erro

```dql
fetch spans, from:now()-24h
| filter gen_ai.provider.name == "github"
| summarize total = count(),
            errors = countIf(status == "ERROR"),
            error_types = collectDistinct(error.type)
  by gen_ai.request.model
| fieldsAdd error_rate = round(toDouble(errors) / toDouble(total) * 100, 2)
| sort error_rate desc
```

## Adoção — modelos mais usados

```dql
fetch spans, from:now()-7d
| filter gen_ai.provider.name == "github"
| filter span.name == "chat"
| summarize chats = count(),
            devs = countDistinct(user.email),
            tokens = sum(toLong(gen_ai.usage.input_tokens) + toLong(gen_ai.usage.output_tokens))
  by gen_ai.request.model
| sort chats desc
```

## Adoção — ferramentas (tools) mais usadas

```dql
fetch spans, from:now()-7d
| filter gen_ai.provider.name == "github"
| filter span.name == "execute_tool"
| summarize calls = count(),
            avg_duration_ms = avg(duration / 1000000)
  by gen_ai.tool.name
| sort calls desc
| limit 20
```

## Adoção — devs mais engajados (top 20)

```dql
fetch spans, from:now()-7d
| filter gen_ai.provider.name == "github"
| filter span.name == "invoke_agent"
| summarize sessions = countDistinct(gen_ai.conversation.id),
            chats = count(),
            unique_models = countDistinct(gen_ai.request.model)
  by user.email, user.name, user.team
| sort chats desc
| limit 20
```

## Adoção — repositórios mais trabalhados

```dql
fetch spans, from:now()-7d
| filter gen_ai.provider.name == "github"
| filter isNotNull(github.copilot.git.repository)
| summarize sessions = countDistinct(gen_ai.conversation.id),
            devs = countDistinct(user.email)
  by github.copilot.git.repository
| sort sessions desc
| limit 20
```

## Qualidade — feedback dos devs (thumbs up/down)

Isso vem via **metrics**, não spans. Rode em um dashboard com timeseries visualization.

```dql
timeseries feedback = sum(copilot_chat.user.feedback.count),
  by:{feedback_type}, from:now()-7d, interval:1h
```

## Qualidade — acceptance rate de edições

```dql
timeseries accepted = sum(copilot_chat.edit.acceptance.count, filter:{outcome=="accepted"}),
           rejected = sum(copilot_chat.edit.acceptance.count, filter:{outcome=="rejected"}),
  from:now()-7d, interval:1h
```

## Content capture — top prompts (só se `captureContent=true`)

**⚠️ Só funciona com captureContent habilitado. Ver [04-lgpd-privacy.md](04-lgpd-privacy.md).**

```dql
fetch spans, from:now()-24h
| filter gen_ai.provider.name == "github"
| filter isNotNull(gen_ai.input.messages)
| fieldsAdd tokens = toLong(gen_ai.usage.input_tokens) + toLong(gen_ai.usage.output_tokens)
| fields timestamp, user.name, gen_ai.request.model, tokens,
         gen_ai.input.messages, gen_ai.output.messages
| sort tokens desc
| limit 10
```
