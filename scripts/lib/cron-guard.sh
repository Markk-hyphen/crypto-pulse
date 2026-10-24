# shellcheck shell=bash
#
# Aviso de cron inactivo. Se sourcea: `source "$(dirname "$0")/lib/cron-guard.sh"`.
#
# El scheduler vive tras el profile `cron`. Si el fork llenó backend/scheduler/crontab
# pero el `.env` del host no declara `COMPOSE_PROFILES=...cron...`, el `up` no levanta el
# scheduler y las tareas no corren nunca, sin ningún error. Esto lo hace ruidoso.
#
# Pregunta a Compose (`config --services`) en vez de parsear el `.env` a mano: así respeta
# exactamente lo que va a hacer el `up` (`.env`, COMPOSE_PROFILES exportada, overlays).
#
# Uso: warn_if_cron_inactive "${COMPOSE[@]}"  → 1 si avisó. Los deploys lo llaman vía
# run_upgrade_guards (lib/upgrade-guards.sh), que nunca aborta.

warn_if_cron_inactive() {
  local crontab="backend/scheduler/crontab"
  [[ -f "$crontab" ]] || return 0

  # Líneas de tarea: ni comentarios, ni vacías, ni asignaciones de entorno (SHELL=..., etc.).
  local tasks
  tasks="$(grep -cvE '^[[:space:]]*(#|$)|^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=' "$crontab" || true)"
  [[ "$tasks" -gt 0 ]] || return 0

  # Si Compose no puede resolver la config, no hay nada confiable que afirmar: no avisar.
  local services
  services="$("$@" config --services 2>/dev/null)" || return 0
  grep -qx scheduler <<<"$services" && return 0

  cat >&2 <<EOF

!! ================================================================
!! CRON INACTIVO: $crontab tiene $tasks tarea(s), pero el scheduler
!! NO se levantó (el profile 'cron' no está activo). Esas tareas no
!! van a correr.
!!
!! Fix: en el .env de este host, agregar cron a COMPOSE_PROFILES
!!   COMPOSE_PROFILES=cron          (o queues,cron si usa colas)
!! y volver a correr el deploy. No hace falta tocar este script.
!! ================================================================

EOF
  return 1
}
