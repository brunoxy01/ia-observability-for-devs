# Como gerar o PDF

O relatório está em [relatorio-poc-boa-vista.html](relatorio-poc-boa-vista.html) e referencia 11 imagens na pasta [images/](images/).

## Passo 1 — Salvar as capturas de tela

Salve os screenshots que você tirou do Dynatrace com **exatamente** estes nomes na pasta `images/`:

| Arquivo | Conteúdo |
|---|---|
| `01-sanity-check.png` | Notebook — Sanity check com 7 records de agents |
| `02-volume-24h.png` | Notebook — Volume 24h (41 chats / 28 tools / 26 sessions) |
| `03-custo-por-modelo.png` | Notebook — Custo total por modelo (US$227 Claude Opus) |
| `04-custo-por-dev.png` | Notebook — Custo por dev top 20 (bruno.silva@boavista.com.br) |
| `05-custo-por-time.png` | Notebook — Custo por time 7 dias |
| `06-latencia-modelo.png` | Notebook — Latência P50/P95/P99 por modelo |
| `07-modelos-adocao.png` | Notebook — Modelos mais usados 7 dias |
| `08-ai-observability-app.png` | App AI Observability — service copilot-chat com Prompts |
| `09-agents-topology.png` | App AI Observability — Agents topology com grafo |
| `10-distributed-trace.png` | Distributed Tracing — invoke_agent GitHub Copilot Chat 4m18s |
| `11-prompts-stream.png` | App AI Observability — Prompts stream com input/output |

## Passo 2 — Abrir no navegador

```bash
open report/relatorio-poc-boa-vista.html
```

Ou duplo-clique no arquivo `relatorio-poc-boa-vista.html`.

## Passo 3 — Exportar para PDF

No Chrome/Safari:
1. `Cmd + P`
2. Em **Destino**, escolha **Salvar como PDF**
3. Em **Papel**, escolha **A4** (retrato)
4. Em **Margens**, deixe **Padrão** ou **Mínimas**
5. Marque **Gráficos de segundo plano** (Chrome) ou **Imprimir plano de fundo** (Safari) para preservar as cores
6. Clique em **Salvar** → escolha `relatorio-poc-boa-vista.pdf`

## Ajustes finos após a primeira exportação

Se as imagens ficarem pequenas ou o layout quebrar:

- No Chrome: **Mais configurações** → **Escala** → aumentar para 90-95%
- Se o texto sair colado: **Margens** → **Personalizado** → 15mm
- Se preferir mais páginas mas com melhor legibilidade: **Papel** → **Ofício** (Legal)

## Sem screenshots ainda?

Você pode gerar o PDF mesmo assim — os placeholders vão aparecer no lugar das imagens.
Depois é só substituir os arquivos em `images/` e re-imprimir.
