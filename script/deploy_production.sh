#!/usr/bin/env bash
# Deploy Canvas LMS in production mode on a VPS.
# Run from the repository root on the VPS:
#   bash script/deploy_production.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

COMPOSE=(docker compose -f docker-compose.production.yml --env-file .env.production)

# Safe KEY=VALUE loader (avoids `source` breaking on spaces / special chars)
load_env_file() {
  local file="$1" line key value
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    key="${line%%=*}"
    value="${line#*=}"
    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    export "${key}=${value}"
  done < "$file"
}

if [[ ! -f .env.production ]]; then
  echo "==> Creating .env.production from example"
  cp .env.production.example .env.production
  if command -v openssl >/dev/null 2>&1; then
    DB_PASS="$(openssl rand -hex 16)"
    ENC_KEY="$(openssl rand -hex 20)"
    ADMIN_PASS="$(openssl rand -hex 12)"
    sed -i "s/CHANGE_ME_strong_db_password/${DB_PASS}/" .env.production
    sed -i "s/CHANGE_ME_generate_with_openssl_rand_hex_20/${ENC_KEY}/" .env.production
    sed -i "s/CHANGE_ME_admin_password/${ADMIN_PASS}/" .env.production
  else
    echo "WARNING: openssl not found - edit .env.production secrets manually"
    exit 1
  fi
  echo "==> Wrote secrets into .env.production (keep this file private)"
fi

load_env_file .env.production

if [[ "${POSTGRES_PASSWORD}" == CHANGE_ME* ]] || [[ "${ENCRYPTION_KEY}" == CHANGE_ME* ]]; then
  echo "ERROR: replace CHANGE_ME_* values in .env.production first"
  exit 1
fi

echo "==> Building production image (this can take a long time)"
"${COMPOSE[@]}" build

echo "==> Starting postgres + redis"
"${COMPOSE[@]}" up -d postgres redis

echo "==> Waiting for postgres"
for _i in $(seq 1 60); do
  if "${COMPOSE[@]}" exec -T postgres pg_isready -U postgres >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

echo "==> Running database initial setup (non-interactive via env)"
set +e
"${COMPOSE[@]}" run --rm \
  -e "CANVAS_LMS_ADMIN_EMAIL=${CANVAS_LMS_ADMIN_EMAIL:-admin@${CANVAS_HOST}}" \
  -e "CANVAS_LMS_ADMIN_PASSWORD=${CANVAS_LMS_ADMIN_PASSWORD}" \
  -e "CANVAS_LMS_ACCOUNT_NAME=${CANVAS_LMS_ACCOUNT_NAME:-Canvas}" \
  -e "CANVAS_LMS_STATS_COLLECTION=${CANVAS_LMS_STATS_COLLECTION:-opt_out}" \
  web bundle exec rake db:initial_setup
setup_status=$?
set -e
if [[ $setup_status -ne 0 ]]; then
  echo "==> initial_setup failed or already done - running migrate"
  "${COMPOSE[@]}" run --rm web bundle exec rake db:migrate
fi

echo "==> Starting web + jobs"
"${COMPOSE[@]}" up -d

echo
echo "Canvas should be available at: http://${CANVAS_HOST:-185.252.233.171}"
echo "Admin email: ${CANVAS_LMS_ADMIN_EMAIL:-admin@${CANVAS_HOST}}"
echo
echo "Useful commands:"
echo "  ${COMPOSE[*]} logs -f web jobs"
echo "  ${COMPOSE[*]} ps"
echo "  ${COMPOSE[*]} restart web jobs"
