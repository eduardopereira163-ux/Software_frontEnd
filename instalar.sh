#!/usr/bin/env bash
# Instala o frontend do ConecTorno no projeto que já roda no Raspberry Pi.
# Uso: ./instalar.sh <pasta-do-projeto> [servico-systemd] [url-do-servidor]
# Exemplo: ./instalar.sh /home/pi/conectorno conectorno http://localhost:5000
set -euo pipefail

ORIGEM="$(cd "$(dirname "$0")" && pwd)/static"
PROJETO="${1:-}"
SERVICO="${2:-}"
URL="${3:-}"

erro() { echo "ERRO: $*" >&2; exit 1; }

if [ -z "$PROJETO" ]; then
  echo "Uso: $0 <pasta-do-projeto> [servico-systemd] [url-do-servidor]"
  echo "Veja o README.md para descobrir a pasta e o serviço no Raspberry."
  exit 1
fi

[ -f "$ORIGEM/index.html" ] || erro "pasta static deste pacote não encontrada em $ORIGEM."
[ -d "$PROJETO" ] || erro "a pasta do projeto '$PROJETO' não existe."
# Exige uma static existente para não instalar na pasta errada por engano.
[ -d "$PROJETO/static" ] || erro "'$PROJETO' não tem uma pasta static. Confirme a pasta do projeto."
ls "$PROJETO"/*.py >/dev/null 2>&1 || echo "AVISO: nenhum arquivo .py em '$PROJETO'. Confira se é a pasta do servidor."

# 1. Backup da static atual, ao lado dela.
BACKUP="$PROJETO/static_backup_$(date +%Y%m%d-%H%M%S)"
cp -a "$PROJETO/static" "$BACKUP"
echo "Backup criado em: $BACKUP"

# 2. Copia os arquivos novos por cima, sem apagar nada que já exista
#    (uploads ou outros arquivos do servidor dentro de static são preservados).
cp -a "$ORIGEM/." "$PROJETO/static/"
echo "Arquivos do site copiados para: $PROJETO/static"

# 3. Reinicia o serviço existente, se informado.
if [ -n "$SERVICO" ]; then
  sudo systemctl restart "$SERVICO"
  sleep 2
  if systemctl is-active --quiet "$SERVICO"; then
    echo "Serviço '$SERVICO' reiniciado e ativo."
  else
    erro "o serviço '$SERVICO' não ficou ativo. Veja: sudo journalctl -u $SERVICO -n 50"
  fi
else
  echo "Nenhum serviço informado: reinicie o servidor do ConecTorno manualmente."
fi

# 4. Teste rápido das rotas usadas pelo site, se a URL foi informada.
if [ -n "$URL" ]; then
  echo "Testando a API em $URL ..."
  for rota in / /api/auth/status /api/monitor/1/display; do
    codigo="$(curl -s -o /dev/null -w '%{http_code}' "$URL$rota" || echo 000)"
    if [ "$codigo" = "200" ]; then
      echo "  OK    $rota"
    else
      echo "  FALHA $rota (HTTP $codigo)"
    fi
  done
  echo "Se houve FALHA, veja a seção 'Problemas comuns' do README.md."
fi

echo
echo "Para desfazer: cp -a \"$BACKUP/.\" \"$PROJETO/static/\""
