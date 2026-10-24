# shellcheck shell=bash
#
# Helpers compartidos por scripts/oliva/*.sh. Se sourcea, no se ejecuta.
# Todos los scripts corren desde la raíz del repo (Oliva o un fork).

OLIVA_REMOTE="${OLIVA_REMOTE:-oliva-upstream}"
OLIVA_REMOTE_URL="${OLIVA_REMOTE_URL:-https://github.com/Markk-hyphen/oliva.git}"

die()  { echo "ERROR: $*" >&2; exit 1; }
info() { echo ">> $*"; }
warn() { echo "!! $*" >&2; }

require_repo_root() {
  [[ -f docker-compose.yml && -d backend && -d frontend ]] \
    || die "corré esto desde la raíz del repo (donde está docker-compose.yml)."
}

require_clean_tree() {
  git diff --quiet && git diff --cached --quiet \
    || die "hay cambios sin commitear en archivos versionados. Commitealos o stasheálos antes."
}

# Versión de Oliva sobre la que está este checkout (archivo OLIVA_VERSION, desde 1.1.0).
local_oliva_version() { cat OLIVA_VERSION 2>/dev/null || echo "0.0.0"; }

# version_lt A B → true si A < B (semver simple, sin pre-releases).
version_lt() { [[ "$1" != "$2" && "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" == "$1" ]]; }

# Imagen base del backend tal como la fija backend/Dockerfile (PHP exacto del proyecto).
backend_base_image() { awk '/^FROM / && /frankenphp_upstream/ {print $2; exit}' backend/Dockerfile; }
frontend_base_image() { awk '/^FROM / {print $2; exit}' frontend/Dockerfile; }

# Imagen de herramientas: el PHP EXACTO del proyecto + composer. Se usa para tocar
# composer.lock sin depender de que la imagen dev del proyecto exista o buildee
# (en medio de un merge con conflictos, no buildea). Las extensiones PHP no están
# en esta imagen: se ignoran solo los requisitos ext-* al resolver, nunca la
# versión de PHP (resolver con otro PHP podría elegir paquetes incompatibles).
composer_tool_image() {
  local base tag
  base="$(backend_base_image)"
  [[ -n "$base" ]] || die "no encuentro el FROM ... AS frankenphp_upstream en backend/Dockerfile"
  tag="oliva-tools/composer:${base##*:}"
  if ! docker image inspect "$tag" >/dev/null 2>&1; then
    info "construyendo imagen de herramientas $tag (una sola vez)" >&2
    printf 'FROM %s\nCOPY --from=composer/composer:2-bin /composer /usr/bin/composer\n' "$base" \
      | docker build -q -t "$tag" - >/dev/null
  fi
  echo "$tag"
}

# composer <args...> sobre ./backend, como el usuario del host (los archivos no quedan de root).
run_composer() {
  local img
  img="$(composer_tool_image)"
  docker run --rm -u "$(id -u):$(id -g)" -e COMPOSER_HOME=/tmp/composer \
    -v "$PWD/backend:/app" -w /app --entrypoint composer "$img" \
    --no-interaction "$@"
}

# Para comandos que resuelven (update/outdated): ignorar solo extensiones, nunca PHP.
# shellcheck disable=SC2034  # lo usan los scripts que sourcean este archivo
IGNORE_EXT="--ignore-platform-req=ext-*"

# yarn <args...> sobre ./frontend con la imagen de node del propio Dockerfile.
# node_modules va a /tmp del container: el host solo ve package.json / yarn.lock.
run_yarn() {
  docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp \
    -v "$PWD/frontend:/w" -w /w "$(frontend_base_image)" \
    yarn --non-interactive --ignore-scripts --modules-folder /tmp/node_modules "$@"
}

# Paquetes de composer.lock como "nombre version" (prod + dev), desde un ref de git.
composer_lock_versions() {
  git show "$1:backend/composer.lock" 2>/dev/null \
    | jq -r '(.packages + ."packages-dev")[] | "\(.name) \(.version)"' | sort
}

# Aborta si backend/composer.json tiene constraints sin techo (ver unbound-constraints.php).
# Va ANTES de cada `composer update` que corren los scripts: después, el major ya entró.
require_bounded_constraints() {
  local img out
  img="$(composer_tool_image)"
  out="$(docker run --rm \
    -v "$PWD/backend/composer.json:/c/composer.json:ro" \
    -v "$PWD/scripts/oliva/unbound-constraints.php:/c/check.php:ro" \
    --entrypoint php "$img" /c/check.php /c/composer.json)" && return 0
  warn "backend/composer.json tiene constraints sin techo: composer podría instalar un major sin aviso."
  echo "$out" | sed 's/^/     /' >&2
  die "ponele techo a cada uno (ej. \">=3.7.1\" → \"^3.7.1\") y volvé a correr."
}
