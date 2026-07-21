# LGPD e privacidade — considerações críticas

Este documento **precisa ser lido antes** de tomar decisões sobre `captureContent`.
Ativar essa opção em produção sem alinhamento adequado com jurídico e RH pode gerar
passivo trabalhista, questionamentos regulatórios (LGPD/ANPD) e perda de confiança
dos devs.

## O que muda entre `captureContent=false` e `captureContent=true`

### Com `captureContent: false` (default seguro)

Dynatrace recebe:
- Nome do modelo usado (`gpt-4o`, `claude-3-5-sonnet`, etc.)
- Contagens de tokens (input, output, cache hits)
- Latência da chamada
- Nomes de ferramentas invocadas (`readFile`, `runCommand`, etc.)
- IDs (session.id, conversation.id, trace.id, span.id)
- Metadata git (repository, branch, commit)
- Timestamps

**Sem conteúdo textual.** Não há prompts, respostas, código, comandos ou dados de arquivo.

### Com `captureContent: true`

Além do acima, Dynatrace passa a receber:
- `gen_ai.input.messages` — **texto integral** do que o dev perguntou
- `gen_ai.output.messages` — **texto integral** da resposta do Copilot
- `gen_ai.tool.call.arguments` — argumentos das ferramentas (ex: **caminhos de arquivos abertos**)
- `gen_ai.tool.call.result` — retorno das ferramentas (ex: **conteúdo dos arquivos lidos**, saída de terminal, etc.)
- `github.copilot.tool.parameters.command` — **comandos de shell** que o Copilot rodou
- `github.copilot.tool.parameters.file_path` — **caminhos de arquivos** manipulados

Isso inclui, potencialmente:
- Código-fonte proprietário da Boa Vista
- Senhas / API keys embutidas no código (mesmo que temporariamente)
- CPFs, e-mails, nomes de clientes se aparecerem em prompts ou arquivos
- Comandos executados no terminal (que podem incluir credenciais)
- Perguntas pessoais/sensíveis do dev ao Copilot ("como calcular hora extra sem RH ver")

## Riscos concretos

### 1. LGPD

- Prompts podem conter **dados pessoais** de clientes que o dev cola no chat.
- Uma vez no Dynatrace (Grail), esses dados ficam armazenados por 35 dias (padrão) ou
  mais, com potencial de aparecer em logs, alertas, dashboards.
- Precisa de base legal, comunicação ao titular do dado, e prazo de retenção alinhado
  com a política interna da Boa Vista.

**Encaminhamento sugerido:** DPO da Boa Vista precisa aprovar a captura antes de ativar.

### 2. Segredo industrial e IP

- Código-fonte que passa pelo Copilot pode ser objeto de sigilo comercial ou patente.
- Se o Dynatrace tem acesso a esse conteúdo, isso amplia a superfície de exposição
  (backups, terceirizados de suporte com acesso ao tenant, etc.).

**Encaminhamento sugerido:** revisão pelo time de segurança da informação + eventual
inclusão em cláusula do contrato Dynatrace.

### 3. Relação trabalhista

- Capturar o **conteúdo textual** do que o dev pergunta ao Copilot é, na prática,
  monitorar sua produção intelectual detalhadamente.
- Pode configurar monitoramento excessivo à luz da CLT/precedentes trabalhistas se
  não houver:
  - Comunicação transparente **antes** de ativar
  - Aviso claro na tela do VS Code (feito pelo próprio Copilot quando `captureContent` está ligado)
  - Alinhamento com representação sindical/comitê de empregados, quando aplicável

**Encaminhamento sugerido:** RH + Jurídico trabalhista aprovarem o texto da comunicação e o
modelo de consentimento (ou nota informativa) para os devs.

### 4. Comitê de segurança

- Alguns dados sensíveis (chaves API, tokens) podem vazar acidentalmente para prompts
  do Copilot e ir parar no Dynatrace.
- Precisa haver processo de **detecção e remoção** desses vazamentos no
  collector antes de forwardar.

