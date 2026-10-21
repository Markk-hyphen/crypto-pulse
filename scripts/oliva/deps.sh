#!/usr/bin/env bash
#
# Mantenimiento de dependencias de una app Oliva (sirve igual en Oliva y en cada fork).
#
#   scripts/oliva/deps.sh due      # offline, 1 segundo: ¿toca ciclo? (chequeo de inicio de sesión)
#   scripts/oliva/deps.sh report   # qué hay viejo: imágenes base, EOL, composer, yarn, actions, CVEs
#   scripts/oliva/deps.sh update   # rama chore/deps-<fecha>: bump DENTRO de los rangos + verify + commit
#
# Qué automatiza y qué no: `update` sube patch/minor dentro de las restricciones de
# composer.json/package.json — lo que casi nunca rompe y siempre conviene. Los saltos
# de imagen base (FrankenPHP, node, postgres, rabbitmq) y los majors de paquetes NO se
# automatizan: `report` los lista y se hacen a mano, uno por commit, con verify.sh.
# Motivo: el único update que rompió algo en serio fue un salto de FrankenPHP (Mercure).
set -euo pipefail
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/../lib/docker-prune.sh"
require_repo_root

DUE_DAYS="${OLIVA_DEPS_DUE_DAYS:-45}"

# ── due ────────────────────────────────────────────────────────────────────────
cmd_due() {
  local last days
  last="$(git log -1 --format=%cs --grep='^chore(deps)' 2>/dev/null || true)"
  if [[ -z "$last" ]]; then
    echo "deps: nunca se corrió un ciclo (no hay commits chore(deps)). Correr: scripts/oliva/deps.sh report"
    return 0
  fi
  days=$(( ( $(date +%s) - $(date -d "$last" +%s) ) / 86400 ))
  if (( days >= DUE_DAYS )); then
    echo "deps: último ciclo hace ${days} días (${last}) → TOCA. Correr: scripts/oliva/deps.sh report"
  else
    echo "deps: último ciclo hace ${days} días (${last}), OK (umbral ${DUE_DAYS})."
  fi
}

# ── report ─────────────────────────────────────────────────────────────────────

