# UPGRADING — notas para forks

Una sección por versión de Oliva, la más nueva arriba. `scripts/oliva/sync.sh` muestra
al fork las secciones más nuevas que su `OLIVA_VERSION`. Formato fijo (lo parsea el script):
encabezado `## X.Y.Z — fecha`, después **Acción requerida en el fork** (pasos concretos,
o "ninguna") y **Qué cambió** (resumen; el detalle está en `git log`).

## 1.1.5 — 2026-10-22

> ⚠️ **Release de seguridad. Syncear y rebuildear cuanto antes.** Parchea dos RCE sin
> autenticación (CVSS 9.2) que afectan a todo fork que corra la imagen base anterior.

**Acción requerida en el fork**

1. **Sync + rebuild, y RECREAR los containers — no basta un `restart`.** El parche no toma
   efecto en procesos vivos: un `docker compose restart` deja los workers de FrankenPHP
   sirviendo el PHP viejo, sin dejar rastro. `./scripts/deploy.sh` ya hace
   `down --remove-orphans` antes del `up`, así que alcanza con eso. En dev:
   `docker compose up -d --build --force-recreate`.
2. **Borrar `PHP_VERSION` del `.env.backend` del fork** (si lo tiene). `.env.backend` es un
   path SHARED: el sync NO lo baja solo, hay que hacerlo a mano. No hace falta reemplazarlo
   por nada — la versión de PHP la fija el tag de la imagen base en `backend/Dockerfile`, que
   es la única fuente de verdad y baja con el sync.
3. **Destrackear `backend/config/reference.php`:** `git rm --cached backend/config/reference.php`.
   La línea del `.gitignore` baja con el sync (también SHARED → resolver a mano), pero el
   `rm --cached` hay que correrlo en cada fork. El archivo se queda en disco y se regenera
   solo; no se pierde nada.
4. **Verificar:** `scripts/oliva/verify.sh`. El step nuevo `[php-version]` falla si lo que
   corre no es el PHP pineado — es lo que confirma que el parche realmente se aplicó.

**Qué cambió**

- `backend/Dockerfile`: imagen base `dunglas/frankenphp:1.13.1-php8.3.35` →
  **`1.13.2-php8.3.36`**. PHP 8.3.36 (security release del 2026-10-21) parchea **PHP2Shell**
  (CVE-2026-109618 + CVE-2026-109619), dos RCE sin auth, CVSS 9.2. No es un CVE de
  espectador: el 109619 es estado de request stale que un worker reusa en el request
  siguiente, y `frankenphp_prod` corre worker mode.
- Se eligió FrankenPHP **1.13.2** y no el bump mínimo `1.13.1-php8.3.36` (que existe) porque
  1.13.2 es a su vez un security release y 2 de sus 4 vulns propias aplican a esta topología:
  fuga de fragmentos del input del cliente anterior vía `error_get_last()`/`libxml_get_errors()`
  en worker mode (GHSA-4gfw-9v29-gp9h) y thread pool ocupable por un cliente sin auth que
  encola requests y se desconecta (GHSA-fq24-r53r-xcx3). Sus upgrade notes son todas de
  static builds (glibc 2.28, assets de macOS) → no aplican, acá se usa la imagen Docker.
  Riesgo de regresión bajo: patch dentro del mismo minor.
- **Sin cambios de dependencias.** `composer.json` ya pedía `php: >=8.3.31`, así que 8.3.36
  lo cumple sin tocar `composer.lock`. Al ser el mismo minor el ABI de Zend no cambia: las
  extensiones por PIE (`apcu`, `amqp`, `xdebug`) recompilan igual, sin cambiar sus pines.
- `.env.backend`: **eliminada `PHP_VERSION`**, que no consumía nadie (ni el Dockerfile —no
  tiene `ARG`—, ni compose, ni el código, ni el CI) y estaba 23 patches atrás. El problema no
  era el valor viejo: se lee como "la versión de PHP del proyecto", así que al parchear un CVE
  se bumpea esa variable, se ve el número correcto y se cree que el fix se aplicó.
- `scripts/oliva/verify.sh`: step nuevo **`[php-version]`** (después de `[up]`). Compara el
  `PHP_VERSION` del container contra el pin del `Dockerfile`, y falla también si el tag deja de
  pinear un patch exacto. Un build verde no prueba que estés parcheado si el `up` reusó un
  container vivo. Mismo criterio que `[mercure]`: cada incidente pasado se vuelve una
  assertion.