**Encaminhamento sugerido:** habilitar redação de PII/secrets no OTel Collector.

## Recomendação técnica em ordem crescente de risco

### Nível 1 — sem captureContent (recomendado para começar)

- **Habilita:** só metadados (tokens, latência, modelo, ferramentas, adoção)
- **Cobre:** 100% dos 4 pilares FinOps/SRE
- **Risco LGPD:** praticamente nulo (não há PII/código exposto)
- **Aprovação necessária:** apenas segurança da informação (validar canal Collector→Dynatrace)

### Nível 2 — captureContent com sanitização no Collector

- **Habilita:** conteúdo completo, mas **filtrado** pelo Collector antes de ir pro Dynatrace
- **Filtros aplicados:**
  - Regex de CPF/CNPJ → substitui por hash
  - Regex de email → substitui por hash + domínio
  - Regex de senhas/tokens (`api_key=`, `password=`, `Bearer `) → substitui por `[REDACTED]`
  - Truncagem de campos > 8k chars
- **Cobre:** análise de qualidade de prompts, tipos de perguntas, temas mais comuns
- **Risco LGPD:** baixo, mas requer aprovação do DPO
- **Aprovação necessária:** DPO + Segurança + Jurídico + comunicação aos devs

### Nível 3 — captureContent completo (não recomendado)

- **Habilita:** todo o conteúdo, sem filtros
- **Cobre:** auditoria total (útil para investigação de incidentes específicos)
- **Risco LGPD:** alto
- **Aprovação necessária:** Comitê Executivo + DPO + Jurídico Trabalhista + Sindicato + termo aditivo de contrato de trabalho

## Configuração de sanitização no Collector (Nível 2)

Ver [`collector/otel-collector-config.yaml`](../collector/otel-collector-config.yaml). Trecho relevante:

```yaml
processors:
  transform:
    trace_statements:
      - context: span
        statements:
          # Máscara de CPF
          - replace_pattern(attributes["gen_ai.input.messages"], "\\d{3}\\.?\\d{3}\\.?\\d{3}-?\\d{2}", "[CPF]")
          # Máscara de email
          - replace_pattern(attributes["gen_ai.input.messages"], "[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+", "[EMAIL]")
          # Truncagem
          - truncate_all(attributes["gen_ai.input.messages"], 8000)
```

## Recomendação para a POC Boa Vista

**Rodar o piloto e o rollout enterprise inicial com `captureContent: false`.**

Motivos:
1. Cobre 100% dos requisitos formalmente pedidos (FinOps + SRE).
2. Zera o risco jurídico — não há dado sensível trafegando.
3. Permite validar a arquitetura sem depender do rito de aprovação LGPD.
4. Se depois o cliente pedir análise de qualidade de prompts, aí sim inicia o
   processo de aprovação para migrar a subset de devs para Nível 2.

O `lockCaptureContent: true` no managed-settings garante que **nenhum dev consegue
sobrescrever** para true individualmente, dando previsibilidade jurídica.

## Comunicação aos devs (template)

Sugestão de aviso interno antes de habilitar (mesmo no Nível 1):

> **Aviso: telemetria de uso do GitHub Copilot Chat**
>
> A partir de [data], o VS Code passa a enviar telemetria anônima de suas
> interações com o Copilot Chat para o Dynatrace, nossa plataforma de observabilidade.
>
> **O que é capturado:**
> - Modelos utilizados (GPT-4o, Claude, etc.)
> - Volume de tokens e tempo de resposta
> - Ferramentas invocadas (leitura de arquivo, comandos de shell)
> - Metadados do repositório (branch, commit)
>
> **O que NÃO é capturado:**
> - Texto das suas perguntas ao Copilot
> - Respostas do Copilot
> - Conteúdo dos arquivos que você abre
> - Comandos executados no terminal
>
> O objetivo é medir custo e adoção da ferramenta para justificar/otimizar o
> investimento. Nenhum dado individual será usado para avaliação de performance
> individual.
>
> Dúvidas: contato do time de plataforma.

Ajustar redação com o RH da Boa Vista.
