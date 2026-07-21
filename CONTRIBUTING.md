# Contribuindo

Repo público para o time — sintam-se à vontade para abrir PR ou issue.

## Como rodar localmente

- **Collector + Copilot Chat**: siga o [Quickstart do README](README.md#quickstart-piloto-de-1-dev).
- **dt-evals (avaliação de qualidade)**: siga [docs/07-evaluations.md](docs/07-evaluations.md),
  scaffold pronto em [`evals/`](evals).

## Regras básicas

- **Nunca commitar credenciais reais** — `.env`, `dt-eval.yaml` (com token/apiKey) e
  qualquer arquivo com `DT_INGEST_TOKEN`/`DT_API_TOKEN`/API key de LLM ficam de fora
  do git (ver `.gitignore`). Use os `.example` como template.
- **Dashboards**: editar `dashboards/copilot-chat-observability.json` direto é ok;
  ao importar de volta do Dynatrace UI, confira que nenhum filtro/token de conta
  específica vazou pro JSON antes de commitar.
- **DQL novo**: adicione em [docs/05-dql-queries.md](docs/05-dql-queries.md) (ou
  [docs/07-evaluations.md](docs/07-evaluations.md) se for sobre evaluations) junto
  com uma linha explicando o que a query responde.
- **Métricas novas de eval**: `npx dt-evals evaluators add` no diretório `evals/`
  cria um evaluator custom; documente o motivo de adicionar em vez de usar um
  built-in existente.

## Estrutura

Ver o índice completo em [README → Estrutura do repositório](README.md#estrutura-do-repositório).
