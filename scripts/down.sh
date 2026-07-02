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

COMPOSE=(docker compose -p "$APP_NAME"
  -f docker-compose.yml
  -f docker-compose.prod.yml
  -f docker-compose.shared-infra.yml)

echo ">> down de '$APP_NAME' desde $PWD"
# COMPOSE_PROFILES=cron mete al scheduler (y cualquier servicio con profile) en
# scope para el down: sin esto, un servicio detrás de un profile no se baja —
# `down` lo saltea (profile inactivo) y --remove-orphans tampoco lo toca (sigue
# definido en el YAML, no es huérfano). NO se pasa -v: volúmenes (DB, secrets)
# se preservan.
COMPOSE_PROFILES=cron "${COMPOSE[@]}" down --remove-orphans

echo ">> OK, servicios de '$APP_NAME' abajo (volúmenes intactos)."
