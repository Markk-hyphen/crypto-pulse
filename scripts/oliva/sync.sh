#!/usr/bin/env bash
#
# Sync de un fork con Oliva (upstream). Se corre DESDE EL FORK, en su raíz.
#
#   scripts/oliva/sync.sh check          # offline-friendly, segundos: ¿cuánto atrás estoy? + notas de upgrade
#   scripts/oliva/sync.sh start [ref]    # rama chore/oliva-sync-<versión>, merge de Oliva, clasifica conflictos
#   scripts/oliva/sync.sh locks          # regenera composer.lock / yarn.lock (durante o después del merge)
#   scripts/oliva/sync.sh verify         # = scripts/oliva/verify.sh (respeta OLIVA_VERIFY_SKIP)
#
# Flujo completo: check → start → (resolver conflictos) → locks → git commit → verify
#                 → git switch main && git merge --no-ff chore/oliva-sync-… (flujo solo-dev, sin PR)
#
# El remote de Oliva se llama `oliva-upstream` (OLIVA_REMOTE para cambiarlo). Si no
# existe, `check`/`start` dicen cómo agregarlo.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_repo_root

UP="${OLIVA_REMOTE}/main"

ensure_remote() {
  git remote get-url "$OLIVA_REMOTE" >/dev/null 2>&1 \
    || die "no existe el remote '$OLIVA_REMOTE'. Agregalo: git remote add $OLIVA_REMOTE $OLIVA_REMOTE_URL"
}

fetch_upstream() {
  git fetch -q "$OLIVA_REMOTE" main 2>/dev/null \
    || warn "no pude hacer fetch de $OLIVA_REMOTE (¿sin red?). Uso lo último conocido."
}

upstream_version() { git show "${1:-$UP}:OLIVA_VERSION" 2>/dev/null || echo "0.0.0"; }

# Imprime las secciones de docs/oliva/UPGRADING.md de <ref> más nuevas que <versión local>.
upgrade_notes() {
  local ref="$1" since="$2"
  git show "$ref:docs/oliva/UPGRADING.md" 2>/dev/null | awk -v since="$since" '
    /^## [0-9]+\.[0-9]+\.[0-9]+/ { ver=$2; printing = (ver != since); if (ver == since) exit }
    printing' | sed 's/^/   /'
}

