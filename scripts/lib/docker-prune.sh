# shellcheck shell=bash
#
# Limpieza de restos de build. Se sourcea: `source "$(dirname "$0")/lib/docker-prune.sh"`.
#
# Cada rebuild deja la imagen anterior sin tag (dangling) y suma caché de build: en un
# VPS chico, deploy tras deploy, eso llena el disco (~750 MB por imagen de backend).
#
# Qué borra: imágenes SIN tag y caché de build sin usar hace más de una semana.
# Qué NO toca nunca: imágenes con tag (incluidas las de plan B taggeadas a mano),
# volúmenes (datos), containers, redes. La caché reciente se conserva para que el
# próximo build siga siendo rápido.
#
# Saltear: OLIVA_NO_PRUNE=1.

prune_build_leftovers() {
  [[ "${OLIVA_NO_PRUNE:-0}" == "1" ]] && { echo ">> limpieza de Docker salteada (OLIVA_NO_PRUNE=1)"; return 0; }
  local img cache
  img="$(docker image prune -f 2>/dev/null | awk '/Total reclaimed space/ {print $4}')"
  cache="$(docker builder prune -f --filter until=168h 2>/dev/null | awk '/Total/ {print $NF}')"
  echo ">> limpieza de Docker: imágenes sin tag ${img:-0B}, caché de build >7 días ${cache:-0B}"
}