- `.gitignore`: **`backend/config/reference.php` destrackeado.** Es auto-generado por
  `cache:clear` solo para autocompletado del IDE (nada en runtime lo lee), pero estaba
  trackeado y cada build lo reescribía → todo `verify.sh` dejaba sucio un archivo commiteado
  y bloqueaba a `release.sh`, que exige árbol limpio. La copia que había en git además quedó
  stale (listaba `when@development`, un entorno que el proyecto ya no usa).

## 1.1.4 — 2026-10-22

**Acción requerida en el fork**

Ninguna en el código. Rebuild (`docker compose build` / `./scripts/deploy.sh`). Relevante sobre
todo para forks con extensiones propias en `backend/php-extensions.txt` (ej. finanzas-ong: bcmath).

**Qué cambió**

- `backend/Dockerfile`: fix de orden en el stage base. El `RUN` de PIE (amqp/apcu) **purga el
  toolchain de compilación** (`$PHPIZE_DEPS`) al terminar. En 1.1.3 ese RUN quedó ANTES del
  extension point del fork (`install-php-extensions $exts`), que necesita `gcc` para compilar sus
  extensiones → un fork con algo en `php-extensions.txt` fallaba el build con `gcc: not found`
  (`exit 127`). Oliva/crypto-pulse no lo notaron porque su `php-extensions.txt` está vacío. Ahora
  el RUN de PIE va ÚLTIMO en el stage base, después del extension point, así todos los
  `install-php-extensions` corren con el toolchain presente y la purga limpia al final.

## 1.1.3 — 2026-10-22

**Acción requerida en el fork**

Ninguna en el código (el `backend/Dockerfile` es de Oliva y baja con el sync). Solo
rebuildear: `docker compose build` (dev) o `./scripts/deploy.sh` (VPS).

**Qué cambió**

- `backend/Dockerfile`: **`amqp`, `apcu` y `xdebug` migradas de PECL a PIE** (`php/pie`). El
  band-aid de 1.1.2 (pinear `install-php-extensions`) NO alcanzó: las extensiones con versión
  pineada se siguen bajando de `pecl.php.net`, que está en phase-out e intermitente → el CI
  seguía rompiendo con `exit 100` (ahora en `xdebug`). PIE baja de Packagist/GitHub, nunca toca
  `pecl.php.net`. La imagen oficial de PIE se monta solo en build-time
  (`--mount=type=bind,from=ghcr.io/php/pie:1.5.3-bin`), no queda en la imagen final. amqp suma
  `librabbitmq-dev` como dep de build. Versiones pineadas exactas, idénticas a antes
  (amqp 2.2.0, apcu 5.1.28, xdebug 3.5.3).
- `install-php-extensions` (mlocati 2.12.3) queda SOLO para lo que no pasa por pecl: `@composer`
  y las bundled de PHP (`intl`/`opcache`/`pdo_pgsql`/`zip`).
- **Punto de extensión del fork (`backend/php-extensions.txt`) sigue usando
  `install-php-extensions`.** Para extensiones bundled de PHP (bcmath, gmp, …) no hay problema.
  Si un fork agrega ahí una extensión PECL y el build flakea, migrar esa a `pie install` también.
- Verificado con build `--no-cache` del target `frankenphp_dev`: las 3 compilan vía PIE
  (0 menciones de pecl.php.net), cargan en runtime con las versiones correctas, amqp linkea
  `librabbitmq.so.4`, y el toolchain de build queda purgado.

## 1.1.2 — 2026-10-22

**Acción requerida en el fork**

Ninguna en el código (el `backend/Dockerfile` es de Oliva y baja con el sync). Solo
rebuildear: `docker compose build` (dev) o `./scripts/deploy.sh` (VPS). Esto
destraba los builds limpios desde cero, que estaban rotos por `install-php-extensions
... exit code 100`.

**Qué cambió**

- `backend/Dockerfile`: `install-php-extensions` pasa a pinearse fresco desde
  `mlocati/php-extension-installer:2.12.3` (en vez del que viene congelado en la imagen
  base). El viejo bajaba siempre la lista REST de metadata de `pecl.php.net` y rompía con
  `exit 100` ahora que ese endpoint está en phase-out (PECL deprecado, RFC
  `adopt_pie_deprecate_pecl`). El 2.12.x solo la consulta cuando hace falta.
- **Deuda viva — TODO(PIE):** esto es un band-aid; seguimos en PECL. La salida definitiva
  es migrar los `install-php-extensions` a `pie install vendor/pkg`. Bloqueado hoy porque
  PIE solo tiene publicado `xdebug`, no `amqp` ni `apcu`. Migrar el día que esos dos estén
  disponibles como paquetes PIE.

