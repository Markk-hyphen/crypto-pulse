#!/usr/bin/env bash
#
# Deploy de una app Oliva sobre infra compartida (down + build + up).
# Reemplaza la tira de comandos manuales del runbook de CLAUDE.md.
#
# Uso:
#   ./scripts/deploy.sh            # app_name = nombre del directorio actual (ej. en ~/ong → "ong")
#   ./scripts/deploy.sh ong        # app_name explícito
#   SKIP_PULL=1 ./scripts/deploy.sh   # no hace git pull (deploy de cambios ya presentes)
#
# Corre desde la raíz del repo de la app en el VPS (ahí viven los 3 compose files).
set -euo pipefail

APP_NAME="${1:-$(basename "$PWD")}"

COMPOSE=(docker compose -p "$APP_NAME"
  -f docker-compose.yml
  -f docker-compose.prod.yml
  -f docker-compose.shared-infra.yml)

echo ">> Deploy de '$APP_NAME' desde $PWD"

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
# COMPOSE_PROFILES=cron mete al scheduler en scope SOLO para el down: un servicio
# detrás de un profile no se baja con `down` (profile inactivo) ni con
# --remove-orphans (sigue definido en el YAML, no es huérfano real) → quedaría
# corriendo stale. Activando el profile acá, el down sí lo apaga. El `up` de
# abajo NO lleva el profile, así que el scheduler no se vuelve a levantar.
echo ">> down"
COMPOSE_PROFILES=cron "${COMPOSE[@]}" down --remove-orphans

echo ">> up -d --build"
"${COMPOSE[@]}" up -d --build

echo ">> estado:"
"${COMPOSE[@]}" ps

echo ">> OK. Si la app usa cron, agregá '--profile cron' al up (ver CLAUDE.md)."
