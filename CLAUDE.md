# Oliva

Framework base para construir webapps: backend Symfony (FrankenPHP), frontend Vite, base de datos PostgreSQL (con pgvector), tiempo real vía Mercure, colas vía RabbitMQ + Symfony Messenger, y un contenedor scheduler (cron) para tareas programadas. Todo orquestado con Docker Compose.

Este `CLAUDE.md` es la guía operativa para agentes que trabajen sobre proyectos construidos con Oliva. La documentación humana (stack, getting started) está en `README.md`.

## Versiones, actualizaciones y forks

Oliva se versiona (`OLIVA_VERSION`, tags `vX.Y.Z`) y las apps hechas con Oliva viven en **repos separados** (finanzas-ong, crypto-pulse) con un remote `oliva-upstream` que apunta acá. El sistema completo está en **`docs/oliva/actualizaciones.md`**; en corto:

- **Mantener Oliva vivo** (acá): `scripts/oliva/deps.sh due` en cada inicio de sesión; cuando dice TOCA → `deps.sh report` (EOL, imágenes, composer, yarn, actions, CVEs) → `deps.sh update` (bump dentro de rangos + `verify.sh` + commit en `chore/deps-<fecha>`) → saltos de major/imágenes base a mano, uno por commit → notas en `docs/oliva/UPGRADING.md` → `scripts/oliva/release.sh X.Y.Z` → push de `main` + tag.
- **Bajarlo a cada fork** (en el fork): `scripts/oliva/sync.sh check` en cada inicio de sesión; si está atrás → `sync.sh start` → resolver → `sync.sh locks` → commit → `sync.sh verify` → merge local a `main`.
- **Propiedad de archivos:** `scripts/oliva/owned-paths.txt`. Un fork no edita los archivos de Oliva; si necesita otra cosa, se agrega a Oliva como opción y baja a todos.
- **Al cambiar algo que un fork tenga que acompañar** (renombre, variable nueva, paso manual), escribirlo en `docs/oliva/UPGRADING.md` en el mismo commit — es lo que `sync.sh` le muestra al fork. `release.sh` no publica sin esa sección.

**Por qué importa:** antes de 1.1.0 nada avisaba que un fork había quedado atrás, y un fork con mes y medio de divergencia costó 19 conflictos (`add/add` del esqueleto Symfony, que hoy ya tiene ancestro común en todos los forks).

## Comandos principales

### Desarrollo
```bash
docker compose up
```
El `docker-compose.override.yml` se aplica automáticamente: monta el código fuente con hot-reload, expone el backend en `:80` y el frontend en `:3000`.

### Producción
```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```
Usa imágenes compiladas (`<project>-backend:prod`, `<project>-frontend:prod`; ver "Nombres de imagen" abajo). El frontend queda expuesto en `:80`.

### Build de producción
```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml build
```

## Estructura
- `backend/` — Symfony con FrankenPHP (Doctrine ORM/Migrations, pgvector, Mercure, Messenger)
- `frontend/` — Vite (Node), incluye demo de Mercure en vivo (`src/js/live.js`, sección "Live" de `index.html`)
- `docs/concepts.md` — glosario técnico acumulativo (pgvector, RabbitMQ, AMQP, modelo de sync de forks, etc.)
- `docs/qa-y-staging.md` — qué garantías ofrece el framework (verify.sh, los 3 jobs de CI, stack de staging, seeding) y qué NO cubre. Es el doc humano de lo que acá está desperdigado en runbooks
- `docs/oliva/` — docs **del framework** que bajan a cada fork: `actualizaciones.md` (sistema de updates) y `UPGRADING.md` (notas por versión)
- `scripts/oliva/` — herramientas de mantenimiento y sync (`deps.sh`, `sync.sh`, `verify.sh`, `release.sh`, `owned-paths.txt`)
- `OLIVA_VERSION` — versión del framework sobre la que está el checkout
- `docs/examples/` — esqueletos de referencia (`*.php.example`) no registrados como código de la app
- `.env`, `.env.backend`, `.env.frontend` — variables por entorno
- `.env.prod` — variables de producción

