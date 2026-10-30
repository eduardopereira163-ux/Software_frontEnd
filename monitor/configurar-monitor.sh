#!/usr/bin/env bash
# Configura este aparelho para abrir a tela do monitor sozinho sempre que a área de trabalho iniciar.
# Uso: ./configurar-monitor.sh <url-do-servidor> [numero-do-monitor]
#   No próprio Raspberry (tela ligada no HDMI do Pi): ./configurar-monitor.sh http://localhost:5000 1
#   Em outro aparelho conectado ao Wi-Fi do Pi:       ./configurar-monitor.sh http://IP-DO-PI:5000 2
# Para desativar: rm ~/.config/autostart/conectorno-monitor.desktop
set -euo pipefail

URL="${1:-}"
MONITOR="${2:-1}"
if [ -z "$URL" ]; then
  echo "Uso: $0 <url-do-servidor> [numero-do-monitor]"
  exit 1
fi
case "$MONITOR" in [1-6]) ;; *) echo "ERRO: o número do monitor deve ser de 1 a 6."; exit 1 ;; esac

command -v chromium-browser >/dev/null || command -v chromium >/dev/null \
  || { echo "ERRO: instale o Chromium: sudo apt install chromium-browser"; exit 1; }
command -v curl >/dev/null || { echo "ERRO: instale o curl: sudo apt install curl"; exit 1; }

# Copia o iniciador para uma pasta fixa, para continuar funcionando mesmo se esta pasta for apagada.
DESTINO="$HOME/.local/share/conectorno"
mkdir -p "$DESTINO" "$HOME/.config/autostart"
cp "$(cd "$(dirname "$0")" && pwd)/iniciar-monitor.sh" "$DESTINO/iniciar-monitor.sh"
chmod +x "$DESTINO/iniciar-monitor.sh"

cat > "$HOME/.config/autostart/conectorno-monitor.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=ConecTorno Monitor $MONITOR
Exec=$DESTINO/iniciar-monitor.sh $URL $MONITOR
X-GNOME-Autostart-enabled=true
EOF

echo "Pronto: ao iniciar a área de trabalho, este aparelho abre o Monitor$MONITOR de $URL em tela cheia."
echo "Para testar agora sem reiniciar: $DESTINO/iniciar-monitor.sh $URL $MONITOR"
echo "Para sair do modo quiosque: Alt+F4."
