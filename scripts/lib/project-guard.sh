# shellcheck shell=bash
#
# Guard de colisión de project name para los scripts de deploy/down.
# Se sourcea (no se ejecuta): `source "$(dirname "$0")/lib/project-guard.sh"`.
#
# Todo lo de una app en el host cuelga del project name de Compose (-p): containers,
# red privada, alias en proxy_net, volúmenes e IMÁGENES (`<project>-backend:prod`).
# Si dos checkouts distintos usan el mismo nombre, un `down --remove-orphans` de uno
# baja los containers del otro y un build pisa su imagen — sin error ni warning.
# Compose etiqueta cada container con el directorio desde el que se levantó
# (com.docker.compose.project.working_dir): eso alcanza para detectar el choque.

# assert_project_owned_here <project>
#   Aborta si <project> ya tiene containers levantados desde OTRO directorio.
assert_project_owned_here() {
  local project="$1" here dir
  here="$(realpath "$PWD")"

  while IFS= read -r dir; do
    [[ -z "$dir" ]] && continue
    if [[ "$(realpath -m "$dir")" != "$here" ]]; then
      echo "ERROR: el project '$project' ya existe y pertenece a otro checkout:" >&2
      echo "         $dir" >&2
      echo "       (este checkout: $here)" >&2
      echo "       Usá otro nombre (./scripts/<script>.sh <nombre>) o bajá ese stack desde su directorio." >&2
      exit 1
    fi
  done < <(docker ps -a --filter "label=com.docker.compose.project=${project}" \
             --format '{{.Label "com.docker.compose.project.working_dir"}}' | sort -u)
}

# assert_not_staging_name <app_name>
#   `<app>-staging` es el project del staging de <app>: una app real no puede llamarse así.
assert_not_staging_name() {
  if [[ "$1" == *-staging ]]; then
    echo "ERROR: '$1' termina en -staging, sufijo reservado para el staging de cada app." >&2
    echo "       Para staging usá ./scripts/deploy-staging.sh ${1%-staging}" >&2
    exit 1
  fi
}
