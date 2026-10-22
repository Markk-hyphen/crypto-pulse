# UPGRADING — notas para forks

Una sección por versión de Oliva, la más nueva arriba. `scripts/oliva/sync.sh` muestra
al fork las secciones más nuevas que su `OLIVA_VERSION`. Formato fijo (lo parsea el script):
encabezado `## X.Y.Z — fecha`, después **Acción requerida en el fork** (pasos concretos,
o "ninguna") y **Qué cambió** (resumen; el detalle está en `git log`).

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
