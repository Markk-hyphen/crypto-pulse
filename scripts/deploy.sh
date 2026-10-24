#!/usr/bin/env bash
#
# Deploy de una app Oliva sobre infra compartida (down + build + up).
# Reemplaza la tira de comandos manuales del runbook de AGENTS.md.
#
# Uso:
#   ./scripts/deploy.sh            # app_name = nombre del directorio actual (ej. en ~/ong → "ong")
#   ./scripts/deploy.sh ong        # app_name explícito
#   SKIP_PULL=1 ./scripts/deploy.sh   # no hace git pull (deploy de cambios ya presentes)
#
# Corre desde la raíz del repo de la app en el VPS (ahí viven los 3 compose files).
set -euo pipefail

APP_NAME="${1:-$(basename "$PWD")}"

source "$(dirname "$0")/lib/project-guard.sh"
source "$(dirname "$0")/lib/docker-prune.sh"
source "$(dirname "$0")/lib/upgrade-guards.sh"
assert_not_staging_name "$APP_NAME"
assert_project_owned_here "$APP_NAME"

COMPOSE=(docker compose -p "$APP_NAME"
  -f docker-compose.yml
  -f docker-compose.prod.yml
  -f docker-compose.shared-infra.yml)

echo ">> Deploy de '$APP_NAME' desde $PWD"

# Antes del pull: si este host no tiene estado de acciones de upgrade, se siembra con la
# versión que corre ahora, así las acciones [host] de lo que traiga el pull quedan pendientes.
seed_acked_version

if [[ "${SKIP_PULL:-0}" != "1" ]]; then
  echo ">> git pull"
  git pull
fi

# Docs internos: no pertenecen al host de prod. El código de la app vive
# en los builds Docker; estos archivos no los necesita nadie en el server.
echo ">> limpieza de docs internos"
find . -maxdepth 1 -name "*.md" -delete
rm -rf docs/

# down borra los containers viejos antes de recrearlos.
# --profile '*' mete en scope del down a TODOS los servicios con profile (cron,
# queues, y los que agregue el fork). Sin esto, un servicio detrás de un profile
# inactivo no se baja — `down` lo saltea y --remove-orphans tampoco (sigue
# definido en el YAML, no es huérfano) → queda corriendo stale. Antes se usaba
# COMPOSE_PROFILES=cron, que REEMPLAZA los profiles del .env: dejaba afuera a
# `queues`. Los servicios desactivados en shared-infra (database/rabbitmq) entran
# en scope pero no tienen containers en este project: el down no los toca.
# El `up` de abajo usa los profiles del `.env` del host (COMPOSE_PROFILES): cada
# servicio con profile vuelve a levantar solo si la app lo declaró ahí.
echo ">> down"
"${COMPOSE[@]}" --profile '*' down --remove-orphans

echo ">> up -d --build"
"${COMPOSE[@]}" up -d --build

echo ">> estado:"
"${COMPOSE[@]}" ps

# La imagen que se acaba de reemplazar queda sin tag: sin esto, cada deploy suma ~750 MB.
prune_build_leftovers

# Solo avisan, no abortan (el stack ya está arriba). UPGRADING.md se lee de git: el
# working tree ya no tiene docs/.
run_upgrade_guards "${COMPOSE[@]}"
show_pending_upgrade_actions host || true

echo ">> OK. Profiles opcionales (cron, queues): se activan con COMPOSE_PROFILES en el .env del host."
