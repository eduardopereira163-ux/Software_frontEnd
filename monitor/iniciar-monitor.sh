#!/usr/bin/env bash
# Abre a tela de um monitor do ConecTorno em modo quiosque, assim que o servidor responder.
# Uso: ./iniciar-monitor.sh <url-do-servidor> [numero-do-monitor]
# Exemplo: ./iniciar-monitor.sh http://localhost:5000 1
set -uo pipefail

URL="${1:-}"
MONITOR="${2:-1}"
[ -n "$URL" ] || { echo "Uso: $0 <url-do-servidor> [numero-do-monitor]"; exit 1; }
URL="${URL%/}"

# Espera o servidor subir (no boot ele pode demorar alguns segundos a mais que a tela).
until curl -s -o /dev/null --max-time 3 "$URL/api/monitor/$MONITOR/display"; do
  sleep 3
done

# Evita que a tela apague ou entre em descanso (só tem efeito em sessões X11).
xset s off -dpms s noblank 2>/dev/null || true

NAVEGADOR="$(command -v chromium-browser || command -v chromium)" || { echo "Chromium não encontrado."; exit 1; }

# Se o navegador fechar ou travar, abre de novo.
while true; do
  "$NAVEGADOR" --kiosk --incognito --noerrdialogs --disable-infobars --no-first-run \
    --disable-session-crashed-bubble --check-for-update-interval=31536000 \
    "$URL/?monitor=$MONITOR"
  sleep 3
done
