#!/usr/bin/env bash
#
# Mantenimiento de dependencias de una app Oliva (sirve igual en Oliva y en cada fork).
#
#   scripts/oliva/deps.sh due         # offline, 1 segundo: ¿toca ciclo? ¿toca audit? (chequeo de inicio de sesión)
#   scripts/oliva/deps.sh report      # qué hay viejo: imágenes base, EOL, composer, yarn, actions, CVEs
#   scripts/oliva/deps.sh update      # rama chore/deps-<fecha>: bump DENTRO de los rangos + verify + commit
#   scripts/oliva/deps.sh audit       # solo CVEs, a demanda (fuera del ciclo): composer + yarn + imágenes (Trivy)
#   scripts/oliva/deps.sh scan-images # solo las imágenes base con Trivy (lo usa el CI)
#
# Qué automatiza y qué no: `update` sube patch/minor dentro de las restricciones de
# composer.json/package.json — lo que casi nunca rompe y siempre conviene. Los saltos
# de imagen base (FrankenPHP, node, postgres, rabbitmq) y los majors de paquetes NO se
# automatizan: `report` los lista y se hacen a mano, uno por commit, con verify.sh.
# Motivo: el único update que rompió algo en serio fue un salto de FrankenPHP (Mercure).
#
# Dos cadencias distintas: el CICLO de deps (`due`/`report`/`update`, ~45 días) es por
# FRESCURA; el AUDIT (`audit`, ~7 días) es por SEGURIDAD — un CVE no espera al ciclo.
# `audit` cubre la capa que composer/yarn audit no ven: el SO y los binarios DENTRO de
# las imágenes base (Trivy). Fuentes: una por capa, no apiladas (ver docs/oliva/actualizaciones.md).
set -euo pipefail
# BASH_SOURCE (no $0) para que el locate de libs funcione igual al ejecutar y al sourcear
# (los tests sourcean este archivo para probar las funciones de runtime; ver guarda al final).
_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_here/lib.sh"
source "$_here/../lib/docker-prune.sh"
require_repo_root

DUE_DAYS="${OLIVA_DEPS_DUE_DAYS:-45}"
AUDIT_DUE_DAYS="${OLIVA_AUDIT_DUE_DAYS:-7}"   # CVEs se mueven más rápido que el ciclo de frescura
AUDIT_STATE=".oliva/audit-state"               # fecha del último audit (por-repo, gitignored)
# Trivy pinneado (aquasec/trivy solo publica tags exactos, sin major.minor). Se corre como
# contenedor: nada que instalar en el host. Bumpearlo en el ciclo como cualquier otra imagen.
# OJO: la v0.69.4 estuvo comprometida (incidente de supply-chain 2026-03) → nunca bajar de 0.71.1.
TRIVY_VERSION="${OLIVA_TRIVY_VERSION:-0.72.0}"

# ── due ────────────────────────────────────────────────────────────────────────
cmd_due() {
  local last days
  last="$(git log -1 --format=%cs --grep='^chore(deps)' 2>/dev/null || true)"
  if [[ -z "$last" ]]; then
    echo "deps: nunca se corrió un ciclo (no hay commits chore(deps)). Correr: scripts/oliva/deps.sh report"
  else
    days=$(( ( $(date +%s) - $(date -d "$last" +%s) ) / 86400 ))
    if (( days >= DUE_DAYS )); then
      echo "deps: último ciclo hace ${days} días (${last}) → TOCA. Correr: scripts/oliva/deps.sh report"
    else
      echo "deps: último ciclo hace ${days} días (${last}), OK (umbral ${DUE_DAYS})."
    fi
  fi
  audit_due_line
}

