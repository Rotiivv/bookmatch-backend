#!/usr/bin/env bash
# Teste de fumaca do pacote de producao.
#
# Executa o mesmo roteiro do deploy/deploy.sh numa copia descartavel:
# monta as imagens (em vez de baixar do GHCR), sobe o banco, aplica as
# migrations, sobe a API e chama o /health. Nao sobe o Caddy (nao ha dominio
# nem certificado) e apaga tudo no fim.
#
# Roda no CI, antes do merge, e tambem manualmente:
#   bash deploy/smoke-test.sh
#
# Usa um projeto Compose proprio (bookmatch-smoke) e um .env temporario, entao
# nao toca nos containers, volumes nem no .env de producao.
set -Eeuo pipefail

cd "$(dirname "$0")/.."

PROJECT=bookmatch-smoke
ENV_FILE="$(mktemp)"

compose() {
  docker compose -p "$PROJECT" --env-file "$ENV_FILE" \
    -f compose.prod.yaml -f compose.build.yaml --profile tools "$@"
}

cleanup() {
  compose down -v --remove-orphans > /dev/null 2>&1 || true
  rm -f "$ENV_FILE"
}
trap cleanup EXIT

on_error() {
  echo "==> Falhou. Ultimos logs da API e do banco:" >&2
  compose logs --no-color --tail=40 api mariadb >&2 || true
}
trap on_error ERR

cat > "$ENV_FILE" <<EOF
IMAGE_TAG=smoke
API_DOMAIN=localhost
MARIADB_DATABASE=bookmatch
MARIADB_USER=bookmatch
MARIADB_PASSWORD=smoketest-$RANDOM$RANDOM
MARIADB_ROOT_PASSWORD=smoketest-root-$RANDOM$RANDOM
EOF

echo "==> Construindo as imagens"
compose build api migrate

echo "==> Subindo o banco"
compose up -d --wait mariadb

echo "==> Aplicando as migrations"
if ! migrate_log="$(compose run --rm migrate 2>&1)"; then
  echo "$migrate_log"
  false
fi
echo "$migrate_log"
# A CLI do Prisma so avisa (nao falha) quando falta o OpenSSL, mas as
# migrations podem quebrar depois. Tratamos o aviso como erro.
if grep -q "failed to detect the libssl/openssl version" <<< "$migrate_log"; then
  echo "==> A imagem migrate esta sem OpenSSL (exigido pela CLI do Prisma)." >&2
  false
fi

echo "==> Subindo a API"
compose up -d --wait --wait-timeout 120 api

echo "==> Chamando /health"
compose exec -T api node -e "
  fetch('http://localhost:3000/health')
    .then(async (r) => { console.log(r.status, await r.text()); process.exit(r.ok ? 0 : 1); })
    .catch((e) => { console.error(e); process.exit(1); });
"

echo "==> Smoke test concluido"
