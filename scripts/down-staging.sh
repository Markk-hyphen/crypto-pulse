#!/usr/bin/env bash
#
# Baja el stack de STAGING de una app Oliva sobre infra compartida.
# Análogo a down.sh, pero con los 4 overlays y project name propio
# (-p <app>-staging) para no tocar el stack de producción.
#
# Uso:
#   ./scripts/down-staging.sh         # app_name = nombre del directorio actual
#   ./scripts/down-staging.sh ong     # app_name explícito
#
# Nunca borra volúmenes (no pasa -v): la DB desechable de staging queda a
# salvo (si se quiere purgar de verdad, bajar con -v a mano).
# Corre desde la raíz del repo de la app en el VPS.
set -euo pipefail

APP_NAME="${1:-$(basename "$PWD")}"
STAGING_PROJECT="${APP_NAME}-staging"

COMPOSE=(docker compose -p "$STAGING_PROJECT"
  -f docker-compose.yml
  -f docker-compose.prod.yml
  -f docker-compose.shared-infra.yml
  -f docker-compose.staging.yml)

echo ">> down de '$STAGING_PROJECT' desde $PWD"
COMPOSE_PROFILES=cron "${COMPOSE[@]}" down --remove-orphans

echo ">> OK, servicios de '$STAGING_PROJECT' abajo (volúmenes intactos)."