## 1.1.1 — 2026-10-21

**Acción requerida en el fork**

Ninguna. En el VPS, el primer `./scripts/deploy.sh` posterior ya limpia las imágenes viejas
sin tag que se hayan acumulado.

**Qué cambió**

- `scripts/lib/docker-prune.sh`: `deploy.sh`, `deploy-staging.sh` y `deps.sh update` borran al
  final las imágenes sin tag y la caché de build de más de 7 días (`OLIVA_NO_PRUNE=1` para saltear).

## 1.1.0 — 2026-10-21

**Acción requerida en el fork**

1. **Primer sync con las herramientas.** Este es el merge que trae `scripts/oliva/`. Si el
   fork todavía no las tiene, el merge se hace a mano una única vez:
   `git fetch oliva-upstream && git switch -c chore/oliva-sync-1.1.0 && git merge oliva-upstream/main`.
   De ahí en más: `scripts/oliva/sync.sh start`.
2. **Imágenes por proyecto.** Los compose ahora nombran las imágenes
   `${COMPOSE_PROJECT_NAME}-<servicio>:<dev|prod|staging>`. Si el fork agregó un servicio
   propio con `image:` (no de Docker Hub) o tocó algún `image:` en su override, pasarlo a la
   misma convención. Nunca un tag fijo: es global al host y otra app lo pisa.
3. **Red por proyecto.** `app_network` ya no tiene `name:` fijo (pasa a `<project>_app_network`).
   Si el fork tiene `name: app_network` en algún archivo propio, sacarlo.
4. **`frontend/yarn.lock` versionado.** El build ahora usa `--frozen-lockfile`. Después del
   merge: `scripts/oliva/sync.sh locks` (genera el lock contra el `package.json` del fork),
   verificar que `frontend/yarn.lock` ya no está en el `.gitignore` y commitearlo.
5. **Dev local:** `docker compose down && docker compose up -d --build`. Las imágenes
   `app-*-dev:1.0` y la red `app_network` quedan huérfanas: borrarlas cuando **ninguna** app
   las use (`docker image rm app-backend-dev:1.0 app-frontend-dev:1.0`, `docker network rm app_network`).
6. **VPS (en el próximo deploy, no antes):** `./scripts/deploy.sh` construye `<app>-backend:prod`
   y `<app>-frontend:prod` y recrea los containers. Volúmenes, red y alias no cambian (dependen
   de `-p`, que es el mismo). Después: `docker image rm app-backend-prod:1.0 app-frontend-prod:1.0
   app-backend-staging:1.0 app-frontend-staging:1.0` cuando ninguna app del VPS siga sin syncear.
7. **Extensiones PHP propias → `backend/php-extensions.txt`.** Si el fork había agregado
   extensiones en `backend/Dockerfile` (finanzas-ong: `bcmath`), ese archivo es de Oliva y en
   el merge **hay que sacarlas de ahí y listarlas en `backend/php-extensions.txt`** (una por
   línea), antes de tomar el Dockerfile de Oliva. Si no, la imagen se construye sin ellas.
8. **Chequeos de inicio de sesión.** Agregar al `CLAUDE.md` del fork, en "Chequeos de sanidad":
   `scripts/oliva/sync.sh check` y `scripts/oliva/deps.sh due`.

**Qué cambió**

- Nombres de imagen y red derivados del project name (fin de las colisiones entre apps).
- `scripts/lib/project-guard.sh`: `deploy*.sh`/`down*.sh` abortan si el project pertenece a
  otro checkout y rechazan nombres `*-staging`.
- `frontend/yarn.lock` versionado + `--frozen-lockfile`.
- `backend/php-extensions.txt`: extensiones PHP propias de la app sin tocar el Dockerfile.
- Extensiones PECL y composer fijados (`amqp-2.2.0`, `apcu-5.1.28`, `xdebug-3.5.3`, composer `2.10.3`).
- `frontend/Caddyfile`: `trusted_proxies static private_ranges` (backport de finanzas-ong `a42aced`):
  detrás del reverse-proxy compartido, el backend recibe la IP real del cliente.
- Sistema de actualización: `OLIVA_VERSION`, `docs/oliva/` (este archivo y `actualizaciones.md`),
  `scripts/oliva/{sync,deps,verify,release}.sh`, `scripts/oliva/owned-paths.txt`.
