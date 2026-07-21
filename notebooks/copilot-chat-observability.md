# IA For Devs × Dynatrace — GitHub Copilot Chat Observability

> Notebook Dynatrace criado programaticamente via MCP.
> Este arquivo é a **fonte versionada** — se precisar recriar em outro tenant,
> use as DQLs abaixo em ordem, cada bloco vira uma célula.
>
> **Notebook ativo (v2 corrigido):** https://fov31014.apps.dynatrace.com/ui/apps/dynatrace.notebooks/notebook/dcceeff0-befc-487d-8a04-b22ceb61d442
>
> **⚠️ Sintaxe DQL importante:**
> - `by:{campo1, campo2}` com chaves — **não** `by campo1, campo2`
> - `startsWith(field, "prefix")` — **não** `field matches "^prefix.*"`
> - `if()` aninhado precisa de `else:` prefixado em **cada** nível

Observabilidade em tempo real do **GitHub Copilot Chat** nas IDEs dos devs, via OpenTelemetry nativo.

**Fonte:** VS Code Copilot Chat → OTel Collector → Dynatrace (`service.name = copilot-chat`)

---

## 🩺 1. Sanity check

```dql
fetch spans, from:now()-1h
| filter service.name == "copilot-chat" or service.name == "github-copilot"
| summarize spans = count(), devs = countDistinct(user.email), by:{service.name, gen_ai.agent.name}
| sort spans desc
```

## 📊 2. Volume — chats vs execuções de tool (últimas 24h)

```dql
fetch spans, from:now()-24h
| filter service.name == "copilot-chat"
| summarize chats = countIf(startsWith(span.name, "chat ")),
            tools = countIf(startsWith(span.name, "execute_tool ")),
            sessions = countDistinct(gen_ai.conversation.id)
```

---

## 💰 FinOps — Consumo e custo

> Custo é **estimado** via pricing hardcoded na DQL. Ajustar conforme contrato Copilot Business/Enterprise.

### 3. Custo total por modelo (últimas 24h)

```dql
fetch spans, from:now()-24h
| filter service.name == "copilot-chat"
| filter isNotNull(gen_ai.usage.input_tokens)
| fieldsAdd inp = toDouble(gen_ai.usage.input_tokens)
| fieldsAdd out = toDouble(gen_ai.usage.output_tokens)
| fieldsAdd cost_usd =
    if(contains(gen_ai.request.model, "opus"),
       (inp * 0.000015) + (out * 0.000075),
    else: if(contains(gen_ai.request.model, "mini"),
       (inp * 0.00000015) + (out * 0.0000006),
    else: if(contains(gen_ai.request.model, "claude"),
       (inp * 0.000003) + (out * 0.000015),
    else: if(contains(gen_ai.request.model, "gpt-4o"),
       (inp * 0.0000025) + (out * 0.00001),
    else: (inp * 0.000002) + (out * 0.00001)))))
| summarize total_cost = sum(cost_usd),
            input_tokens = sum(inp),
            output_tokens = sum(out),
            requests = count(),
            by:{gen_ai.request.model}
| sort total_cost desc
```

### 4. Custo por dev (top 20)

```dql
fetch spans, from:now()-24h
| filter service.name == "copilot-chat"
| filter isNotNull(user.email) and isNotNull(gen_ai.usage.input_tokens)
| fieldsAdd inp = toDouble(gen_ai.usage.input_tokens)
| fieldsAdd out = toDouble(gen_ai.usage.output_tokens)
| fieldsAdd cost_usd =
    if(contains(gen_ai.request.model, "opus"),
       (inp * 0.000015) + (out * 0.000075),
    else: if(contains(gen_ai.request.model, "mini"),
       (inp * 0.00000015) + (out * 0.0000006),
    else: if(contains(gen_ai.request.model, "claude"),
       (inp * 0.000003) + (out * 0.000015),
    else: (inp * 0.0000025) + (out * 0.00001))))
| summarize cost_usd = sum(cost_usd),
            tokens = sum(inp + out),
            chats = count(),
            by:{user.email, user.name, user.team}
| sort cost_usd desc
| limit 20
```

### 5. Custo por time (7 dias)

```dql
fetch spans, from:now()-7d
| filter service.name == "copilot-chat"
| filter isNotNull(user.team) and isNotNull(gen_ai.usage.input_tokens)
| fieldsAdd inp = toDouble(gen_ai.usage.input_tokens)
| fieldsAdd out = toDouble(gen_ai.usage.output_tokens)
| fieldsAdd cost_usd =
    if(contains(gen_ai.request.model, "opus"),
       (inp * 0.000015) + (out * 0.000075),
    else: if(contains(gen_ai.request.model, "mini"),
       (inp * 0.00000015) + (out * 0.0000006),
    else: (inp * 0.0000025) + (out * 0.00001)))
| summarize cost_usd = sum(cost_usd),
            devs = countDistinct(user.email),
            chats = count(),
            by:{user.team}
| sort cost_usd desc
```