## Servicios incluidos y cómo desactivarlos

Además de `database`, `backend` y `frontend`, `docker-compose.yml` define:

| Servicio | Para qué | Si la app no lo necesita |
|---|---|---|
| `rabbitmq` | Broker para Symfony Messenger (colas `ingest`/`enrich` de ejemplo, comentadas) | Quitar el bloque `rabbitmq` y las dependencias `depends_on: rabbitmq` de `backend`/`scheduler`/`worker` |
| `scheduler` | Ejecuta `supercronic` con `backend/scheduler/crontab` para tareas periódicas. **Opt-in:** vive tras el profile `cron`, no arranca por defecto (mismo criterio que `rabbitmq`/`queues`). El crontab base viene vacío. | Por defecto ya no corre. Una app que necesite cron activa el profile (`--profile cron` o listando `scheduler` en `up`) y llena `backend/scheduler/crontab`. Para eliminarlo del todo: quitar el bloque `scheduler` y `backend/scheduler/crontab` |
| `worker` (en `docker-compose.override.yml`, dev) | Corre `bin/console messenger:consume` | Quitar el bloque `worker` si no hay mensajes async |

La base de datos usa la imagen `pgvector/pgvector:pg${POSTGRES_VERSION}` — es un Postgres normal con la extensión `vector` compilada y una migración que la habilita (`CREATE EXTENSION IF NOT EXISTS vector`). No tiene costo si la app no usa tipos `vector`; no hace falta quitarla.

### Deuda conocida: `worker` no tiene definición de producción

`docker-compose.override.yml` (dev) define `worker` con `bin/console messenger:consume`, pero no hay equivalente en `docker-compose.prod.yml` ni en el `docker-compose.yml` base. Si una app usa RabbitMQ/Messenger en serio, antes de ir a producción hay que agregar un servicio `worker` (imagen `${COMPOSE_PROJECT_NAME}-backend:prod`, comando `messenger:consume`, sin exponer puertos). `scheduler` sí está cubierto en prod (usa `${COMPOSE_PROJECT_NAME}-backend:prod` / target `frankenphp_prod`, igual que `backend`).

Mercure (`/.well-known/mercure`) está siempre activo vía el hub de Caddy (`backend/frankenphp/Caddyfile`); la demo de canvas en vivo (`backend/public/live.php` + `frontend/src/js/live.js`) muestra que funciona out of the box.

### Aislamiento por app: todo cuelga del project name

Varias apps Oliva conviven en el mismo host (en dev, tu máquina; en prod, el VPS). Todo lo que Compose crea se deriva del **project name** (nombre del directorio, `-p <app>` o `COMPOSE_PROJECT_NAME`), y nada se nombra fijo:

| Recurso | Nombre | Ejemplo (`-p ong`) |
|---|---|---|
| Imágenes | `<project>-<servicio>:<entorno>` (`dev`/`prod`/`staging`) | `ong-backend:prod`, `ong-staging-frontend:staging` |
| Red privada | `<project>_app_network` | `ong_app_network` |
| Volúmenes | `<project>_<volumen>` | `ong_db_data` |
| Alias en `proxy_net` | `<project>-frontend` | `ong-frontend` |

**Regla para forks:** no introducir nombres globales (`image:` con tag fijo, `name:` en redes/volúmenes, `container_name:`). Un nombre fijo es global al daemon Docker y choca en silencio con la otra app: hasta Oliva 1.1 el tag `app-backend-dev:1.0` hacía que el build de finanzas-ong pisara la imagen de CMP (y viceversa), y la red `app_network` era la misma para las dos.

