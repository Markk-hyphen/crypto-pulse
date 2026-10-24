# shellcheck shell=bash
#
# Acciones de upgrade: que lo que pide docs/oliva/UPGRADING.md no dependa de que alguien
# lo lea a tiempo. Se sourcea: `source "$(dirname "$0")/lib/upgrade-guards.sh"`.
#
# El problema que resuelve: sync.sh muestra las notas de upgrade solo ANTES del merge
# (secciones más nuevas que el OLIVA_VERSION local). Después del merge el fork queda en la
# versión de upstream y las notas no vuelven a aparecer, pero las acciones de host se hacen
# después, en otra máquina, al deployar. Caso real: los pendientes de VPS de 1.4.2 (cron) y
# 1.4.3 (FRANKENPHP_CONFIG) en finanzas-ong solo sobrevivieron porque el agente los anotó.
#
# Dos mecanismos:
#   1. Guards: chequeos del estado real (env resuelto, imagen, crontab). Corren donde vive el
#      estado: verify.sh (checkout de desarrollo) y deploy*.sh (host). Solo avisan, nunca
#      abortan. No se reconocen con ack: desaparecen cuando el estado está bien.
#   2. Acciones pendientes: los ítems de UPGRADING.md SIN guard se muestran en cada máquina
#      hasta que se reconocen ahí (`./oliva ack`). El estado es por checkout:
#      .oliva/acked-version (gitignored). Si falta, se siembra en silencio con la versión
#      actual (host o clon nuevo: arranca del template vigente, no arrastra historia).
#
# Formato de UPGRADING.md (desde OLIVA_TAGGED_SINCE): cada ítem de "Acción requerida en el
# fork" empieza con una etiqueta `- [lugar]` o `- [lugar, guard: <id>]`, con lugar en
# OLIVA_ACTION_PLACES. release.sh lo exige (lint_upgrade_actions).
#
# Requiere solo bash + awk + docker compose: corre en el host (sin jq).

source "$(dirname "${BASH_SOURCE[0]}")/cron-guard.sh"

OLIVA_ACK_FILE=".oliva/acked-version"
OLIVA_TAGGED_SINCE="1.5.0"
OLIVA_ACTION_PLACES="merge local host decisión"

# ── Guards ───────────────────────────────────────────────────────────────────────
# Cada guard: guard_<id> COMPOSE... → 0 = bien o no aplica, 1 = avisó (por stderr).
# El id (con guiones) es lo que se escribe en `[lugar, guard: <id>]`.
UPGRADE_GUARDS=(cron worker-env worker-image)

# Bloque YAML de un servicio en la salida de `docker compose config`.
_ug_service_block() {
  awk -v s="  $1:" '$0 == s { b = 1; next } /^[^ ]/ || /^  [^ ]/ { b = 0 } b'
}

guard_cron() { warn_if_cron_inactive "$@"; }

# 1.4.3: un FRANKENPHP_CONFIG vacío en el env (env_file o environment) pisa el valor que hornea
# la imagen prod y apaga worker mode sin error. Mismo criterio que el job prod-config del CI,
# pero acá ve el .env de ESTA máquina (el del host incluido), que el CI nunca ve.
guard_worker_env() {
  local cfg
  cfg="$("$@" config backend 2>/dev/null)" || return 0
  _ug_service_block backend <<<"$cfg" | grep -qE '^ +FRANKENPHP_CONFIG: ""$' || return 0
  cat >&2 <<'EOF'

!! ================================================================
!! WORKER MODE APAGADO: el backend resuelve FRANKENPHP_CONFIG vacío,
!! que pisa el "import worker.Caddyfile" de la imagen prod.
!!
!! Fix: borrar la línea FRANKENPHP_CONFIG= del .env (y de .env.backend
!! si está) de este host, y volver a deployar.
!! Si es un opt-out deliberado a modo clásico (environment: de
!! docker-compose.prod.yml), este aviso es esperado.
!! ================================================================

EOF
  return 1
}

