#!/usr/bin/env bash
# Publica a versao que esta no diretorio de trabalho.
#
# Executado na VPS pelo job "deploy" do CI, logo depois do checkout do commit
# aprovado. Tambem pode ser executado manualmente:
#   cd ~/bookmatch-backend && bash deploy/deploy.sh
set -euo pipefail

cd "$(dirname "$0")/.."

if [ ! -f .env ]; then
  echo "Arquivo .env nao encontrado em $(pwd). Use deploy/env.production.example como modelo." >&2
  exit 1
fi

compose() {
  docker compose -f compose.prod.yaml --profile tools "$@"
}

echo "==> Versao: $(git rev-parse --short HEAD)"

echo "==> Construindo as imagens"
compose build api migrate

echo "==> Subindo o banco"
compose up -d --wait mariadb

echo "==> Aplicando as migrations"
compose run --rm migrate

echo "==> Subindo a API e o proxy"
compose up -d --wait --wait-timeout 120 api caddy

echo "==> Removendo imagens antigas"
docker image prune -f > /dev/null

compose ps
echo "==> Deploy concluido"