**Guard de colisión en los scripts** (`scripts/lib/project-guard.sh`, sourceado por `deploy*.sh`/`down*.sh`): antes de `down`/`up`, aborta si el project ya tiene containers levantados desde **otro** directorio (label `com.docker.compose.project.working_dir`, que Compose pone solo), y rechaza nombres de app que terminen en `-staging` (sufijo reservado). Lo que el guard **no** cubre: `infra/scripts/provision-postgres.sh` se sigue tipeando a mano y puede driftear del project name. Convención: `<app>_db`/`<app>_user` con el mismo `<app>` que el `-p`.

### Deuda conocida: environments de Bruno commiteados se ensucian solos al testear

La convención de API testing con Bruno (ver `README.md` de la collection `api/` de cada fork, heredada de este patrón) commitea `environments/{staging,prod}.bru` con valores de ejemplo (`project_id`, `member_id`, `batch_id`, montos de los requests). Bruno **escribe de vuelta al archivo en disco** cada vez que el usuario edita una variable desde la UI (el ícono del ojo) o cuando un script `post-response` hace `bru.setVar(...)`. Como esos `.bru` están trackeados en git, **cada sesión de testeo real dirty-ea archivos commiteados** con valores efímeros de esa sesión (ids de fixtures, montos de prueba) — encontrado al testear finanzas-ong (Marcos: `project_id: 1→29`, `member_id: 1→76`, montos `150.00→15000.00`).

Hoy la única mitigación es manual: `git checkout -- api/` después de cada sesión, antes de commitear cualquier otra cosa — funciona pero depende de acordarse.

**Fix sugerido (no implementado), evaluado con Marcos en finanzas-ong:** clonar los environments a una copia personal gitignoreada (`environments/staging.local.bru`, `environments/prod.local.bru`) y trabajar siempre sobre esa en Bruno — los archivos commiteados quedan de plantilla limpia para siempre, nunca los toca la UI. Mismo patrón que `.env.example` → `.env` (gitignoreado) ya usado para los secrets de prod en esta misma collection. Implementar en Oliva (`api/README.md` + `.gitignore` + generar los `.local.bru` iniciales a partir de los committeados) para que baje ya resuelto a cada fork, en vez de backportearlo desde un fork puntual.

## Infra compartida (opcional): `docker-compose.shared-infra.yml`

Overlay genérico, **opt-in**, para cuando varias apps Oliva comparten un mismo
VPS con Postgres/RabbitMQ/reverse-proxy en un repo de infra separado (no es
código de Oliva ni de ninguna app — es su propia capa de Infrastructure-as-Code,
ver convención en `claude-commands.md`/memoria del proyecto de infra).

Se apila encima de `docker-compose.prod.yml`, no lo reemplaza:

```bash
# Standalone (DB propia, de siempre):
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d

# Con infra compartida (project name ÚNICO con -p, sin DB/Rabbit locales):
docker compose -p ong \
  -f docker-compose.yml -f docker-compose.prod.yml \
  -f docker-compose.shared-infra.yml up -d
# (sin listar servicios: el profile inerte excluye database/rabbitmq y el
#  profile `cron` excluye scheduler. Si la app necesita cron, agregar
#  `--profile cron` y llenar backend/scheduler/crontab.)
```

Qué hace (requiere Docker Compose ≥ 2.24, por la tag de merge `!override`):
- Anula `depends_on: database` de `backend`/`scheduler` con `!override {}` —
  necesario porque los merges de Compose son aditivos: omitir una clave en el
  overlay no la borra, hay que reemplazarla explícitamente.
- Anula los `ports` de `frontend` (deja de exponer `:80` al host — en infra
  compartida el único que publica puertos es el reverse-proxy de infra).
- Desactiva `database`/`rabbitmq` locales con un profile inerte
  (`disabled-in-shared-infra`) para que un `up -d` sin listar servicios no los
  levante por accidente.
- **Topología de red (split, ver README de infra):** `frontend` → red privada
  de la app + `proxy_net` (alias único); `backend`/`scheduler` → red privada +
  `data_net`. El frontend no toca `data_net` (no llega a la DB). Las redes
  `proxy_net`/`data_net` son externas (las crea el repo de infra).

