# Troubleshooting

## VS Code não está emitindo nada

### 1. Verificar se OTel está realmente habilitado

`Cmd+Shift+P` → **Developer: Policy Diagnostics**. Procure a seção `Managed Settings`
ou `Copilot OpenTelemetry`. Deve mostrar `enabled: true` e o endpoint configurado.

Se estiver `enabled: false`:
- Verificar user settings (Cmd+,)
- Verificar variáveis de ambiente (`echo $OTEL_EXPORTER_OTLP_ENDPOINT`)
- Se enterprise: pedir para o admin verificar a policy no `.github-private/copilot/managed-settings.json`

### 2. Verificar endpoint acessível

Do terminal, teste:

```bash
curl -v http://localhost:4318/v1/traces \
  -H "Content-Type: application/json" \
  -d '{}'
```

Deve retornar HTTP 200 ou 400 (payload vazio). Se der connection refused, o
collector não está rodando ou está em outra porta.

### 3. Ver os logs do próprio VS Code

`Cmd+Shift+P` → **Output** → dropdown → **GitHub Copilot Chat**. Erros de OTel
aparecem aí (falha de conexão, timeout, etc.).

Se estiver silencioso, aumentar o log level via env var:

```bash
export COPILOT_OTEL_LOG_LEVEL=debug
```

Reinicie o VS Code.

### 4. Usar o exporter console para debugar localmente

Troque temporariamente o user settings para:

```jsonc
{
  "github.copilot.chat.otel.enabled": true,
  "github.copilot.chat.otel.exporterType": "console"
}
```

Os spans passam a aparecer direto no Output panel do VS Code (canal
**GitHub Copilot Chat**). Se aparecerem aqui mas não no collector, o problema
é no envio HTTP.

### 5. Usar o exporter file

```jsonc
{
  "github.copilot.chat.otel.enabled": true,
  "github.copilot.chat.otel.exporterType": "file",
  "github.copilot.chat.otel.outfile": "/tmp/copilot-otel.jsonl"
}
```

`tail -f /tmp/copilot-otel.jsonl` mostra os spans em tempo real.

## Collector recebe mas Dynatrace não mostra

### 1. Verificar logs do Collector

```bash
podman logs -f bv-otel-collector | tail -50
```

Procurar por:
- `HTTP 403` → token do Dynatrace sem scope. Precisa `openTelemetryTrace.ingest`.
- `HTTP 401` → token inválido ou expirado.
- `HTTP 400` → payload inválido (raríssimo).
- `no such host` → DNS do endpoint Dynatrace não resolve.

### 2. Verificar o endpoint do Dynatrace

Deve ser `https://<tenant-id>.live.dynatrace.com/api/v2/otlp/v1/traces` — nota:
`live.dynatrace.com`, **não** `apps.dynatrace.com`.

Para o tenant `fov31014.apps.dynatrace.com`, o OTLP fica em
`fov31014.live.dynatrace.com`.

### 3. Confirmar scope do token

No tenant: `Ctrl+K` → **Access Tokens** → abrir o token usado no `.env`. Deve ter:
- `openTelemetryTrace.ingest`
- `metrics.ingest` (se estiver mandando métricas também)

### 4. DQL vazio mesmo com collector recebendo?

Testar sem filtro:

```dql
fetch spans, from:now()-15m
| limit 10
| fields service.name, span.name
```

Se retornar dados de outros serviços mas nenhum `copilot-chat` / `github-copilot`,
provavelmente o Collector está descartando os spans. Ver a config em
`otel-collector-config.yaml`.

## Dados chegam mas atributos estão faltando

### Atributo `user.email` / `user.team` está vazio

Não configurou `OTEL_RESOURCE_ATTRIBUTES`. Ver [03-dev-user-settings.md](03-dev-user-settings.md#enriquecimento-com-identidade-opcional).

Alternativamente, colocar como resource attribute no collector, por meio de um
processor `resource`:

```yaml
processors:
  resource:
    attributes:
      - key: user.email
        from_attribute: user.name
        action: insert
```

### Atributo `github.copilot.git.repository` vazio

O VS Code só popula esse atributo se você estiver com uma pasta git aberta.
Se estiver testando com uma pasta qualquer, não vai aparecer.

## captureContent está true mas prompt não aparece nos spans

Ver o filtro do exporter. Content capture adiciona atributos possivelmente **muito
grandes**. Se o backend/collector tem limite de tamanho por atributo, o VS Code
pode estar truncando ou o backend pode estar rejeitando.

Verifique `maxAttributeSizeChars`:

```jsonc
{
  "github.copilot.chat.otel.maxAttributeSizeChars": 8000
}
```

E no collector, o receiver OTLP tem limite default de payload; se estiver com
muitos spans grandes, aumentar:

```yaml
receivers:
  otlp:
    protocols:
      http:
        max_request_body_size: 4194304  # 4MB
```

## Copilot CLI não emite

O CLI só suporta `otlp-http` (mesmo se você configurar `otlp-grpc` no VS Code).
Certifique-se que o endpoint do collector aceita HTTP.

Se rodar o CLI num terminal fora do VS Code, precisa exportar as env vars manualmente:

```bash
export COPILOT_OTEL_ENABLED=true
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318
copilot chat "diga oi"
```

## Verificar precedência das settings

`Cmd+Shift+P` → **Developer: Policy Diagnostics**. A seção mostra qual **channel** (native MDM,
server-managed, file-based, env var, user setting) forneceu o valor efetivo.

Ordem de precedência (do maior para o menor):

1. Native MDM
2. Server-managed
3. File-based `managed-settings.json`
4. Environment variables
5. User settings

Se você configurou user setting mas está sendo ignorado, algum canal superior está
sobrescrevendo.

## Comandos úteis no VS Code

| Comando | Uso |
|---|---|
| **Developer: Policy Diagnostics** | Ver quais policies estão aplicadas |
| **Developer: Reload Window** | Recarregar após mudar settings |
| **Chat: Export Agent Traces DB** | Exportar SQLite local com todos os spans (se `dbSpanExporter.enabled=true`) |
| **Chat: Show Cache Explorer** | Ver hit rate de prompt caching |
| **Output** → **GitHub Copilot Chat** | Logs da extensão |
