# Guia do dev — configuração no piloto

Este documento é para os **3-5 devs que vão participar do piloto** antes do rollout
enterprise. É a forma manual de habilitar a telemetria, sem depender do admin do
Copilot.

Quando o rollout enterprise acontecer, essas configurações serão **sobrescritas pela
managed policy** automaticamente — você não precisa desfazer nada.

## Pré-requisitos

- VS Code versão **1.128 ou superior** (para suportar a precedência das managed policies).
- Extensão **GitHub Copilot Chat** atualizada.
- Endereço do collector fornecido pelo time de plataforma. Para o piloto local,
  use `http://localhost:4318`.

## Setup em 3 passos

### 1. Rode o collector localmente (piloto local) OU use o do time (piloto remoto)

**Piloto local** — na pasta do projeto:

```bash
cd collector
cp .env.example .env
# edite .env e coloque o DT_INGEST_TOKEN
podman-compose up -d
```

**Piloto remoto** — pergunte ao time de plataforma o URL do collector corporativo.

### 2. Configure o VS Code

`Cmd+Shift+P` → **Preferences: Open User Settings (JSON)** → adicione:

```jsonc
{
  // ── Habilita OpenTelemetry para o Copilot Chat ────────────────────
  "github.copilot.chat.otel.enabled": true,
  "github.copilot.chat.otel.exporterType": "otlp-http",
  "github.copilot.chat.otel.otlpEndpoint": "http://localhost:4318",

  // ── Captura de conteúdo ───────────────────────────────────────────
  // false = só metadados (modelo, tokens, latência). SEGURO.
  // true  = também captura prompt, resposta, tool args e resultados.
  //         REQUER APROVAÇÃO JURÍDICA da IA For Devs antes de habilitar.
  "github.copilot.chat.otel.captureContent": false,

  // ── Limite de tamanho por atributo (proteção do backend) ──────────
  // 0 = sem limite; se ligar captureContent, considere 8000 (8k chars).
  "github.copilot.chat.otel.maxAttributeSizeChars": 0
}
```

### 3. Reload do VS Code

`Cmd+Shift+P` → **Developer: Reload Window**.

## Validação

Use o Copilot Chat normalmente por alguns minutos. Depois:

### Do lado do VS Code

`Cmd+Shift+P` → **Developer: Show Running Extensions** → confirme que **GitHub Copilot Chat**
está ativo.

Para inspecionar o que está sendo emitido localmente, use o exporter `console` (só pra debug):

```jsonc
{
  "github.copilot.chat.otel.enabled": true,
  "github.copilot.chat.otel.exporterType": "console"
}
```

Os spans aparecem no **Output panel** → dropdown → `GitHub Copilot Chat`.

### Do lado do collector

```bash
podman logs -f bv-otel-collector | grep -E "spans|traces"
```

Deve ver linhas indicando spans recebidos.

### Do lado do Dynatrace

Notebook do tenant → cole:

```dql
fetch spans, from:now()-5m
| filter gen_ai.provider.name == "github"
| fields timestamp, gen_ai.agent.name, gen_ai.request.model,
         gen_ai.usage.input_tokens, gen_ai.usage.output_tokens,
         span.name, duration
| sort timestamp desc
| limit 20
```

Se retornar linhas, deu certo.

## Enriquecimento com identidade (opcional)

Você pode adicionar atributos extras via variável de ambiente. No `.zshrc`/`.bashrc`:

```bash
export OTEL_RESOURCE_ATTRIBUTES="user.email=seu.nome@iafordevs.com.br,user.team=plataforma-api,cost_center=engineering"
```

Reinicie o VS Code depois. No Dynatrace, esses atributos vão aparecer em todos os
spans, permitindo filtros por time/cost center/pessoa.

## Trocar entre "só metadados" e "conteúdo completo"

**⚠️ Só habilite captureContent depois de aprovação jurídica da IA For Devs.**

Uma vez aprovado, mude no user settings:

```jsonc
{
  "github.copilot.chat.otel.captureContent": true
}
```

Agora os spans vão incluir:
- `gen_ai.input.messages` — mensagens completas do dev
- `gen_ai.output.messages` — respostas completas do Copilot
- `gen_ai.tool.call.arguments` — argumentos passados para ferramentas (ex: caminho de arquivo)
- `gen_ai.tool.call.result` — retorno das ferramentas (ex: conteúdo de arquivo lido)

Isso inclui **código-fonte** de arquivos abertos, conteúdo de terminal, etc. Ver
[04-lgpd-privacy.md](04-lgpd-privacy.md).

## Para desabilitar

Basta remover as linhas do user settings. Não emite mais nada.

## FAQ

**"Isso afeta a performance do meu VS Code?"**
Praticamente não. Overhead reportado: <1% de CPU e <10MB de RAM. O exporter é async.

**"Meu Copilot Chat vai ficar mais lento?"**
Não. O OTel roda em background depois que a resposta é retornada ao usuário.

**"Se o collector cair, o Copilot para?"**
Não. O SDK OTel tem retry + timeout curto. Falhas são silenciosas e não bloqueiam.

**"O que acontece com o autocomplete inline (as sugestões que aparecem enquanto digito)?"**
Nada — o autocomplete inline ainda não emite OTel. Só o Chat está coberto.

**"E se eu usar Copilot no JetBrains ou Visual Studio?"**
Nesses IDEs o OTel ainda não está disponível. Só VS Code.

**"E o Copilot CLI (terminal)?"**
Também emite, mas em processo separado. Vai aparecer com `service.name = github-copilot`
em vez de `copilot-chat`. Ambos aparecem no mesmo tenant.

**"Consegue distinguir o que veio de qual dev?"**
Sim, se você configurar `OTEL_RESOURCE_ATTRIBUTES` com `user.email` ou `user.name`.
No rollout enterprise, isso vai vir automaticamente via managed policy.

**"Se eu logar em uma conta pessoal do GitHub, ainda vai capturar?"**
Depende. No rollout enterprise a IA For Devs pode configurar `ChatApprovedAccountOrganizations`
para bloquear features de AI a menos que o dev esteja logado em uma conta corporativa.
No piloto (user settings), sim, captura independente da conta.