# La imagen del backend debe hornear worker mode (backend/Dockerfile, stage frankenphp_prod;
# staging hereda de ahí). La imagen sale del `config` del servicio, no de `config --images`:
# ese lista también las imágenes de los depends_on, en orden no determinista.
guard_worker_image() {
  local img
  img="$("$@" config backend 2>/dev/null | _ug_service_block backend | awk '$1 == "image:" { print $2; exit }')"
  if [[ -z "$img" ]]; then
    echo "!! worker-image: no pude resolver la imagen del backend con este compose" >&2
    return 1
  fi
  if ! docker image inspect "$img" >/dev/null 2>&1; then
    echo "!! worker-image: la imagen $img no existe localmente (¿falta el build?)" >&2
    return 1
  fi
  docker image inspect "$img" --format '{{range .Config.Env}}{{println .}}{{end}}' \
    | grep -qx 'FRANKENPHP_CONFIG=import worker.Caddyfile' && return 0
  echo "!! worker-image: $img NO hornea FRANKENPHP_CONFIG=import worker.Caddyfile" >&2
  echo "!!   worker mode arrancaría APAGADO (ver backend/Dockerfile, stage frankenphp_prod)" >&2
  return 1
}

# Corre todos los guards. Solo avisa: siempre devuelve 0 (no frena un deploy).
run_upgrade_guards() {
  local id
  for id in "${UPGRADE_GUARDS[@]}"; do
    "guard_${id//-/_}" "$@" || true
  done
  return 0
}

# Un id de guard vale si es del registro o un step de verify.sh (ej. php-version).
upgrade_guard_exists() {
  local id="$1" g
  for g in "${UPGRADE_GUARDS[@]}"; do [[ "$g" == "$id" ]] && return 0; done
  grep -qE "^step +$id( |$)" "$(dirname "${BASH_SOURCE[0]}")/../oliva/verify.sh" 2>/dev/null
}

# ── Acciones pendientes ─────────────────────────────────────────────────────────

_ug_current_version() { cat OLIVA_VERSION 2>/dev/null || echo "0.0.0"; }

# Si falta el estado, lo siembra con la versión actual. Llamarlo ANTES de cambiar de versión
# (sync.sh start, deploy.sh antes del pull) para que lo que llega después quede pendiente.
seed_acked_version() {
  [[ -s "$OLIVA_ACK_FILE" || ! -f OLIVA_VERSION ]] && return 0
  mkdir -p "$(dirname "$OLIVA_ACK_FILE")" 2>/dev/null && _ug_current_version > "$OLIVA_ACK_FILE" 2>/dev/null
  return 0
}

oliva_acked_version() {
  seed_acked_version
  cat "$OLIVA_ACK_FILE" 2>/dev/null || _ug_current_version
}