---

## ⚙️ SRE — Performance e erros

### 6. Latência P50/P95/P99 por modelo (24h)

```dql
fetch spans, from:now()-24h
| filter service.name == "copilot-chat"
| filter startsWith(span.name, "chat ")
| fieldsAdd dur_ms = duration / 1000000
| summarize p50 = percentile(dur_ms, 50),
            p95 = percentile(dur_ms, 95),
            p99 = percentile(dur_ms, 99),
            avg_ms = avg(dur_ms),
            requests = count(),
            by:{gen_ai.request.model}
| sort p95 desc
```

### 7. Taxa de erro por modelo (24h)

```dql
fetch spans, from:now()-24h
| filter service.name == "copilot-chat"
| filter startsWith(span.name, "chat ")
| summarize total = count(),
            errors = countIf(status == "ERROR"),
            by:{gen_ai.request.model}
| fieldsAdd error_rate_pct = round(toDouble(errors) / toDouble(total) * 100, 2)
| sort error_rate_pct desc
```

### 8. Timeseries de chats por modelo (últimas 6h)

```dql
fetch spans, from:now()-6h
| filter service.name == "copilot-chat"
| filter startsWith(span.name, "chat ")
| makeTimeseries chats = count(), by:{gen_ai.request.model}, interval:5m
```

---

## 🎯 Adoção — Modelos, ferramentas, devs

### 9. Modelos mais usados (7 dias)

```dql
fetch spans, from:now()-7d
| filter service.name == "copilot-chat"
| filter startsWith(span.name, "chat ")
| summarize chats = count(),
            devs = countDistinct(user.email),
            tokens = sum(toLong(gen_ai.usage.input_tokens) + toLong(gen_ai.usage.output_tokens)),
            by:{gen_ai.request.model}
| sort chats desc
```

### 10. Ferramentas (tools) mais invocadas (24h)

```dql
fetch spans, from:now()-24h
| filter service.name == "copilot-chat"
| filter startsWith(span.name, "execute_tool ")
| fieldsAdd tool_name = replaceString(span.name, "execute_tool ", "")
| fieldsAdd dur_ms = duration / 1000000
| summarize calls = count(),
            avg_ms = avg(dur_ms),
            errors = countIf(status == "ERROR"),
            by:{tool_name}
| sort calls desc
| limit 20
```

### 11. Agents / sub-agents ativos (24h)

```dql
fetch spans, from:now()-24h
| filter service.name == "copilot-chat"
| filter isNotNull(gen_ai.agent.name)
| summarize chats = count(),
            tokens = sum(toLong(gen_ai.usage.input_tokens) + toLong(gen_ai.usage.output_tokens)),
            by:{gen_ai.agent.name}
| sort chats desc
```

### 12. Top 10 devs por consumo (7 dias)

```dql
fetch spans, from:now()-7d
| filter service.name == "copilot-chat"
| filter startsWith(span.name, "chat ")
| filter isNotNull(user.email)
| summarize chats = count(),
            tokens = sum(toLong(gen_ai.usage.input_tokens) + toLong(gen_ai.usage.output_tokens)),
            sessions = countDistinct(gen_ai.conversation.id),
            by:{user.email, user.name, user.team}
| sort chats desc
| limit 10
```

---

## 🧵 13. Sessões — top conversas por consumo (24h)

```dql
fetch spans, from:now()-24h
| filter service.name == "copilot-chat"
| filter isNotNull(gen_ai.conversation.id)
| summarize chats = count(),
            total_tokens = sum(toLong(gen_ai.usage.input_tokens) + toLong(gen_ai.usage.output_tokens)),
            by:{gen_ai.conversation.id, user.email}
| sort total_tokens desc
| limit 10
```

---

## 🔒 14. Prompts — conteúdo das interações

> ⚠️ Só retorna dados **se `captureContent=true`** estiver habilitado no VS Code.
> Requer aprovação LGPD. Ver [docs/04-lgpd-privacy.md](../docs/04-lgpd-privacy.md).

```dql
fetch spans, from:now()-1h
| filter service.name == "copilot-chat"
| filter isNotNull(gen_ai.input.messages) or isNotNull(gen_ai.output.messages)
| fields timestamp, user.email, gen_ai.request.model,
         gen_ai.input.messages, gen_ai.output.messages,
         gen_ai.usage.input_tokens, gen_ai.usage.output_tokens
| sort timestamp desc
| limit 5
```