**Cada fork que use este overlay debe:** (1) **arrancar con `-p <appname>`
único** — eso hace su red privada `<appname>_app_network` y deriva el alias de
`frontend` en `proxy_net` (`${COMPOSE_PROJECT_NAME}-frontend`, ej.
`ong-frontend`), evitando que el DNS interno colisione con otra app (ver
[`infra` README, "Topología de red"]); (2) descomentar/setear `DATABASE_URL`
en `.env.backend` de prod apuntando al Postgres compartido (`postgres`), no a `database`.

> **Gotcha — colisión de alias en `proxy_net`:** `proxy_net` es externa y
> compartida entre TODOS los `-p` del VPS. Si dos apps (o prod/staging de la
> misma app) registraran el mismo alias fijo, el DNS interno de Docker hace
> round-robin entre ambas → el reverse-proxy rutearía tráfico de una al
> frontend de la otra. Por eso el alias se
> deriva de `${COMPOSE_PROJECT_NAME:-app}` en vez de hardcodearse: con `-p
> ong` da `ong-frontend`, con `-p ong-staging` da `ong-staging-frontend` —
> nunca colisionan.

Es reversible: si una app deja de usar infra compartida, simplemente no se pasa
ese `-f` al arrancar — `docker-compose.prod.yml` standalone sigue intacto.

### Runbook de deploy con infra compartida (pasos manuales por app)

Estos pasos se repiten en **cada** deploy de **cada** fork sobre infra
compartida. El código viene del `git pull`, pero estos NO (o requieren un valor
único por app):

> **Atajo para redeploys:** los pasos 1, 5 y 6 (pull + build + up) están
> envueltos en `scripts/deploy.sh`. Después del setup inicial (pasos 2-4, que
> se hacen una sola vez por app), cada redeploy es solo:
> `cd ~/<app> && ./scripts/deploy.sh` (toma el `app_name` del nombre del dir;
> hace `down` antes del `up` para no dejar containers stale). Si la app usa
> cron, editar el script o agregar `--profile cron`. Los pasos de abajo quedan
> como referencia de qué hace cada cosa.

1. **En el VPS, traer el código:** `cd ~/<app> && git pull` (trae el overlay y
   el `.env.backend` con el `DATABASE_URL` comentado).
2. **Crear el `.env`** (gitignored → NO viene en el pull): `cp .env.example .env`.
   En shared-infra casi todo el `.env` queda inerte (no hay `database` local) o
   lo pisa `.env.backend`; igual debe existir porque Compose lo interpola
   (`POSTGRES_VERSION`, etc.) y es el `env_file` base.
3. **Provisionar la base** en el Postgres compartido, desde `~/infra`:
   `./scripts/provision-postgres.sh <app>_db <app>_user` → imprime el
   `DATABASE_URL` con la password generada (guardarla en el gestor de claves).
   El script ya crea la extensión `vector` como superuser (ver nota pgvector
   abajo).
4. **Setear el `DATABASE_URL`** en `~/<app>/.env.backend`: **descomentar** la
   línea y pegar la URL provisionada (host `postgres`, `<app>_user`, `<app>_db`).
   Al cargarse después de `.env`, pisa el `DATABASE_URL` standalone.
5. **Build:** `docker compose -f docker-compose.yml -f docker-compose.prod.yml build`.
6. **Up** (project name `-p <app>` ÚNICO, los 3 overlays; sin listar servicios,
   el profile inerte ya excluye `database`/`rabbitmq`; el alias de `frontend`
   en `proxy_net` se deriva solo de `-p <app>`, no hace falta tocar nada):
   `docker compose -p <app> -f docker-compose.yml -f docker-compose.prod.yml -f docker-compose.shared-infra.yml up -d`.
