#!/usr/bin/env bash
#
# Deploy del stack de STAGING de una app Oliva sobre infra compartida.
# Análogo a deploy.sh, pero usa la imagen frankenphp_staging y un project
# name propio (-p <app>-staging) para no interferir con el stack de producción.
#
# Prerequisitos (primera vez, una sola vez por app):
#   1. Provisionar la DB de staging en el Postgres compartido:
#        ~/infra/scripts/provision-postgres.sh <app>_staging_db <app>_staging_user
#   2. Completar .env.staging (copiar de .env.staging.example y setear DATABASE_URL).
#
# Uso:
#   ./scripts/deploy-staging.sh            # app_name = nombre del directorio actual
#   ./scripts/deploy-staging.sh ong        # app_name explícito
#   SKIP_PULL=1 ./scripts/deploy-staging.sh   # no hace git pull
set -euo pipefail

APP_NAME="${1:-$(basename "$PWD")}"
STAGING_PROJECT="${APP_NAME}-staging"

COMPOSE=(docker compose -p "$STAGING_PROJECT"
  -f docker-compose.yml
  -f docker-compose.prod.yml
  -f docker-compose.shared-infra.yml
  -f docker-compose.staging.yml)

echo ">> Deploy de STAGING '$STAGING_PROJECT' desde $PWD"

if [[ "${SKIP_PULL:-0}" != "1" ]]; then
  echo ">> git pull"
  git pull
fi

echo ">> down"
COMPOSE_PROFILES=cron "${COMPOSE[@]}" down --remove-orphans

# build-everything (no enumerar servicios): enumerar es lo frágil — es lo que
# en finanzas-ong dejó el frontend STALE (build solo listaba backend) y se
# pudre de nuevo en cuanto un fork agregue un servicio buildeable más. Alinea
# además con deploy.sh (prod), que ya usa up -d --build.
echo ">> up -d --build (target backend/scheduler: frankenphp_staging)"
"${COMPOSE[@]}" up -d --build

echo ">> migraciones"
docker exec "${STAGING_PROJECT}-backend-1" bin/console doctrine:migrations:migrate --no-interaction

echo ">> seeding (fixtures:load --group=staging)"
docker exec "${STAGING_PROJECT}-backend-1" bin/console doctrine:fixtures:load --group=staging --no-interaction

echo ">> estado:"
"${COMPOSE[@]}" ps

echo ">> OK — staging corriendo en project '${STAGING_PROJECT}'."
echo "   DB de staging es desechable. Para reiniciar con datos frescos:"
echo "   SKIP_PULL=1 ./scripts/deploy-staging.sh"