# Tags de Docker Hub con la misma "forma" que el actual (dígitos → \d+), más nuevo primero.
# Ej: 1.13.1-php8.3.35 → ^\d+\.\d+\.\d+-php\d+\.\d+\.\d+$ ; 20-slim → ^\d+-slim$
hub_newer_tags() {
  local image="$1" repo tag regex frag url page=1
  repo="${image%%:*}"; tag="${image##*:}"
  [[ "$repo" == */* ]] || repo="library/$repo"
  regex="^$(printf '%s' "$tag" | sed -E 's/[.]/\\./g; s/[0-9]+/[0-9]+/g')\$"
  frag="$(printf '%s' "$tag" | tr -s '0-9.' '\n' | awk 'length>1' | head -1)"
  url="https://hub.docker.com/v2/repositories/${repo}/tags?page_size=100&ordering=last_updated&name=${frag}"
  {
    while [[ -n "$url" && "$url" != null && $page -le 4 ]]; do
      local body; body="$(curl -fsS "$url" 2>/dev/null)" || break
      jq -r '.results[].name' <<<"$body"
      url="$(jq -r '.next' <<<"$body")"; page=$((page+1))
    done
  } | grep -E "$regex" | sort -V | tail -1
}

eol_line() {  # eol_line <producto endoflife.date> <ciclo>
  local product="$1" cycle="$2" eol today
  eol="$(curl -fsS "https://endoflife.date/api/v1/products/${product}/" 2>/dev/null \
        | jq -r --arg c "$cycle" '.result.releases[] | select(.name==$c or (.name|startswith($c+"."))) | .eolFrom // "?"' | head -1)"
  [[ -z "$eol" ]] && { echo "   $product $cycle: sin datos"; return; }
  today="$(date +%F)"
  if [[ "$eol" != "?" && "$eol" < "$today" ]]; then
    echo "   ⛔ $product $cycle: EOL desde $eol"
  elif [[ "$eol" != "?" && "$eol" < "$(date -d '+180 days' +%F)" ]]; then
    echo "   ⚠️  $product $cycle: EOL el $eol (menos de 6 meses)"
  else
    echo "   ✓  $product $cycle: soportado hasta $eol"
  fi
}

report_images() {
  echo "## Imágenes base (actual → más nueva con la misma forma de tag)"
  local images img newest
  images="$( { awk '/^FROM / && $2 !~ /^(frankenphp_|base|builder)/ {print $2}' backend/Dockerfile frontend/Dockerfile
               grep -hoE 'image: *[a-z0-9./-]+:[A-Za-z0-9.${}_:-]+' docker-compose*.yml \
                 | sed -E 's/image: *//' | grep -v 'COMPOSE_PROJECT_NAME'; } \
             | sed -E 's/\$\{POSTGRES_VERSION:-([0-9]+)\}/\1/' | sort -u)"
  while read -r img; do
    [[ -z "$img" ]] && continue
    newest="$(hub_newer_tags "$img" || true)"
    if [[ -z "$newest" ]]; then echo "   $img → (sin datos)"
    elif [[ "$newest" == "${img##*:}" ]]; then echo "   ✓  $img (al día)"
    else echo "   ↑  $img → ${newest}"; fi
  done <<<"$images"
  local sc_cur sc_new
  sc_cur="$(awk -F= '/SUPERCRONIC_VERSION=/ {print $2; exit}' backend/Dockerfile)"
  sc_new="$(curl -fsS https://api.github.com/repos/aptible/supercronic/releases/latest 2>/dev/null | jq -r .tag_name || true)"
  [[ -n "$sc_cur" ]] && echo "   $( [[ "$sc_cur" == "$sc_new" ]] && echo '✓ ' || echo '↑ ') supercronic $sc_cur → ${sc_new:-?}"
  echo
  echo "   Ojo: 'más nueva con la misma forma' puede ser un major (node 20→25) o no-LTS."
  echo "   Decidir con la tabla de EOL de abajo. FrankenPHP: tras subirlo, verify.sh [mercure] es obligatorio."
}

report_eol() {
  echo "## Ciclos de vida (EOL)"
  local php node pg rabbit sf
  php="$(backend_base_image | grep -oE 'php[0-9]+\.[0-9]+' | head -1 | sed 's/php//')"
  node="$(frontend_base_image | grep -oE ':[0-9]+' | tr -d ':')"
  pg="$(grep -oE '^POSTGRES_VERSION=[0-9]+' .env.example | cut -d= -f2)"
  rabbit="$(grep -hoE 'rabbitmq:[0-9]+' docker-compose.yml | cut -d: -f2 | head -1)"
  sf="$(jq -r '.extra.symfony.require // empty' backend/composer.json | grep -oE '[0-9]+\.[0-9]+')"
  [[ -n "$php" ]]    && eol_line php "$php"
  [[ -n "$node" ]]   && eol_line nodejs "$node"
  [[ -n "$pg" ]]     && eol_line postgresql "$pg"
  [[ -n "$rabbit" ]] && eol_line rabbitmq "$rabbit"
  [[ -n "$sf" ]]     && eol_line symfony "$sf"
}

report_composer() {
  echo "## Composer (dependencias directas desactualizadas)"
  run_composer outdated "$IGNORE_EXT" --direct --locked --format=json 2>/dev/null \
    | jq -r '.locked[]? | "   \(if ."latest-status"=="semver-safe-update" then "↑ " else "⇑ " end) \(.name) \(.version) → \(.latest)\(if ."latest-status"=="semver-safe-update" then "" else "  (fuera del rango: major/manual)" end)"' \
    || warn "composer outdated falló"
  echo "   (↑ = lo sube \`deps.sh update\` · ⇑ = cambiar el constraint a mano)"
  echo
  echo "## Composer audit (CVEs)"
  run_composer audit --locked 2>&1 | sed 's/^/   /' || true
}

report_yarn() {
  echo "## Frontend (yarn)"
  [[ -f frontend/yarn.lock ]] || { echo "   ⛔ no hay frontend/yarn.lock versionado: las builds no son reproducibles"; return; }
  docker run --rm -e HOME=/tmp -v "$PWD/frontend:/src:ro" "$(frontend_base_image)" sh -c '
    mkdir /tmp/w && cp /src/package.json /src/yarn.lock /tmp/w && cd /tmp/w &&
    yarn install --frozen-lockfile --ignore-scripts --silent >/dev/null 2>&1 &&
    yarn outdated 2>/dev/null | sed -n "/^Package/,\$p"; echo; yarn audit --summary 2>/dev/null | tail -2
  ' | sed 's/^/   /' || warn "yarn outdated falló"
}

report_actions() {
  echo "## GitHub Actions"
  local uses repo ver latest
  grep -hoE 'uses: *[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+@v[0-9.]+' .github/workflows/*.yml 2>/dev/null | sed 's/uses: *//' | sort -u \
  | while read -r uses; do
      repo="${uses%@*}"; ver="${uses#*@}"
      latest="$(curl -fsS "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null | jq -r .tag_name || true)"
      if [[ -z "$latest" || "$latest" == null ]]; then echo "   $uses → ?"
      elif [[ "${latest%%.*}" == "${ver%%.*}" ]]; then echo "   ✓  $uses (último: $latest)"
      else echo "   ↑  $uses → $latest"; fi
    done
}

cmd_report() {
  echo "# Reporte de dependencias — $(basename "$PWD") (Oliva $(local_oliva_version)) — $(date +%F)"
  echo
  report_eol; echo
  report_images; echo
  report_composer; echo
  report_yarn; echo
  report_actions
}

# ── update ─────────────────────────────────────────────────────────────────────
cmd_update() {
  require_clean_tree
  local branch before after
  branch="chore/deps-$(date +%F)"
  git switch -c "$branch"
  before="$(mktemp)"; after="$(mktemp)"
  composer_lock_versions HEAD > "$before"

  info "composer update (dentro de los rangos de composer.json)"
  run_composer update "$IGNORE_EXT" --no-install --no-scripts --with-all-dependencies
  info "yarn upgrade (dentro de los rangos de package.json)"
  run_yarn upgrade

  if git diff --quiet; then
    info "nada para actualizar dentro de los rangos. Volviendo a la rama anterior."
    git switch -; git branch -d "$branch"; return 0
  fi

  ( cd backend && jq -r '(.packages + ."packages-dev")[] | "\(.name) \(.version)"' composer.lock | sort ) > "$after"
  local summary
  summary="$(join -a2 -e '(nuevo)' -o '0,1.2,2.2' "$before" "$after" | awk '$2!=$3 {print "- " $1 ": " $2 " → " $3}')"
  echo "$summary"

  info "audit"
  run_composer audit --locked || warn "composer audit reporta CVEs: revisar antes de mergear"

  info "verify (rebuild del stack dev con las nuevas versiones)"
  if ! scripts/oliva/verify.sh; then
    warn "verify FALLÓ. Los cambios quedan SIN commitear en $branch para inspeccionar."
    warn "Para descartar: git checkout -- . && git switch - && git branch -D $branch"
    exit 1
  fi

  git add backend/composer.json backend/composer.lock frontend/package.json frontend/yarn.lock
  git commit -q -F - <<EOF
chore(deps): update dependencies within constraints ($(date +%F))

Composer packages changed:
${summary:-- (sin cambios en composer.lock)}

Frontend: yarn upgrade within package.json ranges (see yarn.lock diff).
Verified with scripts/oliva/verify.sh.
EOF
  prune_build_leftovers
  info "commit hecho en $branch. Si está bien: git switch main && git merge --no-ff $branch"
  rm -f "$before" "$after"
}

case "${1:-}" in
  due)    cmd_due ;;
  report) cmd_report ;;
  update) cmd_update ;;
  *) sed -n '3,15p' "$0"; exit 1 ;;
esac