7. **Migraciones:** automáticas. El entrypoint del backend las corre en cada
   boot (`doctrine:migrations:migrate`), junto con la generación de las claves
   JWT y el wait-for-db. Solo verificar que no quedaron pendientes:
   `docker exec <app>-backend-1 bin/console doctrine:migrations:status`.
8. **Claves JWT:** en el primer boot el entrypoint las genera en `./secrets/jwt`
   (bind-mount al host, gitignored) usando `JWT_PASSPHRASE`. **Backupear**
   `~/<app>/secrets/jwt/{private,public}.pem` + la `JWT_PASSPHRASE` al gestor de
   claves. De ahí en más persisten y NUNCA se regeneran (recrear el container no
   desloguea a nadie). Para restaurar en un host nuevo: poné los `.pem` ahí antes
   del `up`.
9. **Health:** `docker exec <app>-backend-1 curl -s http://localhost/health` → `{"status":"ok"}`.
10. **(Opt-in) Levantar el stack de staging:** staging es una app aparte en el VPS
    con su propia DB desechable. Ver **"Runbook de staging"** más abajo.
11. **(Cuando haya dominio)** vhost en `~/infra/caddy/Caddyfile` apuntando al
    alias `<app>-frontend` + `docker exec infra-reverse-proxy-1 caddy reload`.
12. **Smoke de flujos de negocio:** correr la collection Bruno de la app (`api/`,
    si existe) contra el entorno recién levantado — apuntar `{{base_url}}` al host
    correcto (público tras el paso 11, o `http://localhost` local) y verificar que
    login + los flujos de dominio responden OK. Simétrico al `fixtures:load` del
    runbook de staging: el health check confirma que el proceso arranca; la
    collection confirma que el dominio funciona end-to-end. Es opt-in y por app —
    Oliva no shipea la collection (los requests son 100% dominio, ver tabla de
    stack del README).

> **Gotcha pgvector / shared-infra:** en standalone la app conecta como el
> superuser del Postgres local, así que la migración que hace
> `CREATE EXTENSION vector` funciona. En shared-infra conecta como `<app>_user`
> (no-superuser) y esa migración falla con *"permission denied to create
> extension"*. Por eso `provision-postgres.sh` crea la extensión como superuser
> al provisionar; la migración la encuentra con su `IF NOT EXISTS` y hace no-op.

### Runbook de staging (pasos manuales, primera vez)

Staging es **una app más** en el VPS: misma infra compartida, pero DB propia
desechable y project name propio (`-p <app>-staging`). No interfiere con el
stack de producción.

> **Atajo para redeploys:** `./scripts/deploy-staging.sh` (ejecuta build + up
> + migraciones + `fixtures:load` en una sola llamada). Los pasos de abajo
> documentan el setup inicial (una sola vez) y la lógica de cada paso.

1. **Provisionar la DB de staging** en el Postgres compartido, desde `~/infra`:
   `./scripts/provision-postgres.sh <app>_staging_db <app>_staging_user`
   → imprime el `DATABASE_URL` con la password generada (guardarla en el
   gestor de claves). El script crea la extensión `vector` como superuser.
2. **Crear `.env.staging`** (gitignored → NO viene del pull):
   `cp .env.staging.example .env.staging`
   Setear `DATABASE_URL` con la URL impresa en el paso anterior
   (host `postgres`, `<app>_staging_user`, `<app>_staging_db`).
3. **Build + up** (project name `-p <app>-staging` propio; staging como app en
   shared-infra). `up -d --build` buildea automáticamente cualquier servicio
   con sección `build` (backend/scheduler con tag `<app>-staging-backend:staging`,
   target `frankenphp_staging`; frontend con tag `<app>-staging-frontend:staging`) —
   no se enumeran servicios a propósito, ver gotcha más abajo:
   ```bash
   docker compose -p <app>-staging \
     -f docker-compose.yml -f docker-compose.prod.yml \
     -f docker-compose.shared-infra.yml -f docker-compose.staging.yml \
     up -d --build
   ```
   Env files que se cargan: `.env` → `.env.backend` → `.env.staging`
   (`.env.staging` carga último y pisa `DATABASE_URL`). `APP_ENV=staging` lo
   fija `docker-compose.staging.yml` vía `environment:` (no vía env_file —
   ver gotcha de precedencia abajo).
