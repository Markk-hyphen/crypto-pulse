#!/usr/bin/env bash
#
# Publica una versión de Oliva. Solo en el repo de Oliva, sobre main.
#
#   scripts/oliva/release.sh 1.2.0
#
# Exige que docs/oliva/UPGRADING.md ya tenga la sección "## 1.2.0": las notas son lo
# que sync.sh le muestra a cada fork, así que no se publica sin escribirlas.
# Escribe OLIVA_VERSION, commitea y crea el tag anotado v1.2.0. NO pushea: imprime el comando.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_repo_root

ver="${1:-}"
[[ "$ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "uso: scripts/oliva/release.sh X.Y.Z"
[[ "$(git branch --show-current)" == main ]] || die "las versiones salen de main."
require_clean_tree
version_lt "$(local_oliva_version)" "$ver" || die "$ver no es mayor que la actual ($(local_oliva_version))."
grep -qE "^## ${ver//./\\.}( |$)" docs/oliva/UPGRADING.md \
  || die "falta la sección '## $ver' en docs/oliva/UPGRADING.md (qué cambia y qué tiene que hacer cada fork)."
git rev-parse -q --verify "refs/tags/v$ver" >/dev/null && die "el tag v$ver ya existe."

printf '%s\n' "$ver" > OLIVA_VERSION
git add OLIVA_VERSION
git commit -q -m "release: Oliva $ver"
git tag -a "v$ver" -m "Oliva $ver"
info "Oliva $ver lista. Publicar: git push origin main v$ver"
info "Después, en cada fork: scripts/oliva/sync.sh check"