# Frescura del audit de seguridad (independiente del ciclo de deps). Offline: solo lee
# la fecha que `cmd_audit` dejó en AUDIT_STATE. Es el "aviso por advisory" en el flujo.
audit_due_line() {
  local last days
  if [[ ! -f "$AUDIT_STATE" ]]; then
    echo "audit: nunca se corrió. Correr: scripts/oliva/deps.sh audit"
    return 0
  fi
  last="$(cat "$AUDIT_STATE")"
  days=$(( ( $(date +%s) - $(date -d "$last" +%s) ) / 86400 ))
  if (( days >= AUDIT_DUE_DAYS )); then
    echo "audit: último hace ${days} días (${last}) → TOCA (CVEs no esperan). Correr: scripts/oliva/deps.sh audit"
  else
    echo "audit: último hace ${days} días (${last}), OK (umbral ${AUDIT_DUE_DAYS})."
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

# Imágenes base EXTERNAS (no las stages internas del Dockerfile), con los tags
# resueltos a algo concreto (pg${POSTGRES_VERSION:-15} → pg15). Lista compartida por
# el reporte de novedades (report_images) y el scan de CVEs (scan_images).
base_images() {
  { awk '/^FROM / && $2 !~ /^(frankenphp_|base|builder)/ {print $2}' backend/Dockerfile frontend/Dockerfile
    grep -hoE 'image: *[a-z0-9./-]+:[A-Za-z0-9.${}_:-]+' docker-compose*.yml \
      | sed -E 's/image: *//' | grep -v 'COMPOSE_PROJECT_NAME'; } \
    | sed -E 's/\$\{POSTGRES_VERSION:-([0-9]+)\}/\1/' | sort -u
}

report_images() {
  echo "## Imágenes base (actual → más nueva con la misma forma de tag)"
  local img newest
  while read -r img; do
    [[ -z "$img" ]] && continue
    newest="$(hub_newer_tags "$img" || true)"
    if [[ -z "$newest" ]]; then echo "   $img → (sin datos)"
    elif [[ "$newest" == "${img##*:}" ]]; then echo "   ✓  $img (al día)"
    else echo "   ↑  $img → ${newest}"; fi
  done < <(base_images)
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

# Trivy sobre cada imagen base fijada. HIGH/CRITICAL con fix disponible (--ignore-unfixed):
# lo accionable, sin ruido de CVEs que no se pueden resolver hasta que el upstream rebuildee.
# Esta es la capa que composer/yarn audit NO ven: SO + binarios DENTRO de la imagen (OpenSSL
# del postgres, el binario de Caddy en FrankenPHP, …). Escanea el REF BASE, no la imagen prod
# buildeada: ahí viven casi todos los CVEs de imagen y no hace falta buildear nada. Trivy corre
# como contenedor pinneado; su DB y las capas escaneadas se cachean en un volumen de tooling
# (mismo criterio que oliva-tools/composer de lib.sh). Devuelve != 0 si alguna imagen tiene findings.
scan_images() {
  command -v docker >/dev/null 2>&1 || { warn "docker no disponible: scan de imágenes salteado"; return 0; }
  # .trivyignore (CVEs aceptados/infixables) vive en el repo pero Trivy corre en un
  # contenedor: hay que montarlo y apuntarlo con --ignorefile, no lo toma del host solo.
  local img rc=0 ignore_mount=() ignore_flag=()
  if [[ -f .trivyignore ]]; then
    ignore_mount=(-v "$PWD/.trivyignore:/tmp/.trivyignore:ro")
    ignore_flag=(--ignorefile /tmp/.trivyignore)
  fi
  local out status
  while read -r img; do
    [[ -z "$img" ]] && continue
    echo "   • $img"
    # Capturamos salida + estado SIN pipe directo: con set -e + pipefail, `trivy ... | sed`
    # saldría != 0 en la 1ª imagen con findings (--exit-code 1) y abortaría el loop. El
    # `|| status=$?` neutraliza eso y deja seguir con las demás imágenes.
    status=0
    out="$(docker run --rm -v oliva-tools-trivy-cache:/root/.cache/ "${ignore_mount[@]}" \
      "aquasec/trivy:${TRIVY_VERSION}" image \
      --severity HIGH,CRITICAL --ignore-unfixed --no-progress --quiet \
      "${ignore_flag[@]}" --exit-code 1 "$img" 2>&1)" || status=$?
    printf '%s\n' "$out" | sed 's/^/     /'
    if (( status != 0 )); then rc=1; fi
  done < <(base_images)
  return $rc
}

report_trivy() {
  echo "## Imágenes base — CVEs (Trivy ${TRIVY_VERSION}, HIGH/CRITICAL con fix)"
  scan_images || true   # en el reporte es informativo; el exit code lo maneja `audit`
  echo "   (pin de Trivy: bumpearlo en el ciclo como cualquier imagen base)"
}

# ── runtime (PHP / FrankenPHP) ─────────────────────────────────────────────────────
# La capa que NI composer/yarn audit NI Trivy ven: el runtime compilado del source dentro
# de la imagen base. PHP y el binario de FrankenPHP salen compilados (no como paquetes),
# así que Trivy no los matchea contra ninguna CVE DB — probado: no detectó PHP2Shell. Esta
# capa avisa cuando el upstream ya publicó un patch más nuevo (no es ni pretende ser detección
# de lo no publicado — eso no existe). Una fuente autoritativa por runtime, no advisory-matching:
#   - PHP: php.net lista cada release de la rama; chequeo DURO = ¿hay un patch más nuevo?
#   - FrankenPHP: releases de GitHub; chequeo BLANDO (solo frescura, avisa sin fallar el audit) —
#     su módulo Go sale pseudo-versionado (v0.0.0-…) y no se matchea con advisories con confianza.
#
# El dato sale del tag del FROM (dunglas/frankenphp:<franken>-php<php>), que es el punto
# SENSIBLE: si no se puede confiar en el parseo, NO se reporta "al día" (eso sería un falso
# verde, peor que no tener la capa). Cada guarda que no puede verificar AVISA y se saltea.
check_runtime() {
  local rc=0 ref tag
  ref="$(backend_base_image 2>/dev/null || true)"
  # C1 — ¿es la imagen frankenphp? Si un fork cambió la base, el parseo "phpX.Y.Z" no aplica.
  if [[ -z "$ref" || "$ref" != *frankenphp* ]]; then
    warn "runtime: la imagen base del backend no es frankenphp (ref: '${ref:-vacío}') — capa de runtime salteada"
    return 0
  fi
  tag="${ref##*:}"                      # 1.13.2-php8.3.36
  check_php_runtime "$tag" || rc=1      # DURO: puede poner rc=1
  check_frankenphp_runtime "$tag" || true   # BLANDO: nunca cambia rc
  return $rc
}

# DURO: 1 si hay un patch de PHP más nuevo en la misma rama. Doble verificación contra falso
# verde — la versión pinneada TIENE que figurar en php.net para esa rama; si no, el parseo o
# la rama están mal → avisa y saltea (no reporta "al día").
check_php_runtime() {
  local tag="$1" php branch body versions newer v tags vdate
  # C2 — extraer X.Y.Z de "…-phpX.Y.Z". Regex estricto: 3 componentes numéricos.
  php="$(grep -oE 'php[0-9]+\.[0-9]+\.[0-9]+' <<<"$tag" | head -1 | sed 's/^php//' || true)"
  if [[ -z "$php" ]]; then
    warn "runtime PHP: no pude extraer la versión de PHP del tag '$tag' (¿cambió el formato del FROM?) — salteado"
    return 0
  fi
  branch="${php%.*}"                    # 8.3.36 → 8.3
  body="$(curl -fsS "https://www.php.net/releases/?json&version=${branch}&max=100" 2>/dev/null || true)"
  if [[ -z "$body" ]] || ! jq -e . >/dev/null 2>&1 <<<"$body"; then
    warn "runtime PHP: no pude consultar php.net para la rama $branch (¿red?) — salteado (NO es 'al día')"
    return 0
  fi
  # Solo versiones de ESTA rama (defensa extra aunque la API ya filtra), ordenadas ascendente.
  versions="$(jq -r 'keys_unsorted[]' <<<"$body" | grep -E "^${branch//./\\.}\.[0-9]+$" | sort -V || true)"
  # C3 — la versión pinneada DEBE estar en la lista; si no, no confío en la comparación.
  if ! grep -qxF "$php" <<<"$versions"; then
    warn "runtime PHP: la versión pinneada $php no figura en php.net/${branch} (¿parseo erróneo o rama EOL?) — salteado (NO es 'al día')"
    return 0
  fi
  # Lo posterior al pin en orden de versión = los patches más nuevos de la rama.
  newer="$(awk -v pin="$php" 'found; $0==pin{found=1}' <<<"$versions")"
  if [[ -z "$newer" ]]; then
    echo "   ✓  PHP $php: al día en la rama $branch"
    return 0
  fi
  echo "   ⛔ PHP $php: hay patch(es) más nuevo(s) en la rama $branch — bumpear la imagen frankenphp del FROM:"
  while read -r v; do
    [[ -z "$v" ]] && continue
    tags="$(jq -r --arg v "$v" '.[$v].tags // [] | join(",")' <<<"$body" 2>/dev/null || true)"
    vdate="$(jq -r --arg v "$v" '.[$v].date // "?"' <<<"$body" 2>/dev/null || true)"
    echo "        → PHP $v (${vdate:-?}${tags:+, $tags})"
  done <<<"$newer"
  return 1
}

# BLANDO: solo frescura contra el último release de GitHub; NUNCA cambia el rc del audit.
# No matchea advisories (el módulo Go sale pseudo-versionado). GitHub 301-redirige
# dunglas/frankenphp (el repo se movió) → curl -L es obligatorio o vuelve null.
check_frankenphp_runtime() {
  local tag="$1" cur latest newest
  cur="$(grep -oE '^[0-9]+\.[0-9]+\.[0-9]+' <<<"$tag" | head -1 || true)"
  if [[ -z "$cur" ]]; then
    warn "runtime FrankenPHP: no pude extraer la versión del tag '$tag' — salteado"
    return 0
  fi
  latest="$(curl -fsSL "https://api.github.com/repos/dunglas/frankenphp/releases/latest" 2>/dev/null \
            | jq -r '.tag_name // empty' 2>/dev/null | sed 's/^v//' || true)"
  if [[ -z "$latest" ]]; then
    warn "runtime FrankenPHP: no pude consultar los releases de GitHub — salteado"
    return 0
  fi
  newest="$(printf '%s\n%s\n' "$cur" "$latest" | sort -V | tail -1)"
  if [[ "$cur" == "$latest" || "$newest" == "$cur" ]]; then
    echo "   ✓  FrankenPHP $cur: al día (último release $latest)"
  else
    echo "   ⚠️  FrankenPHP $cur → $latest disponible (solo frescura, no es un advisory; flag menor)"
  fi
  return 0
}

report_runtime() {
  echo "## Runtime PHP / FrankenPHP (compilados del source — invisibles a Trivy)"
  check_runtime || true   # en el reporte es informativo; el exit code lo maneja `audit`
}

cmd_report() {
  echo "# Reporte de dependencias — $(basename "$PWD") (Oliva $(local_oliva_version)) — $(date +%F)"
  echo
  report_eol; echo
  report_images; echo
  report_composer; echo
  report_yarn; echo
  report_actions; echo
  report_trivy; echo
  report_runtime
}

# ── audit ────────────────────────────────────────────────────────────────────────
# Solo CVEs, a demanda, fuera del ciclo de 45 días. Una fuente por capa: composer audit
# (paquetes PHP), yarn audit (paquetes JS), Trivy (SO + binarios de las imágenes base) y
# runtime (PHP/FrankenPHP compilados del source, que Trivy no ve — ver check_runtime).
# Siempre deja la fecha en AUDIT_STATE (lo que mira `due`): el estado es "cuándo corriste
# audit", no "quedó limpio" — los CVEs encontrados ya los viste en la salida.
cmd_audit() {
  local rc=0
  echo "# Audit de seguridad — $(basename "$PWD") (Oliva $(local_oliva_version)) — $(date +%F)"
  echo
  echo "## Composer (CVEs)"
  run_composer audit --locked || { rc=1; warn "composer audit reporta CVEs"; }
  echo
  echo "## Frontend (yarn audit)"
  run_yarn audit || { rc=1; warn "yarn audit reporta CVEs"; }
  echo
  echo "## Imágenes base (Trivy ${TRIVY_VERSION}, HIGH/CRITICAL con fix)"
  scan_images || { rc=1; warn "Trivy reporta CVEs en imágenes base"; }
  echo
  echo "## Runtime PHP / FrankenPHP (compilados del source — invisibles a Trivy)"
  check_runtime || { rc=1; warn "runtime: PHP está atrás en su rama (ver arriba)"; }

  mkdir -p "$(dirname "$AUDIT_STATE")"
  date +%F > "$AUDIT_STATE"
  echo
  if (( rc == 0 )); then
    info "audit limpio. Fecha guardada en $AUDIT_STATE."
  else
    warn "audit encontró CVEs (ver arriba). Fecha guardada en $AUDIT_STATE."
  fi
  return $rc
}

# Solo las imágenes base (lo usa el CI). No toca paquetes ni el state file.
cmd_scan_images() {
  echo "# Scan de imágenes base — Trivy ${TRIVY_VERSION} (HIGH/CRITICAL con fix)"
  scan_images
}

# ── update ─────────────────────────────────────────────────────────────────────
cmd_update() {
  require_clean_tree
  require_bounded_constraints
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
  # ⇑ MAJOR: los techos frenan majors de las deps DIRECTAS; una transitiva puede saltar si la
  # directa declara compatibilidad (orm acepta dbal ^3 || ^4). Mirar el changelog antes de mergear.
  # En 0.x el "major" es el minor (semver de composer: ^0.4 = 0.4.*).
  summary="$(join -a2 -e '(nuevo)' -o '0,1.2,2.2' "$before" "$after" | awk '
    function major(v,  p) { sub(/^v/, "", v); split(v, p, "."); return p[1] == "0" ? p[1] "." p[2] : p[1] }
    $2 != $3 { m = ($2 != "(nuevo)" && major($2) != major($3)) ? "  ⇑ MAJOR" : ""; print "- " $1 ": " $2 " → " $3 m }')"
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

# Dispatcher solo al EJECUTAR el script; al sourcearlo (tests) no corre, para poder
# llamar las funciones de runtime con tags fabricados sin disparar un subcomando.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    due)         cmd_due ;;
    report)      cmd_report ;;
    update)      cmd_update ;;
    audit)       cmd_audit ;;
    scan-images) cmd_scan_images ;;
    *) sed -n '3,18p' "$0"; exit 1 ;;
  esac
fi
