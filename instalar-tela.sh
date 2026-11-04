#!/usr/bin/env bash
# Prepara o Raspberry como TELA do torno no formato "servidor no PC do professor":
#   1. o Pi entra no Hotspot móvel do PC do professor (sempre que ligar);
#   2. liga sem área de trabalho e abre o monitor em tela cheia, esperando o PC aparecer.
# O servidor NÃO roda no Pi: ele roda no PC (pasta ConecTorno-PC, "Iniciar ConecTorno").
# Uso (como usuário normal, sem sudo, com o Pi ligado à internet por cabo ou Wi-Fi):
#   ./instalar-tela.sh        → esta tela vira o Monitor 1
#   ./instalar-tela.sh 2      → Monitor 2
# O nome e a senha do hotspot do PC são perguntados. Para não perguntar:
#   WIFI_NOME=ConecTorno WIFI_SENHA=senai12345 ./instalar-tela.sh
# Outro endereço de servidor (padrão: hotspot do Windows, porta 8080):
#   SERVIDOR=http://192.168.137.1:8080 ./instalar-tela.sh
# Monitor de pé (padrão: GIRAR=90). Deitado: GIRAR=0. De cabeça para baixo? Use GIRAR=270.
#   Para mudar só o giro depois, sem reinstalar: monitor/girar-tela.sh 270
set -euo pipefail

PASTA="$(cd "$(dirname "$0")" && pwd)"
MONITOR="${1:-1}"
SERVIDOR="${SERVIDOR:-http://192.168.137.1:8080}"
GIRAR="${GIRAR:-90}"
CON_PC=hotspot-professor   # nome da conexão no NetworkManager (não é o nome da rede)

erro() { echo "ERRO: $*" >&2; exit 1; }
passo() { echo; echo "==> $*"; }

[ "$(id -un)" != "root" ] || erro "rode sem sudo (o script pede a senha quando precisar)."
case "$MONITOR" in [1-6]) ;; *) erro "o número do monitor deve ser de 1 a 6." ;; esac
case "$GIRAR" in 0|90|270) ;; *) erro "GIRAR deve ser 0 (deitado), 90 ou 270 (de pé)." ;; esac
command -v nmcli >/dev/null || erro "NetworkManager não encontrado (use o Raspberry Pi OS atual, não o 'Legacy')."

# Senha/nome só com letras, números, espaço, ponto, hífen e sublinhado: o teclado do Pi vem em inglês e
# troca símbolos como @ " ç / ? (a senha digitada aqui sairia diferente da do PC).
valido() { local LC_ALL=C; [[ "$1" =~ ^[A-Za-z0-9._\ -]+$ ]]; }  # LC_ALL=C: "a-z" sem letras acentuadas

passo "Rede: hotspot do PC do professor"
NOME="${WIFI_NOME:-}"
SENHA="${WIFI_SENHA:-}"
if [ -z "$NOME" ] || [ -z "$SENHA" ]; then
  [ -t 0 ] || erro "informe a rede: WIFI_NOME=ConecTorno WIFI_SENHA=suasenha ./instalar-tela.sh"
  echo "Use o mesmo nome e senha do Hotspot móvel do PC (Configurações → Rede e Internet → Hotspot móvel)."
  while [ -z "$NOME" ]; do
    read -r -p "Nome da rede [ConecTorno]: " NOME
    NOME="${NOME:-ConecTorno}"
    valido "$NOME" && [ "${#NOME}" -le 32 ] || { echo "Use só letras, números, espaço, ponto, hífen ou sublinhado (até 32)."; NOME=""; }
  done
  while [ -z "$SENHA" ]; do
    read -r -p "Senha da rede (8 a 63 caracteres): " SENHA
    valido "$SENHA" && [ "${#SENHA}" -ge 8 ] && [ "${#SENHA}" -le 63 ] \
      || { echo "Use de 8 a 63 letras ou números (sem símbolos)."; SENHA=""; }
  done
