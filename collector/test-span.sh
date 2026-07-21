#!/usr/bin/env bash
# test-span.sh — envia um span sintético formato Copilot Chat pro collector local
set -euo pipefail

TRACE_ID=$(openssl rand -hex 16)
SPAN_ID=$(openssl rand -hex 8)
NOW_NS=$(($(date +%s) * 1000000000))
END_NS=$((NOW_NS + 1500000000))

curl -sS -X POST http://localhost:4318/v1/traces \
  -H "Content-Type: application/json" \
  -w "\nHTTP %{http_code}\n" \
  -d @- <<EOF
{
  "resourceSpans": [{
    "resource": {
      "attributes": [
        {"key":"service.name","value":{"stringValue":"copilot-chat"}},
        {"key":"service.version","value":{"stringValue":"1.128.0"}},
        {"key":"session.id","value":{"stringValue":"test-session-001"}},
        {"key":"user.email","value":{"stringValue":"bruno.silva@boavista.com.br"}},
        {"key":"user.name","value":{"stringValue":"Bruno Silva"}},
        {"key":"user.team","value":{"stringValue":"plataforma-api"}}
      ]
    },
    "scopeSpans": [{
      "scope": {"name":"github.copilot.chat"},
      "spans": [{
        "traceId": "${TRACE_ID}",
        "spanId": "${SPAN_ID}",
        "name": "chat gpt-4o",
        "kind": 3,
        "startTimeUnixNano": "${NOW_NS}",
        "endTimeUnixNano": "${END_NS}",
        "attributes": [
          {"key":"gen_ai.provider.name","value":{"stringValue":"github"}},
          {"key":"gen_ai.agent.name","value":{"stringValue":"copilot"}},
          {"key":"gen_ai.operation.name","value":{"stringValue":"chat"}},
          {"key":"gen_ai.request.model","value":{"stringValue":"gpt-4o"}},
          {"key":"gen_ai.response.model","value":{"stringValue":"gpt-4o"}},
          {"key":"gen_ai.conversation.id","value":{"stringValue":"conv-abc123"}},
          {"key":"gen_ai.usage.input_tokens","value":{"intValue":"342"}},
          {"key":"gen_ai.usage.output_tokens","value":{"intValue":"189"}},
          {"key":"llm.request.type","value":{"stringValue":"chat"}},
          {"key":"github.copilot.git.repository","value":{"stringValue":"boavista/score-api"}},
          {"key":"github.copilot.git.branch","value":{"stringValue":"main"}}
        ],
        "status": {"code": 1}
      }]
    }]
  }]
}
EOF
