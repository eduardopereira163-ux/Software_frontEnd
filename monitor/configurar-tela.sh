#!/usr/bin/env bash
# Faz o Raspberry ligar SEM área de trabalho e abrir direto a tela de um monitor em tela cheia
# (Chromium dentro do cage). Usado pelo instalar-tela.sh e pelo instalar.sh; rode sem sudo.
# Uso: monitor/configurar-tela.sh <url-do-servidor> [numero-do-monitor] [girar: 0, 90 ou 270]
#   Ex.: monitor/configurar-tela.sh http://192.168.137.1:8080 1 90   (monitor de pé)
# Para mudar só o giro depois: monitor/girar-tela.sh 90
# Variável opcional: SERVICO_LOCAL=conectorno  → a tela espera o servidor deste Pi subir antes.
# Para desfazer: sudo systemctl disable conectorno-tela && sudo systemctl set-default graphical.target
set -euo pipefail

URL="${1:-}"
MONITOR="${2:-1}"
GIRAR="${3:-0}"
[ -n "$URL" ] || { echo "Uso: $0 <url-do-servidor> [numero-do-monitor]"; exit 1; }
case "$MONITOR" in [1-6]) ;; *) echo "ERRO: o número do monitor deve ser de 1 a 6."; exit 1 ;; esac
case "$GIRAR" in 0|90|270) ;; *) echo "ERRO: girar deve ser 0 (deitado), 90 ou 270 (de pé)."; exit 1 ;; esac
command -v cage >/dev/null || { echo "ERRO: o cage não está instalado (precisa de internet): sudo apt install cage"; exit 1; }
command -v chromium-browser >/dev/null || command -v chromium >/dev/null \
  || { echo "ERRO: o Chromium não está instalado: sudo apt install chromium-browser"; exit 1; }

PASTA="$(cd "$(dirname "$0")" && pwd)"
USUARIO="$(id -un)"
TELA=conectorno-tela
chmod +x "$PASTA/iniciar-monitor.sh"

DEPENDE=""
if [ -n "${SERVICO_LOCAL:-}" ]; then
  DEPENDE="Wants=$SERVICO_LOCAL.service
After=$SERVICO_LOCAL.service"
fi

# Acesso à placa de vídeo, à tela e ao teclado/mouse.
for grupo in video render input; do
  if getent group "$grupo" >/dev/null; then sudo usermod -aG "$grupo" "$USUARIO"; fi
done

# Sessão de login própria para a tela (o cage precisa dela para usar a placa de vídeo).
sudo tee /etc/pam.d/$TELA >/dev/null <<'FIM'
auth    required pam_unix.so nullok
account required pam_unix.so
session required pam_unix.so
session required pam_systemd.so
FIM

sudo tee /etc/systemd/system/$TELA.service >/dev/null <<FIM
[Unit]
Description=ConecTorno - tela do Monitor $MONITOR em modo quiosque (sem área de trabalho)
After=systemd-user-sessions.service getty@tty1.service network-online.target
$DEPENDE
# Ocupa o lugar do login em modo texto na tela principal (tty1).
Conflicts=getty@tty1.service
# Se a tela falhar muitas vezes seguidas, desiste e devolve o login à tela (em vez de ficar tudo preto).
StartLimitIntervalSec=300
StartLimitBurst=10
OnFailure=getty@tty1.service

[Service]
User=$USUARIO
PAMName=$TELA
TTYPath=/dev/tty1
TTYReset=yes
TTYVHangup=yes
TTYVTDisallocate=yes
StandardInput=tty-fail
StandardOutput=journal
StandardError=journal
UtmpIdentifier=tty1
UtmpMode=user
# -s permite trocar de terminal (Ctrl+Alt+F2) para fazer manutenção.
ExecStart=/usr/bin/cage -s -- $PASTA/iniciar-monitor.sh $URL $MONITOR $GIRAR
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
FIM
sudo systemctl daemon-reload
sudo systemctl enable $TELA >/dev/null

# Desliga a área de trabalho: o Pi passa a ligar em modo texto e só a tela do quiosque aparece.
if command -v raspi-config >/dev/null; then
  sudo raspi-config nonint do_boot_behaviour B1 || sudo systemctl set-default multi-user.target
else
  sudo systemctl set-default multi-user.target
fi
# Tira a abertura automática antiga (de quando o quiosque rodava dentro da área de trabalho).
rm -f "$HOME/.config/autostart/conectorno-monitor.desktop"

echo "Ao ligar, o Pi vai direto para a tela do Monitor $MONITOR ($URL), sem área de trabalho."
[ "$GIRAR" = 0 ] || echo "Imagem girada $GIRAR° (monitor de pé). Se ficar de cabeça para baixo: monitor/girar-tela.sh $([ "$GIRAR" = 90 ] && echo 270 || echo 90)"
echo "Manutenção: Ctrl+Alt+F2 abre um terminal de login; Ctrl+Alt+F1 volta para a tela."
