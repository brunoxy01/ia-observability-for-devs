#!/usr/bin/env bash
# gerar-pdf.sh — regera o PDF a partir do HTML depois de atualizar as imagens
#
# Uso: bash gerar-pdf.sh
set -euo pipefail

cd "$(dirname "$0")"

CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
if [ ! -x "$CHROME" ]; then
  echo "❌ Google Chrome não encontrado em $CHROME"
  echo "   Instale o Chrome ou abra relatorio-poc-boa-vista.html no browser e faça Cmd+P → Salvar como PDF."
  exit 1
fi

echo "🔄 Gerando PDF..."
"$CHROME" \
  --headless \
  --disable-gpu \
  --no-pdf-header-footer \
  --print-to-pdf-no-header \
  --print-to-pdf=relatorio-poc-boa-vista.pdf \
  "file://$PWD/relatorio-poc-boa-vista.html" 2>&1 | tail -3

echo ""
echo "✅ PDF gerado: $PWD/relatorio-poc-boa-vista.pdf"
ls -lh relatorio-poc-boa-vista.pdf

echo ""
echo "🔍 Abrindo o PDF..."
open relatorio-poc-boa-vista.pdf