fi
valido "$NOME" && [ "${#NOME}" -le 32 ] || erro "nome da rede inválido: use só letras, números, espaço, ponto, hífen ou sublinhado."
valido "$SENHA" && [ "${#SENHA}" -ge 8 ] && [ "${#SENHA}" -le 63 ] || erro "senha inválida: use de 8 a 63 letras ou números."

passo "Instalando programas (navegador e tela cheia)"
PACOTES=""
command -v cage >/dev/null || PACOTES="$PACOTES cage"
command -v curl >/dev/null || PACOTES="$PACOTES curl"
if [ -n "$PACOTES" ] || { ! command -v chromium-browser >/dev/null && ! command -v chromium >/dev/null; }; then
  sudo apt-get update || true
  [ -z "$PACOTES" ] || sudo apt-get install -y $PACOTES || erro "não consegui instalar$PACOTES. O Pi está com internet?"
  if ! command -v chromium-browser >/dev/null && ! command -v chromium >/dev/null; then
    sudo apt-get install -y chromium-browser || sudo apt-get install -y chromium || erro "não consegui instalar o Chromium."
  fi
else
  echo "Tudo já instalado."
fi

passo "Desfazendo o formato antigo (Pi como servidor e Access Point)"
if systemctl cat conectorno.service >/dev/null 2>&1; then
  sudo systemctl disable --now conectorno >/dev/null 2>&1 || true
  echo "Servidor do Pi desligado (agora o servidor é o PC)."
fi
# Apaga todas as conexões de Access Point antigas chamadas ConecTorno (podem ter ficado repetidas).
for uuid in $(nmcli -t -f UUID,NAME con show | awk -F: '$2 == "ConecTorno" { print $1 }'); do
  sudo nmcli con delete "$uuid" >/dev/null && echo "Access Point antigo removido."
done
sudo rm -f /etc/NetworkManager/dnsmasq-shared.d/conectorno.conf

passo "Conectando o Pi ao hotspot \"$NOME\""
# Sem o país do Wi-Fi definido, o Raspberry Pi OS deixa o Wi-Fi bloqueado.
if command -v raspi-config >/dev/null && [ -z "$(sudo raspi-config nonint get_wifi_country 2>/dev/null || true)" ]; then
  sudo raspi-config nonint do_wifi_country "${WIFI_PAIS:-BR}" || echo "AVISO: defina o país do Wi-Fi: sudo raspi-config → Localisation → WLAN Country."
fi
sudo rfkill unblock wifi 2>/dev/null || true
sudo nmcli radio wifi on || true
# Cria (ou recria) a conexão já com tudo num comando só; funciona mesmo com o hotspot desligado agora.
for uuid in $(nmcli -t -f UUID,NAME con show | awk -F: -v n="$CON_PC" '$2 == n { print $1 }'); do
  sudo nmcli con delete "$uuid" >/dev/null
done
sudo nmcli con add type wifi ifname wlan0 con-name "$CON_PC" ssid "$NOME" \
  wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$SENHA" \
  connection.autoconnect yes connection.autoconnect-priority 100 >/dev/null
echo "Pronto: o Pi entra sozinho na rede \"$NOME\" sempre que ela estiver ligada."

passo "Configurando esta tela como Monitor $MONITOR"
chmod +x "$PASTA/monitor/"*.sh
"$PASTA/monitor/configurar-tela.sh" "$SERVIDOR" "$MONITOR" "$GIRAR"

passo "Pronto! Reinicie o Pi: sudo reboot"
echo "Ao ligar, a tela mostra \"Aguardando o computador do professor\" até o PC estar com:"
echo "   - o Hotspot móvel ligado (rede \"$NOME\", banda 2,4 GHz);"
echo "   - o \"Iniciar ConecTorno\" aberto."
echo "Aí ela entra sozinha no Monitor $MONITOR ($SERVIDOR)."
echo
echo "Comandos úteis:"
echo "   nmcli dev status                          (o wlan0 deve aparecer conectado em \"$CON_PC\")"
echo "   curl -I $SERVIDOR                (testa se o Pi alcança o PC)"
echo "   sudo journalctl -u conectorno-tela -n 50  (erros da tela)"
echo "   vcgencmd get_throttled                    (0x0 = energia OK; outro valor = fonte fraca)"
