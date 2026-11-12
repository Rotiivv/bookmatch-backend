#!/usr/bin/env bash
# Publica na VPS a versao informada em IMAGE_TAG (o hash do commit).
#
# Executado pelo workflow de CD (.github/workflows/cd.yml), que antes envia
# este arquivo, o compose.prod.yaml e o Caddyfile para ~/bookmatch e faz login
# no GHCR. A VPS nao tem o codigo-fonte: as imagens chegam prontas.
#
# Manualmente (com login no GHCR feito antes):
#   IMAGE_TAG=<hash completo do commit> bash ~/bookmatch/deploy/deploy.sh
set -Eeuo pipefail

cd "$(dirname "$0")/.."

: "${IMAGE_TAG:?Informe a versao: IMAGE_TAG=<hash do commit> bash deploy/deploy.sh}"
export IMAGE_TAG

if [ ! -f .env ]; then
  echo "Arquivo .env nao encontrado em $(pwd). Use deploy/env.production.example como modelo." >&2
  exit 1
fi

compose() {
  docker compose -f compose.prod.yaml --profile tools "$@"
}

# Se algo falhar, mostra a causa no log (inclusive no GitHub Actions).
on_error() {
  echo "==> Falhou. Ultimos logs da API e do banco:" >&2
  compose logs --no-color --tail=40 api mariadb >&2 || true
}
trap on_error ERR

echo "==> Versao: $IMAGE_TAG"

# So as imagens da API. Caddy e MariaDB tem versao fixa no compose e o "up"
# so as baixa se faltarem: o deploy nao depende do Docker Hub a cada vez.
echo "==> Baixando as imagens da API e do migrate"
compose pull --quiet api migrate

echo "==> Subindo o banco"
compose up -d --wait mariadb

echo "==> Aplicando as migrations"
compose run --rm migrate

echo "==> Subindo a API e o proxy"
compose up -d --wait --wait-timeout 120 api caddy

# Apaga as imagens deste projeto de outras versoes. Mantem as da versao atual
# (inclusive a do migrate, que nao fica rodando): assim o proximo deploy so
# baixa as camadas que mudaram. O filtro de label garante que nada de outros
# projetos seja removido. Para voltar versao, o CD baixa de novo do GHCR.
echo "==> Removendo imagens antigas"
docker image ls \
  --filter "label=org.opencontainers.image.source=https://github.com/Rotiivv/bookmatch-backend" \
  --format '{{.Repository}}:{{.Tag}}' \
  | grep -v ":$IMAGE_TAG\$" \
  | xargs -r docker image rm > /dev/null || true
docker image prune -f > /dev/null

compose ps
echo "==> Deploy concluido"