is_owned() {
  local f="$1" p
  while IFS= read -r p; do
    [[ -z "$p" || "$p" == \#* ]] && continue
    if [[ "$p" == */ ]]; then [[ "$f" == "$p"* ]] && return 0
    else [[ "$f" == "$p" ]] && return 0; fi
  done < <(git show "${OWNED_REF:-HEAD}:scripts/oliva/owned-paths.txt" 2>/dev/null || cat scripts/oliva/owned-paths.txt 2>/dev/null)
  return 1
}

# ── check ──────────────────────────────────────────────────────────────────────
cmd_check() {
  ensure_remote; fetch_upstream
  local mine theirs behind oldest
  mine="$(local_oliva_version)"; theirs="$(upstream_version)"
  behind="$(git rev-list --count HEAD.."$UP")"
  if (( behind == 0 )); then
    echo "oliva: al día (Oliva $mine)."
    return 0
  fi
  oldest="$(git log --reverse --format=%cs HEAD.."$UP" | head -1)"
  echo "oliva: este fork está en Oliva ${mine/0.0.0/<1.1 (sin OLIVA_VERSION)} y upstream en $theirs:"
  echo "       $behind commits sin traer, el más viejo del $oldest. Sync: scripts/oliva/sync.sh start"
  local notes; notes="$(upgrade_notes "$UP" "$mine")"
  [[ -n "$notes" ]] && { echo; echo "   Notas de upgrade pendientes (docs/oliva/UPGRADING.md):"; echo "$notes"; }
  return 0
}

# ── start ──────────────────────────────────────────────────────────────────────
cmd_start() {
  ensure_remote
  [[ ! -f "$(git rev-parse --git-dir)/MERGE_HEAD" ]] || die "ya hay un merge en curso. Terminalo (o git merge --abort)."
  require_clean_tree
  fetch_upstream
  local ref="${1:-$UP}" mine theirs branch
  mine="$(local_oliva_version)"; theirs="$(upstream_version "$ref")"
  (( $(git rev-list --count HEAD.."$ref") > 0 )) || { info "nada para traer: ya incluye $ref."; return 0; }

  # rerere: git recuerda cómo resolviste cada conflicto y lo reaplica en el próximo sync.
  git config rerere.enabled true
  git config rerere.autoupdate true

  branch="chore/oliva-sync-${theirs}"
  git show-ref -q --verify "refs/heads/$branch" && branch="${branch}-$(date +%Y%m%d%H%M)"
  git switch -q -c "$branch"
  info "rama $branch — merge de $ref (Oliva $theirs) sobre Oliva $mine"

  local notes; notes="$(upgrade_notes "$ref" "$mine")"
  if [[ -n "$notes" ]]; then
    echo; echo "── Notas de upgrade (leer ANTES de resolver) ──"; echo "$notes"; echo
  fi

  if git merge --no-ff --no-edit -m "merge: sync Oliva ${theirs} into $(basename "$PWD")" "$ref"; then
    info "merge LIMPIO."
  else
    echo
    echo "── Conflictos ──"
    local f
    OWNED_REF="$ref"
    while IFS= read -r f; do
      case "$f" in
        agent-commits.md|commits.md)
          echo "   [FORK]   $f  → es el log del proyecto, no se mezcla con el de Oliva: git checkout --ours -- $f";;
        backend/composer.lock|frontend/yarn.lock)
          echo "   [LOCK]   $f  → no lo resuelvas a mano: scripts/oliva/sync.sh locks";;
        backend/symfony.lock)
          echo "   [LOCK]   $f  → combinar a mano (registro de recipes; casi siempre: unión de ambos)";;
        *)
          if is_owned "$f"; then
            # NUNCA sugerir theirs a ciegas: el fork pudo haber agregado algo que necesita
            # (caso real: bcmath en backend/Dockerfile). Mostrar qué cambió el fork.
            echo "   [OLIVA]  $f  → es del framework. Lo que el FORK cambió desde el último sync:"
            git diff "$(git merge-base HEAD MERGE_HEAD)" HEAD -- "$f" \
              | grep -E '^[+-][^+-]' | grep -vE '^[+-][[:space:]]*(#|//|$)' | head -12 | sed 's/^/              /'
            echo "            Si son solo comentarios o lo mismo que trae Oliva: git checkout --theirs -- $f"
            echo "            Si es algo que el fork necesita: moverlo a su extension point (UPGRADING.md)"
            echo "            o backportearlo a Oliva, y recién ahí tomar theirs."
          else
            echo "   [MANUAL] $f  → combinar: mantener lo del fork + traer lo nuevo de Oliva"
          fi;;
      esac
    done < <(git diff --name-only --diff-filter=U)
    echo
    echo "   Después: resolver composer.json/package.json si aparecen, scripts/oliva/sync.sh locks,"
    echo "   git add -A && git commit --no-edit, y scripts/oliva/sync.sh verify."
  fi

  # Drift: archivos de Oliva que el fork editó desde el último sync (fuente de conflictos).
  local fork_head base drift=()
  if [[ -f "$(git rev-parse --git-dir)/MERGE_HEAD" ]]; then fork_head=HEAD; else fork_head=HEAD^1; fi
  base="$(git merge-base "$fork_head" "$ref")"
  OWNED_REF="$ref"
  # Solo cuenta si además difiere de Oliva: un cambio idéntico en los dos lados no es drift.
  while IFS= read -r f; do
    is_owned "$f" && ! git diff --quiet "$fork_head" "$ref" -- "$f" && drift+=("$f")
  done < <(git diff --name-only "$base" "$fork_head")
  if (( ${#drift[@]} )); then
    echo
    echo "── Drift: archivos de Oliva que este fork tiene distintos (ver scripts/oliva/owned-paths.txt) ──"
    printf '   %s\n' "${drift[@]}"
    echo "   Si es intencional, documentalo en el AGENTS.md del fork; si no, alinealo con Oliva."
  fi

  local changed_manifests
  changed_manifests="$(git diff --name-only "$base" "$ref" -- backend/composer.json frontend/package.json backend/composer.lock frontend/yarn.lock | tr '\n' ' ')"
  if [[ -n "$changed_manifests" ]]; then
    echo
    info "Oliva cambió dependencias ($changed_manifests) → corré scripts/oliva/sync.sh locks"
  fi
  info "al terminar: scripts/oliva/sync.sh verify y, si pasa, git switch main && git merge --no-ff $branch"
}

# ── locks ──────────────────────────────────────────────────────────────────────
# composer.lock: se parte del lock del FORK y se le re-aplican solo los paquetes que
# Oliva cambió entre la base y su versión ("replay" de los bumps de upstream). Así no
# se arrastran updates que nadie pidió en los paquetes propios del fork.
# yarn.lock: yarn 1 resuelve solo un lock con marcadores de conflicto al instalar; si
# el fork no tenía lock, se genera contra SU package.json.
cmd_locks() {
  local gitdir ours theirs base
  gitdir="$(git rev-parse --git-dir)"
  if [[ -f "$gitdir/MERGE_HEAD" ]]; then ours=HEAD; theirs=MERGE_HEAD
  elif git rev-parse -q --verify HEAD^2 >/dev/null; then ours=HEAD^1; theirs=HEAD^2
  else die "no hay merge en curso ni el último commit es un merge: no sé contra qué regenerar."
  fi
  base="$(git merge-base "$ours" "$theirs")"

  for manifest in backend/composer.json frontend/package.json; do
    grep -qE '^(<<<<<<<|>>>>>>>)' "$manifest" && die "$manifest tiene marcadores de conflicto: resolvelo primero."
  done
  require_bounded_constraints

  # composer
  if ! git diff --quiet "$base" "$theirs" -- backend/composer.lock backend/composer.json \
     || grep -qE '^(<<<<<<<|>>>>>>>)' backend/composer.lock; then
    local pkgs
    pkgs="$(comm -13 <(composer_lock_versions "$base") <(composer_lock_versions "$theirs") | awk '{print $1}' | sort -u | tr '\n' ' ')"
    git show "$ours:backend/composer.lock" > backend/composer.lock
    if [[ -n "${pkgs// }" ]]; then
      info "composer: re-aplicando bumps de Oliva: $pkgs"
      # shellcheck disable=SC2086
      run_composer update "$IGNORE_EXT" --no-install --no-scripts --with-dependencies $pkgs
    else
      info "composer: Oliva no cambió versiones; solo refresco el content-hash"
      run_composer update "$IGNORE_EXT" --no-install --no-scripts --lock
    fi
    git add backend/composer.lock
  else
    info "composer: sin cambios de Oliva."
  fi

  # yarn
  if [[ -f frontend/yarn.lock ]] || git cat-file -e "$theirs:frontend/yarn.lock" 2>/dev/null; then
    if ! git diff --quiet "$base" "$theirs" -- frontend/yarn.lock frontend/package.json \
       || grep -qE '^(<<<<<<<|>>>>>>>)' frontend/yarn.lock 2>/dev/null; then
      info "yarn: regenerando frontend/yarn.lock contra el package.json del fork"
      run_yarn install
      git add frontend/yarn.lock
    else
      info "yarn: sin cambios de Oliva."
    fi
  fi

  if [[ -f "$gitdir/MERGE_HEAD" ]]; then
    info "locks listos y en staging. Seguí: resolver lo que quede, git add -A && git commit --no-edit"
  else
    info "locks regenerados. Commitealos: git commit -m 'chore: regenerate lockfiles after Oliva sync'"
  fi
}

case "${1:-}" in
  check)  cmd_check ;;
  start)  shift; cmd_start "$@" ;;
  locks)  cmd_locks ;;
  verify) exec "$(dirname "$0")/verify.sh" ;;
  *) sed -n '3,14p' "$0"; exit 1 ;;
esac
