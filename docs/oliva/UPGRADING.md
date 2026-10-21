# UPGRADING — notas para forks

Una sección por versión de Oliva, la más nueva arriba. `scripts/oliva/sync.sh` muestra
al fork las secciones más nuevas que su `OLIVA_VERSION`. Formato fijo (lo parsea el script):
encabezado `## X.Y.Z — fecha`, después **Acción requerida en el fork** (pasos concretos,
o "ninguna") y **Qué cambió** (resumen; el detalle está en `git log`).

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
