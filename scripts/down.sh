#!/usr/bin/env bash
#
# Baja los servicios de una app Oliva sobre infra compartida.
# Reemplaza el `docker compose -p ... -f ... -f ... -f ... down` a mano.
#
# Uso:
#   ./scripts/down.sh         # app_name = nombre del directorio actual (ej. en ~/ong → "ong")
#   ./scripts/down.sh ong     # app_name explícito
#
# Nunca borra volúmenes (no pasa -v): la DB y los secrets quedan a salvo.
# Corre desde la raíz del repo de la app en el VPS.
set -euo pipefail

APP_NAME="${1:-$(basename "$PWD")}"

source "$(dirname "$0")/lib/project-guard.sh"
assert_not_staging_name "$APP_NAME"
assert_project_owned_here "$APP_NAME"

COMPOSE=(docker compose -p "$APP_NAME"
  -f docker-compose.yml
  -f docker-compose.prod.yml
  -f docker-compose.shared-infra.yml)

echo ">> down de '$APP_NAME' desde $PWD"
# --profile '*' mete en scope del down a TODOS los servicios con profile (cron,
# queues, y los que agregue el fork). Sin esto, un servicio detrás de un profile
# inactivo no se baja — `down` lo saltea y --remove-orphans tampoco (sigue
# definido en el YAML, no es huérfano) → queda corriendo stale. Antes se usaba
# COMPOSE_PROFILES=cron, que REEMPLAZA los profiles del .env: dejaba afuera a
# `queues`. Los servicios desactivados en shared-infra (database/rabbitmq) entran
# en scope pero no tienen containers en este project: el down no los toca.
# NO se pasa -v: volúmenes (DB, secrets) se preservan.
"${COMPOSE[@]}" --profile '*' down --remove-orphans

echo ">> OK, servicios de '$APP_NAME' abajo (volúmenes intactos)."
