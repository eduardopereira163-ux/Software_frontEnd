#!/usr/bin/env bash
# Muda o giro da tela do monitor no Raspberry, sem reinstalar.
# Uso: monitor/girar-tela.sh 90    → monitor de pé (imagem gira no sentido horário)
#      monitor/girar-tela.sh 270   → de pé, para o outro lado (use se ficou de cabeça para baixo)
#      monitor/girar-tela.sh 0     → monitor deitado
set -euo pipefail

GIRAR="${1:-}"
case "$GIRAR" in 0|90|270) ;; *) echo "Uso: $0 0|90|270"; exit 1 ;; esac
UNIDADE=/etc/systemd/system/conectorno-tela.service
[ -f "$UNIDADE" ] || { echo "ERRO: a tela ainda não foi configurada (rode ./instalar-tela.sh)."; exit 1; }

# A linha termina em: iniciar-monitor.sh <url> <monitor> [girar]; troca (ou acrescenta) o último número.
sudo sed -i -E "s#^(ExecStart=.*iniciar-monitor\.sh [^ ]+ [1-6])( (0|90|270))?\$#\1 $GIRAR#" "$UNIDADE"
grep -q "iniciar-monitor\.sh [^ ]* [1-6] $GIRAR\$" "$UNIDADE" || { echo "ERRO: não consegui alterar $UNIDADE."; exit 1; }
sudo systemctl daemon-reload
sudo systemctl restart conectorno-tela
echo "Pronto: tela girada $GIRAR°."
