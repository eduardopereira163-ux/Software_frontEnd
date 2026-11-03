#!/usr/bin/env bash
# Instala o ConecTorno completo no Raspberry Pi:
#   1. servidor como serviço (sobe sozinho ao ligar o Pi);
#   2. Wi-Fi próprio do Pi (Access Point), sempre ligado, para os celulares enviarem arquivos;
#   3. tela deste Pi em modo quiosque mostrando um monitor (opcional).
# Uso (como usuário normal, sem sudo, com o Pi ainda ligado à internet):
#   ./instalar.sh                  → servidor na porta 80 e esta tela como Monitor 1
#   ./instalar.sh 80 2             → esta tela como Monitor 2
#   ./instalar.sh 80 sem-monitor   → só o servidor
# O nome e a senha do Wi-Fi são perguntados na primeira instalação. Para não perguntar:
#   WIFI_NOME=Torno1 WIFI_SENHA=minhasenha ./instalar.sh
#   SEM_WIFI=1 ./instalar.sh       → não mexe no Wi-Fi
# O Access Point só liga depois de reiniciar (até lá o Pi continua na internet).
# Para atualizar depois (com cabo de rede): git pull && ./instalar.sh
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

if [ -d /etc/NetworkManager ] && [ "$PORTA" = 80 ]; then
  passo "Fazendo o celular manter o Wi-Fi do Pi (que não tem internet)"
  # O DNS do hotspot aponta os testes de internet dos celulares para o Pi, e o servidor responde que há internet.
  # Sem isso, muitos celulares desconectam do Wi-Fi do Pi assim que percebem que ele não tem internet.
  sudo mkdir -p /etc/NetworkManager/dnsmasq-shared.d
  {
    for dominio in connectivitycheck.gstatic.com connectivitycheck.android.com clients1.google.com \
      clients3.google.com captive.apple.com www.apple.com www.msftconnecttest.com www.msftncsi.com; do
      echo "interface-name=$dominio,wlan0"
    done
  } | sudo tee /etc/NetworkManager/dnsmasq-shared.d/conectorno.conf >/dev/null
  echo "Vale na próxima vez que o hotspot ligar (reinicie o Pi)."
fi

CON_WIFI=ConecTorno   # nome da conexão no NetworkManager (não é o nome da rede)
AP_OK=0
if [ "${SEM_WIFI:-0}" = 1 ]; then
  passo "Wi-Fi do Pi: não alterado (SEM_WIFI=1)"
elif ! command -v nmcli >/dev/null || ! nmcli -t -f DEVICE device 2>/dev/null | grep -qx wlan0; then
  passo "Wi-Fi do Pi"
  echo "AVISO: NetworkManager ou a placa wlan0 não encontrados; o Access Point não foi criado."
  echo "       (O Raspberry Pi OS 'Legacy'/Bullseye não usa NetworkManager.)"