5. **Migraciones:** automáticas en el entrypoint. Verificar:
   `docker exec <app>-staging-backend-1 bin/console doctrine:migrations:status`
6. **Seeding:** la imagen `frankenphp_staging` sí tiene `doctrine:fixtures:load`
   (a diferencia de prod). La DB de staging es desechable — la purga es inocua:
   ```bash
   docker exec <app>-staging-backend-1 \
     bin/console doctrine:fixtures:load --group=staging --no-interaction
   ```
7. **Health:** `docker exec <app>-staging-backend-1 curl -s http://localhost/health`

Para reiniciar con datos frescos: `SKIP_PULL=1 ./scripts/deploy-staging.sh`.
Para bajar staging (preserva el volumen de la DB desechable): `./scripts/down-staging.sh`
(o `./scripts/down-staging.sh <app>`; análogo a `down.sh` pero con los 4 overlays
y project name `<app>-staging`). Para purgar también el volumen, bajar a mano
con `-v` agregado al comando de los 4 overlays.

> **env_file de staging:** `docker-compose.staging.yml` usa `env_file: !override`
> (Compose >= 2.24, mismo requisito que shared-infra) para REEMPLAZAR (no concatenar)
> la lista del base. Sin `!override`, Compose concatena listas → `.env`/`.env.backend`
> aparecerían duplicados. Con él, la lista queda `[.env, .env.backend, .env.staging]`
> y `.env.staging` carga último, pisando `DATABASE_URL`.

> **Gotcha — precedencia de `APP_ENV` (la saga que costó 3 capas):** en Compose,
> `environment:` > `env_file:` > `ENV` horneado en la imagen. `prod.yml`
> hardcodea `environment: APP_ENV=prod` en backend/scheduler — sin un
> override explícito en `staging.yml`, ese `environment:` pisaba
> `.env.staging` (env_file) Y el `ENV` del Dockerfile, pese a apilarse encima.
> Síntoma real: `fixtures:load` fallaba con "command not defined" porque
> `prod` no está en `bundles.php`. Por eso `docker-compose.staging.yml`
> fija `environment: [APP_ENV=staging]` explícito en backend/scheduler, y el
> stage `frankenphp_staging` del Dockerfile borra el `.env.local.php` heredado
> de prod (otra capa que pisaba el entorno). Regla general para diagnosticar
> cualquier env var que no toma el valor esperado: primero
> `docker exec <c> printenv VAR` + `docker compose ... config` (de qué capa
> sale), recién después editar.

## Variables de entorno

Ver `.env.example` como referencia. Agrupadas por servicio:
- **DB — standalone (en `.env`)**: `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`, `POSTGRES_VERSION` y `DATABASE_URL` (la lee Doctrine). Las credenciales de `DATABASE_URL` deben coincidir con los `POSTGRES_*` — es el mismo Postgres local.
- **DB — infra compartida (override en `.env.backend`)**: `DATABASE_URL` viene comentado por default; se descomenta/setea solo en deploys con infra compartida (apunta al `postgres` compartido) y pisa al de `.env`.
- **Mercure**: `MERCURE_URL`, `MERCURE_PUBLIC_URL`, `MERCURE_PUBLISHER_JWT_KEY`, `MERCURE_JWT_SECRET`, `CADDY_MERCURE_URL`, `CADDY_MERCURE_PUBLIC_URL`
- **RabbitMQ**: `RABBITMQ_USER`, `RABBITMQ_PASSWORD`, `RABBITMQ_DSN`
- **JWT**: `JWT_PASSPHRASE`

## Health check y CI

