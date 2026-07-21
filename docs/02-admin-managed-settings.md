# Guia do admin — deploy do `managed-settings.json`

Este documento é para o **time de admins do GitHub Copilot na IA For Devs**. Explica
como fazer com que **todos os devs** passem a emitir telemetria OTel para o
collector corporativo, sem que cada dev precise configurar nada.

## Pré-requisitos

- Plano **Copilot Business** ou **Enterprise** (o managed-settings.json não se aplica ao plano Individual).
- Um dos três canais de delivery disponível:
  - GitHub Enterprise Cloud com AI Controls configurado (server-managed), **OU**
  - MDM (Intune/Jamf) para native MDM, **OU**
  - Config-mgmt (Ansible/Chef/Puppet/SCCM) para file-based.
- OTel Collector corporativo rodando (ver [../collector/](../collector/)).

## Canal 1 — Server-managed (recomendado para GitHub Enterprise Cloud)

Requer que a org IA For Devs esteja no GHEC com AI Controls habilitado.

### Passos

1. No Enterprise Settings → **AI Controls** → **Agents**, selecione a organização
   que hospedará o repositório `.github-private`.
2. Crie (se ainda não existe) o repositório `.github-private` nessa org.
3. Adicione o arquivo `copilot/managed-settings.json` com o conteúdo abaixo:

```json
{
  "telemetry": {
    "enabled": true,
    "endpoint": "https://otel-collector.iafordevs.corp:4318",
    "protocol": "otlp-http",
    "captureContent": false,
    "lockCaptureContent": true,
    "serviceName": "copilot-chat-iafordevs",
    "resourceAttributes": {
      "deployment.environment": "production",
      "organization": "iafordevs",
      "cost_center": "engineering"
    }
  }
}
```

4. Commit no branch default (`main`).
5. Verificação: aguarde ~1h (o VS Code refaz o pull hourly) ou peça a um dev
   piloto pra rodar `Developer: Policy Diagnostics` no VS Code — deve aparecer o
   bloco de `telemetry.*` como "policy-enforced".

**Vantagem:** os devs podem trocar de máquina que a política acompanha.

## Canal 2 — File-based (Linux/servers ou MDM personalizado)

Coloque o arquivo em uma das localizações abaixo em cada máquina:

| SO | Path |
|---|---|
| macOS | `/Library/Application Support/GitHubCopilot/managed-settings.json` |
| Windows | `%ProgramFiles%\GitHubCopilot\managed-settings.json` |
| Linux | `/etc/github-copilot/managed-settings.json` |

### Exemplo via Ansible

```yaml
- name: Configure GitHub Copilot managed settings
  hosts: dev_workstations
  tasks:
    - name: Ensure directory exists (macOS)
      file:
        path: /Library/Application Support/GitHubCopilot
        state: directory
        mode: '0755'
      when: ansible_os_family == "Darwin"

    - name: Deploy managed-settings.json (macOS)
      copy:
        src: files/managed-settings.json
        dest: /Library/Application Support/GitHubCopilot/managed-settings.json
        mode: '0644'
      when: ansible_os_family == "Darwin"
    # ... equivalente para Windows e Linux
```

O conteúdo do arquivo é o mesmo do Canal 1.

## Canal 3 — Native MDM (Windows Registry / macOS managed prefs)

### Windows (via GPO ou Intune)

Registry key: `HKEY_LOCAL_MACHINE\SOFTWARE\Policies\GitHubCopilot`

Cada campo do bloco `telemetry` é um valor separado. Campos estruturados (como
`resourceAttributes`) vão como JSON string.

Exemplo `.reg`:

```reg
Windows Registry Editor Version 5.00

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\GitHubCopilot]
"telemetry.enabled"=dword:00000001
"telemetry.endpoint"="https://otel-collector.iafordevs.corp:4318"
"telemetry.protocol"="otlp-http"
"telemetry.captureContent"=dword:00000000
"telemetry.lockCaptureContent"=dword:00000001
"telemetry.serviceName"="copilot-chat-iafordevs"
"telemetry.resourceAttributes"="{\"deployment.environment\":\"production\",\"organization\":\"iafordevs\"}"
```

### macOS (via Jamf ou managed preferences)

Preference domain: `com.github.copilot`

Configuration Profile `.mobileconfig` com o payload:

```xml
<key>telemetry.enabled</key><true/>
<key>telemetry.endpoint</key><string>https://otel-collector.iafordevs.corp:4318</string>
<key>telemetry.protocol</key><string>otlp-http</string>
<key>telemetry.captureContent</key><false/>
<key>telemetry.lockCaptureContent</key><true/>
<key>telemetry.serviceName</key><string>copilot-chat-iafordevs</string>
```

## Campos do bloco `telemetry` — referência

| Campo | Tipo | Descrição |
|---|---|---|
| `enabled` | bool | Liga/desliga a exportação OTel. Quando managed, usuário não pode sobrescrever. |
| `endpoint` | string | URL do collector OTLP (ex: `https://otel-collector.corp:4318`). |
| `protocol` | string | `otlp-http` ou `otlp-grpc`. |
| `captureContent` | bool | Captura prompt/resposta/tool args. **Requer aprovação jurídica.** Ver [04-lgpd-privacy.md](04-lgpd-privacy.md). |
| `lockCaptureContent` | bool | Impede o dev de sobrescrever `captureContent` em suas settings. |
| `serviceName` | string | `service.name` no OTel (padrão: `copilot-chat`). |
| `resourceAttributes` | object | Atributos extras (`team.id`, `cost_center`, etc.). |
| `headers` | object | **Não recomendado.** Ver nota abaixo. |

## Nota importante sobre `telemetry.headers`

O bloco managed `headers` é **aplicado apenas à extensão Copilot Chat**, não é
propagado para subprocessos do agent host (ex: terminal CLI). Isso é intencional
por segurança — evita vazar tokens para processos filhos.

**Recomendação:** deixe headers vazio no managed-settings. Faça a autenticação
**no collector**, adicionando o header `Authorization: Api-Token dt0c01.xxx` lá.

## Verificação após deploy

### Do lado do admin

```bash
# GHEC API — confirmar que a source-org está configurada:
curl -H "Authorization: Bearer $GH_TOKEN" \
  https://api.github.com/enterprises/iafordevs/copilot/custom-agents-source
```

### Do lado do dev

No VS Code, `Cmd+Shift+P` → **Developer: Policy Diagnostics**. Deve aparecer:

```
Managed Settings (source: server-managed)
✓ telemetry.enabled = true
✓ telemetry.endpoint = https://otel-collector.iafordevs.corp:4318
✓ telemetry.captureContent = false [locked]
```

### Do lado do Dynatrace

Notebook → cole a DQL:

```dql
fetch spans, from:now()-15m
| filter gen_ai.provider.name == "github"
| filter gen_ai.agent.name == "copilot"
| summarize devs = countDistinct(user.name), spans = count()
```

Se retorna `spans > 0`, está funcionando.

## Rollback

Se precisar desligar em emergência:

- **Server-managed:** comitar `{"telemetry": {"enabled": false}}` no
  `.github-private/copilot/managed-settings.json`. Propaga em ~1h.
- **File-based:** remover o arquivo com Ansible → dev volta ao default (OTel off).
- **Native MDM:** remover a policy → dev volta ao default.