else
  passo "Configurando o Wi-Fi próprio do Pi (Access Point)"
  # Sem o país do Wi-Fi definido, o Raspberry Pi OS deixa o Wi-Fi bloqueado.
  if command -v raspi-config >/dev/null && [ -z "$(sudo raspi-config nonint get_wifi_country 2>/dev/null || true)" ]; then
    sudo raspi-config nonint do_wifi_country "${WIFI_PAIS:-BR}" || echo "AVISO: não consegui definir o país do Wi-Fi (raspi-config → Localisation → WLAN Country)."
  fi
  sudo rfkill unblock wifi 2>/dev/null || true

  EXISTE=0
  nmcli con show "$CON_WIFI" >/dev/null 2>&1 && EXISTE=1
  NOME="${WIFI_NOME:-}"
  SENHA="${WIFI_SENHA:-}"
  if [ "$EXISTE" = 0 ] && [ -z "$SENHA" ]; then
    [ -t 0 ] || erro "informe a senha do Wi-Fi: WIFI_SENHA=suasenha ./instalar.sh"
    read -r -p "Nome da rede Wi-Fi do Pi [ConecTorno]: " NOME
    while :; do
      read -r -p "Senha da rede (8 a 63 caracteres): " SENHA
      [ "${#SENHA}" -ge 8 ] && [ "${#SENHA}" -le 63 ] && break
      echo "A senha precisa ter de 8 a 63 caracteres."
    done
  fi
  [ "$EXISTE" = 1 ] || NOME="${NOME:-ConecTorno}"
  [ -z "$SENHA" ] || { [ "${#SENHA}" -ge 8 ] && [ "${#SENHA}" -le 63 ]; } || erro "a senha do Wi-Fi precisa ter de 8 a 63 caracteres."
  [ "${#NOME}" -le 32 ] || erro "o nome da rede pode ter no máximo 32 caracteres."

  [ "$EXISTE" = 1 ] || sudo nmcli con add type wifi ifname wlan0 con-name "$CON_WIFI" ssid "$NOME" >/dev/null
  # Rede 2,4 GHz (todo celular enxerga), WPA2, IP fixo 10.42.0.1 e DHCP para os celulares.
  # pmf disable evita falhas de conexão de alguns iPhones/Androids com a placa do Pi.
  AJUSTES=(802-11-wireless.mode ap 802-11-wireless.band bg 802-11-wireless.channel 6
    ipv4.method shared ipv4.addresses 10.42.0.1/24 ipv6.method disabled
    wifi-sec.key-mgmt wpa-psk wifi-sec.proto rsn wifi-sec.pairwise ccmp wifi-sec.group ccmp wifi-sec.pmf disable
    connection.autoconnect yes connection.autoconnect-priority 100)
  [ -z "$NOME" ] || AJUSTES+=(802-11-wireless.ssid "$NOME")
  [ -z "$SENHA" ] || AJUSTES+=(wifi-sec.psk "$SENHA")
  sudo nmcli con modify "$CON_WIFI" "${AJUSTES[@]}"

  # A antena não faz Access Point e cliente ao mesmo tempo: as outras redes Wi-Fi deixam de conectar sozinhas.
  for uuid in $(nmcli -t -f UUID,TYPE con show | awk -F: '$2 == "802-11-wireless" { print $1 }'); do
    nome_con="$(nmcli -g connection.id con show "$uuid")"
    [ "$nome_con" != "$CON_WIFI" ] || continue
    [ "$(nmcli -g connection.autoconnect con show "$uuid")" = yes ] || continue
    sudo nmcli con modify "$uuid" connection.autoconnect no
    echo "O Wi-Fi \"$nome_con\" não conecta mais sozinho (para ter internet de novo, use cabo de rede)."
  done
  AP_NOME="$(nmcli -g 802-11-wireless.ssid con show "$CON_WIFI")"
  AP_SENHA="$(sudo nmcli -s -g 802-11-wireless-security.psk con show "$CON_WIFI" 2>/dev/null || true)"
  AP_OK=1
  echo "Access Point \"$AP_NOME\" configurado; liga sozinho a cada reinício."
fi

if [ "$MONITOR" != "sem-monitor" ]; then
  passo "Configurando esta tela como Monitor $MONITOR (modo quiosque)"
  chmod +x "$PASTA/monitor/"*.sh
  "$PASTA/monitor/configurar-monitor.sh" "$URL" "$MONITOR"
  # O quiosque abre junto com a área de trabalho: entra nela sem senha e não deixa a tela apagar.
  if command -v raspi-config >/dev/null; then
    sudo raspi-config nonint do_boot_behaviour B4 \
      || echo "AVISO: ative o login automático: sudo raspi-config → System Options → Boot / Auto Login → Desktop Autologin"
    sudo raspi-config nonint do_blanking 1 || true
  fi
fi

passo "Pronto!"
SUFIXO="$([ "$PORTA" = 80 ] || echo ":$PORTA")"
if [ "$AP_OK" = 1 ]; then
  echo "Depois de reiniciar, conecte o celular na rede Wi-Fi \"$AP_NOME\"${AP_SENHA:+ (senha: $AP_SENHA)}"
  echo "e abra o painel do professor em:  http://10.42.0.1$SUFIXO"
else
  echo "Painel do professor (celular conectado no Wi-Fi do Pi):"
  for ip in $(hostname -I); do
    case "$ip" in *:*) ;; *) echo "   http://$ip$SUFIXO" ;; esac
  done
fi
echo "Monitores: o mesmo endereço com /?monitor=1 até /?monitor=6"
if [ "$MONITOR" != "sem-monitor" ] || [ "$AP_OK" = 1 ]; then
  echo "Reinicie para ligar o Wi-Fi do Pi e abrir a tela sozinha: sudo reboot"
fi
echo
echo "Comandos úteis:"
echo "   sudo systemctl status $SERVICO       (situação do servidor)"
echo "   sudo journalctl -u $SERVICO -f       (registro em tempo real)"
echo "   Dados e arquivos enviados ficam em: $PASTA/dados"