- `GET /health` → `{"status": "ok"}` (`backend/src/Controller/HealthController.php`).
- `.github/workflows/ci.yml`: build de imágenes, levanta los servicios, chequea `/health` y `/.well-known/mercure`, corre migraciones, valida el schema de Doctrine y corre PHPUnit. Job adicional de lint de Dockerfile con hadolint.

## Protocolo de explicaciones conceptuales

Cuando el usuario pide que se le explique un concepto (`"explicame X"`, `"enseñame X"`), el agente debe:
1. Agregar la explicación al **final** de `docs/concepts.md` como una nueva sección `## NombreDelConcepto`.
2. Commitear `docs/concepts.md` junto con el trabajo en curso (o en un commit separado si el usuario lo pide).
3. No repetir explicaciones ya presentes en el archivo — si el concepto ya está, referenciarlo.

`docs/concepts.md` es acumulativo: nunca se borra contenido, solo se agrega.

## Protocolo de commits del agente

Para proyectos multi-sesión o de trabajo autónomo, `agent-commits.md` en la raíz del proyecto registra cambios del agente con formato detallado. **No se anota cada commit**: cuando el agente haga un cambio que le parezca interesante (una decisión de diseño, un fix con *por qué* no obvio, algo que afecte cómo se opera el proyecto), **le pregunta a Marcos si lo registra** — Marcos decide. Lo rutinario no se anota ni se pregunta.

### Formato

```markdown
## [PASO X.Y] <título del commit>
**Hash:** `<hash completo>`
**Rama:** `<rama>`
**Fecha:** <fecha>

### Cambios
| Archivo | Tipo | Descripción |
|---|---|---|
| path/archivo | nuevo/modificado/eliminado | qué hace |

### Justificación
<por qué se tomaron estas decisiones, qué problema resuelven, qué alternativas se descartaron>
```

### Reglas
- Registrar **todos** los archivos modificados, no solo los principales.
- La justificación debe responder **por qué**, no solo describir el qué (eso ya lo hace la tabla).
- Si un cambio resuelve un problema encontrado durante la ejecución (no previsto en el plan), documentarlo explícitamente.
- El commit de git y la entrada en `agent-commits.md` van en el **mismo commit**.

## Comandos del agente

Ver `claude-commands.md` en la raíz del proyecto para los comandos que el usuario puede invocar en el chat (protocolos de reinicio de sesión, etc.).

## Chequeos de sanidad (inicio y cierre de sesión)

Correr al **inicio** de cada sesión antes de tocar código:

```bash
git branch --show-current          # confirmar la rama de trabajo esperada
git status -s                      # debe estar limpio (o saber qué hay pendiente)
git log --oneline -3               # orientarse en dónde quedó la sesión anterior
docker compose ps                  # todos los servicios healthy
docker compose exec backend bin/console doctrine:migrations:status  # sin migraciones pendientes
scripts/oliva/deps.sh due          # ¿toca ciclo de deps (~45d)? ¿toca audit de seguridad (~7d)?
```

`deps.sh due` reporta DOS cadencias: el ciclo de deps (frescura, ~45 días → `report`/`update`)
y el audit de CVEs (seguridad, ~7 días → `scripts/oliva/deps.sh audit`, que corre composer +
yarn audit + Trivy sobre las imágenes base). Si el audit avisa que TOCA, correr `deps.sh audit`
— un CVE no espera al ciclo de 45 días. Ver `docs/oliva/actualizaciones.md` ("El aviso por advisory").

En un **fork** se agrega además `scripts/oliva/sync.sh check` (¿Oliva avanzó?). Si alguno de los tres avisa, mencionárselo a Marcos al arrancar — no ejecutar el ciclo ni el audit sin que lo pida.

Verificar al **cierre** de sesión antes de cortar:

```bash
git status -s                      # sin archivos sin commitear (salvo intencional)
git log --oneline -3               # último commit con mensaje claro
```

Si el proyecto usa `agent-commits.md`, verificar si el último commit merece una entrada (si es un cambio interesante, agregar; si es rutinario, omitir).
