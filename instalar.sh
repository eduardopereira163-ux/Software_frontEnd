#!/usr/bin/env bash
# Instala o ConecTorno completo no Raspberry Pi:
#   1. servidor como serviço (sobe sozinho ao ligar o Pi);
#   2. tela deste Pi em modo quiosque mostrando um monitor (opcional).
# Uso (como usuário normal, sem sudo):
#   ./instalar.sh                  → servidor na porta 80 e esta tela como Monitor 1
#   ./instalar.sh 80 2             → esta tela como Monitor 2
#   ./instalar.sh 80 sem-monitor   → só o servidor
# Para atualizar depois: git pull && ./instalar.sh
set -euo pipefail

PASTA="$(cd "$(dirname "$0")" && pwd)"
PORTA="${1:-80}"
MONITOR="${2:-1}"
USUARIO="$(id -un)"
SERVICO=conectorno

erro() { echo "ERRO: $*" >&2; exit 1; }
passo() { echo; echo "==> $*"; }

[ "$USUARIO" != "root" ] || erro "rode sem sudo (o script pede a senha quando precisar)."
command -v python3 >/dev/null || erro "python3 não encontrado."
python3 -c 'import sys; sys.exit(sys.version_info < (3, 9))' || erro "é preciso Python 3.9 ou mais novo."
[ -f "$PASTA/servidor/servidor.py" ] || erro "servidor/servidor.py não encontrado em $PASTA."

passo "Instalando programas de apoio (conversor de PDF e navegador)"
PACOTES=""
command -v pdftoppm >/dev/null || PACOTES="$PACOTES poppler-utils"
command -v curl >/dev/null || PACOTES="$PACOTES curl"
PRECISA_NAVEGADOR=0
if [ "$MONITOR" != "sem-monitor" ] && ! command -v chromium-browser >/dev/null && ! command -v chromium >/dev/null; then
  PRECISA_NAVEGADOR=1
fi
if [ -n "$PACOTES" ] || [ "$PRECISA_NAVEGADOR" = 1 ]; then
  sudo apt-get update || true
  [ -z "$PACOTES" ] || sudo apt-get install -y $PACOTES \
    || echo "AVISO: não foi possível instalar$PACOTES. Sem internet? Sem o poppler-utils os PDFs aparecem sem conversão."
  if [ "$PRECISA_NAVEGADOR" = 1 ]; then
    sudo apt-get install -y chromium-browser || sudo apt-get install -y chromium \
      || echo "AVISO: não foi possível instalar o Chromium; a tela do monitor não vai abrir sozinha."
  fi
else
  echo "Tudo já instalado."
fi
command -v curl >/dev/null || erro "curl é necessário: conecte o Pi à internet e rode de novo."

passo "Criando o serviço '$SERVICO' (porta $PORTA)"
sudo tee /etc/systemd/system/$SERVICO.service >/dev/null <<EOF
[Unit]
Description=ConecTorno - servidor do painel e dos monitores
After=network.target

[Service]
User=$USUARIO
WorkingDirectory=$PASTA
Environment=CONECTORNO_PORTA=$PORTA
ExecStart=/usr/bin/env python3 $PASTA/servidor/servidor.py
Restart=always
RestartSec=3
# Permite usar a porta 80 sem rodar como root.
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable $SERVICO >/dev/null
sudo systemctl restart $SERVICO

URL="http://localhost$([ "$PORTA" = 80 ] || echo ":$PORTA")"
for _ in $(seq 1 20); do
  curl -s -o /dev/null "$URL/api/auth/status" && break
  sleep 1
done
curl -s -o /dev/null "$URL/api/auth/status" || erro "o servidor não respondeu. Veja: sudo journalctl -u $SERVICO -n 50"
echo "Servidor no ar."

if [ "$MONITOR" != "sem-monitor" ]; then
  passo "Configurando esta tela como Monitor $MONITOR (modo quiosque)"
  chmod +x "$PASTA/monitor/"*.sh
  "$PASTA/monitor/configurar-monitor.sh" "$URL" "$MONITOR"
fi

passo "Pronto!"
SUFIXO="$([ "$PORTA" = 80 ] || echo ":$PORTA")"
echo "Painel do professor (celular conectado no Wi-Fi do Pi):"
for ip in $(hostname -I); do
  case "$ip" in *:*) ;; *) echo "   http://$ip$SUFIXO" ;; esac
done
echo "Monitores: o mesmo endereço com /?monitor=1 até /?monitor=6"
[ "$MONITOR" = "sem-monitor" ] || echo "Reinicie para a tela abrir sozinha: sudo reboot"
echo
echo "Comandos úteis:"
echo "   sudo systemctl status $SERVICO       (situação do servidor)"
echo "   sudo journalctl -u $SERVICO -f       (registro em tempo real)"
echo "   Dados e arquivos enviados ficam em: $PASTA/dados"
