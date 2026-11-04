#!/usr/bin/env bash
# Abre a tela de um monitor do ConecTorno em modo quiosque (mostra uma página de espera até o servidor responder).
# Uso: ./iniciar-monitor.sh <url-do-servidor> [numero-do-monitor] [girar: 0, 90 ou 270]
# Exemplo: ./iniciar-monitor.sh http://192.168.137.1:8080 1 90   (monitor de pé)
set -uo pipefail

URL="${1:-}"
MONITOR="${2:-1}"
GIRAR="${3:-0}"
case "$GIRAR" in 90|270) EXTRA_URL="&girar=$GIRAR" ;; *) EXTRA_URL="" ;; esac
[ -n "$URL" ] || { echo "Uso: $0 <url-do-servidor> [numero-do-monitor]"; exit 1; }
URL="${URL%/}"

# Garante uma única cópia rodando, mesmo que a área de trabalho chame o script mais de uma vez.
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/conectorno-monitor.lock"
flock -n 9 || exit 0

# Enquanto o servidor não responde (ex.: o PC do professor ainda não abriu o ConecTorno), a tela mostra
# a página de espera, que entra no monitor sozinha quando o servidor aparecer.
# Sem a página (script copiado para outro lugar), espera aqui mesmo antes de abrir o navegador.
ESPERA="$(cd "$(dirname "$0")" && pwd)/aguardando.html"
if [ -f "$ESPERA" ]; then
  ENDERECO="file://$ESPERA?servidor=$URL&monitor=$MONITOR$EXTRA_URL"
else
  until curl -s -o /dev/null --max-time 3 "$URL/api/monitor/$MONITOR/display"; do
    sleep 3
  done
  ENDERECO="$URL/?monitor=$MONITOR$EXTRA_URL"
fi

# Evita que a tela apague ou entre em descanso (só tem efeito em sessões X11).
xset s off -dpms s noblank 2>/dev/null || true

NAVEGADOR="$(command -v chromium-browser || command -v chromium)" || { echo "Chromium não encontrado."; exit 1; }

# Sem área de trabalho, o Chromium roda dentro do cage (Wayland) e precisa saber disso.
EXTRA=()
[ -z "${WAYLAND_DISPLAY:-}" ] || EXTRA+=(--ozone-platform=wayland)

# Se o navegador fechar ou travar, abre de novo.
while true; do
  "$NAVEGADOR" --kiosk --incognito --noerrdialogs --disable-infobars --no-first-run \
    --disable-session-crashed-bubble --check-for-update-interval=31536000 --password-store=basic \
    "${EXTRA[@]}" "$ENDERECO"
  sleep 3
done