# Ítems de "Acción requerida" sin guard, de las versiones reconocidas < v <= OLIVA_VERSION
# (y >= OLIVA_TAGGED_SINCE), cuyo lugar está en $1 (ej. "host" o "local host decisión").
# Lee UPGRADING.md de git, no del disco: en el host deploy.sh borra docs/ del working tree.
pending_upgrade_actions() {
  git show HEAD:docs/oliva/UPGRADING.md 2>/dev/null | awk \
    -v acked="$(oliva_acked_version)" -v cur="$(_ug_current_version)" \
    -v floor="$OLIVA_TAGGED_SINCE" -v places=" $1 " '
    function vnum(v,  a) { split(v, a, "."); return a[1] * 1000000 + a[2] * 1000 + a[3] }
    BEGIN { lo = vnum(acked); hi = vnum(cur); fl = vnum(floor) }
    /^## [0-9]+\.[0-9]+\.[0-9]+/ { ver = $2; n = vnum(ver); inrange = (n > lo && n <= hi && n >= fl); inact = 0; take = 0; next }
    /^\*\*Acción requerida/ { inact = inrange; next }
    !inact { next }
    /^```/ { fence = !fence; if (take) print "     " $0; next }
    fence { if (take) print "     " $0; next }
    /^\*\*/ { inact = 0; take = 0; next }
    /^- / {
      take = 0
      if (match($0, /^- \[[^]]+\]/)) {
        n2 = split(substr($0, 4, RLENGTH - 4), parts, ",")
        place = parts[1]; gsub(/^ +| +$/, "", place)
        guarded = 0
        for (i = 2; i <= n2; i++) if (parts[i] ~ /^ *guard:/) guarded = 1
        take = !guarded && index(places, " " place " ")
      }
      if (take) { if (ver != shown) { print "   " ver ":"; shown = ver } print "     " $0 }
      next
    }
    /^[ \t]*$/ { next }
    /^ / { if (take) print "     " $0; next }
    { take = 0 }'
}

# Muestra los pendientes de $1. Devuelve 1 si había alguno (para que el caller lo sepa).
show_pending_upgrade_actions() {
  local out
  out="$(pending_upgrade_actions "$1")"
  [[ -n "$out" ]] || return 0
  {
    echo
    echo "!! ACCIONES DE UPGRADE PENDIENTES en esta máquina"
    echo "!! (reconocidas hasta Oliva $(oliva_acked_version); el repo está en $(_ug_current_version)):"
    echo "$out"
    echo "!! Cuando estén hechas ACÁ: ./oliva ack  (cada máquina reconoce las suyas)"
    [[ "$1" != host && "$out" == *"[host"* ]] \
      && echo "!! Las [host] se hacen en cada host: su deploy.sh las muestra allá hasta un ack ahí."
    echo
  } >&2
  return 1
}

# `./oliva ack`: da por hechas en esta máquina las acciones hasta la versión actual.
ack_upgrade_actions() {
  local cur out
  cur="$(_ug_current_version)"
  out="$(pending_upgrade_actions "$OLIVA_ACTION_PLACES")" || true   # sin UPGRADING en HEAD: igual reconoce
  mkdir -p "$(dirname "$OLIVA_ACK_FILE")"
  echo "$cur" > "$OLIVA_ACK_FILE"
  if [[ -n "$out" ]]; then
    echo ">> diste por hechas, en esta máquina:"
    echo "$out"
  fi
  echo ">> acciones de upgrade reconocidas hasta Oliva $cur en esta máquina."
  echo "   (los guards no se reconocen: siguen avisando mientras el estado esté mal)"
}

# ── Lint (release.sh) ───────────────────────────────────────────────────────────
# Valida las etiquetas de "Acción requerida" de la sección <ver>. Imprime cada error y
# devuelve 1 si hubo alguno. Versiones anteriores a OLIVA_TAGGED_SINCE no se validan.
lint_upgrade_actions() {
  local ver="$1" file="${2:-docs/oliva/UPGRADING.md}" errs=0 line tag place part gid found
  [[ "$(printf '%s\n%s\n' "$OLIVA_TAGGED_SINCE" "$ver" | sort -V | head -1)" == "$OLIVA_TAGGED_SINCE" ]] || return 0

  found="$(awk -v v="$ver" '
    /^## [0-9]+\.[0-9]+\.[0-9]+/ { sec = ($2 == v); inact = 0; next }
    sec && /^\*\*Acción requerida/ { inact = 1; print "#HEADER"; next }
    sec && inact && /^```/ { fence = !fence; next }
    fence { next }
    sec && /^\*\*/ { inact = 0; next }
    sec && inact && /^(- |[0-9]+\. )/' "$file")"
  if [[ "$found" != "#HEADER"* ]]; then
    echo "   ## $ver: falta el bloque **Acción requerida en el fork** (o \"Ninguna.\")"
    return 1
  fi

  while IFS= read -r line; do
    [[ "$line" == "#HEADER" ]] && continue
    if [[ ! "$line" =~ ^-\ \[([^]]+)\] ]]; then
      echo "   ## $ver: ítem sin etiqueta [lugar] o [lugar, guard: id]: ${line:0:70}"
      errs=1; continue
    fi
    tag="${BASH_REMATCH[1]}"
    IFS=',' read -ra parts <<<"$tag"
    place="$(echo "${parts[0]}" | xargs)"
    if [[ " $OLIVA_ACTION_PLACES " != *" $place "* ]]; then
      echo "   ## $ver: lugar '$place' inválido (usar: $OLIVA_ACTION_PLACES): ${line:0:70}"
      errs=1
    fi
    for part in "${parts[@]:1}"; do
      part="$(echo "$part" | xargs)"
      if [[ "$part" =~ ^guard:\ *([a-z0-9-]+)$ ]]; then
        gid="${BASH_REMATCH[1]}"
        upgrade_guard_exists "$gid" \
          || { echo "   ## $ver: guard '$gid' no existe (ni en UPGRADE_GUARDS ni como step de verify.sh)"; errs=1; }
      else
        echo "   ## $ver: etiqueta '$part' no reconocida (solo 'guard: <id>'): ${line:0:70}"
        errs=1
      fi
    done
  done <<<"$found"
  return $errs
}
