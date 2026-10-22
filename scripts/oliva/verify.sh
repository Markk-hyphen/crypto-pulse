#!/usr/bin/env bash
#
# Smoke + tests contra el stack DEV de este checkout. Es la red de seguridad de todo
# cambio de dependencias o sync con Oliva: si pasa, el cambio no rompió nada que se vea.
#
# Uso (desde la raíz del repo):
#   scripts/oliva/verify.sh                       # todo
#   OLIVA_VERIFY_SKIP="schema prod-build" scripts/oliva/verify.sh
#
# Pasos (nombre entre corchetes = lo que acepta OLIVA_VERIFY_SKIP):
#   [up]          docker compose up -d --build --wait (respeta COMPOSE_PROFILES del .env)
#   [php-version] el PHP que CORRE coincide con el pin de backend/Dockerfile
#   [health]      GET /health
#   [mercure]     publish con JWT + suscriptor CON token recibe el update privado y
#                 suscriptor anónimo NO (la regresión real de FrankenPHP 1.13.1)
#   [migrations]  no hay migraciones pendientes
#   [schema]      doctrine:schema:validate (CMP lo saltea: drift conocido de pgvector)
#   [phpunit]     suite completa
#   [prod-build]  buildea las imágenes de prod (composer --no-dev, dump-env, vite build)
#
# Corre sobre la DB de dev (es la de siempre); no crea ni borra stacks.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_repo_root
[[ -f .env ]] || die "falta .env (cp .env.example .env)"

SKIP=" ${OLIVA_VERIFY_SKIP:-} "
RESULTS=()
FAILED=0

step() {
  local name="$1"; shift
  if [[ "$SKIP" == *" $name "* ]]; then RESULTS+=("SKIP  $name"); return 0; fi
  info "[$name]"
  if "$@"; then RESULTS+=("PASS  $name"); else RESULTS+=("FAIL  $name"); FAILED=1; fi
}

be() { docker compose exec -T backend "$@"; }

do_up()         { docker compose up -d --build --wait; }
do_health()     { be curl -fsS http://localhost/health && echo; }
do_migrations() { be bin/console doctrine:migrations:up-to-date; }
do_schema()     { be bin/console doctrine:schema:validate; }
do_phpunit()    { be php vendor/bin/phpunit; }
do_prod_build() { docker compose -f docker-compose.yml -f docker-compose.prod.yml build backend frontend; }

# Versión de PHP que CORRE en el backend vs. el pin de backend/Dockerfile.
# Un build verde NO prueba que estés parcheado: si el `up` reusó un container vivo, sus
# workers siguen sirviendo el PHP anterior. Es exactamente el modo de falla de un CVE como
# PHP2Shell, donde el fix solo toma efecto al recrear el proceso — el paso que más fácil se
# saltea en un apuro, y el que no deja rastro. Este step cierra ese loop.
# También falla si el tag no pinea un patch exacto: un tag flotante es la regresión que ya
# rompió Mercure una vez (ver comentario del FROM en backend/Dockerfile).
do_php_version() {
  local pin running
  pin="$(backend_base_image | grep -oE 'php[0-9]+\.[0-9]+\.[0-9]+$' | sed 's/^php//')"
  if [[ -z "$pin" ]]; then
    warn "backend/Dockerfile no pinea un PHP exacto (x.y.z) en el FROM ... AS frankenphp_upstream"
    warn "un tag flotante hace que un rebuild cualquiera cambie el runtime sin aviso: pinealo"
    return 1
  fi
  running="$(be php -r 'echo PHP_VERSION;' | tr -d '\r')"
  if [[ "$running" != "$pin" ]]; then
    warn "el backend corre PHP $running pero backend/Dockerfile pinea $pin"
    warn "si venís de bumpear la imagen base, el container es viejo:"
    warn "  docker compose up -d --force-recreate backend"
    return 1
  fi
  echo "PHP $running (coincide con el pin de backend/Dockerfile)"
}

# JWT HS256 firmado con la clave del hub (la misma que usa MercureBundle).
jwt() {
  local key="$1" payload="$2" h p s
  b64() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }
  h="$(printf '{"alg":"HS256","typ":"JWT"}' | b64)"
  p="$(printf '%s' "$payload" | b64)"
  s="$(printf '%s.%s' "$h" "$p" | openssl dgst -sha256 -hmac "$key" -binary | b64)"
  printf '%s.%s.%s' "$h" "$p" "$s"
}

do_mercure() {
  local key pub sub marker
  key="$(be printenv MERCURE_PUBLISHER_JWT_KEY | tr -d '\r')"
  [[ -n "$key" ]] || { warn "MERCURE_PUBLISHER_JWT_KEY vacía en el backend"; return 1; }
  pub="$(jwt "$key" '{"mercure":{"publish":["*"]}}')"
  sub="$(jwt "$key" '{"mercure":{"subscribe":["*"]}}')"
  marker="oliva-verify-$RANDOM$RANDOM"
  # Dos suscriptores (con token / anónimo) escuchan 4s; a mitad se publica un update PRIVADO.
  be sh -c '
    hub=http://localhost/.well-known/mercure; t="topic=oliva/verify"
    curl -sN --max-time 4 -H "Authorization: Bearer $1" "$hub?$t" > /tmp/v-auth.out &
    curl -sN --max-time 4 "$hub?$t" > /tmp/v-anon.out &
    sleep 1
    curl -fsS -X POST -H "Authorization: Bearer $2" -d "$t" -d "data=$3" -d private=on "$hub" >/dev/null || exit 11
    wait
    grep -q "$3" /tmp/v-auth.out || exit 12
    ! grep -q "$3" /tmp/v-anon.out || exit 13
  ' _ "$sub" "$pub" "$marker"
  local rc=$?
  case $rc in
    0)  echo "publish OK, privado entregado solo al suscriptor con token";;
    11) warn "el hub rechazó el publish (publisher_jwt)";;
    12) warn "el suscriptor con token NO recibió el update privado (subscriber_jwt)";;
    13) warn "un suscriptor ANÓNIMO recibió un update privado";;
  esac
  return $rc
}

step up          do_up
step php-version do_php_version
step health      do_health
step mercure     do_mercure
step migrations  do_migrations
step schema      do_schema
step phpunit     do_phpunit
step prod-build  do_prod_build

echo
echo "── verify: $(basename "$PWD") ──"
printf '   %s\n' "${RESULTS[@]}"
exit $FAILED
