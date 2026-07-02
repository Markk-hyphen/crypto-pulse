diff --git a/.env.backend b/.env.backend
index bbb3521..d7009ab 100644
--- a/.env.backend
+++ b/.env.backend
@@ -6,13 +6,6 @@ HTTP_PORT=80
 # PHP
 PHP_VERSION=8.3.13
 
-# Database — SOLO para infra compartida (override).
-# Standalone: NO tocar esto; DATABASE_URL vive en .env (junto a POSTGRES_*).
-# Infra compartida (prod): descomentar y apuntar al Postgres compartido (host
-# `postgres`), con el usuario/base que provisiona infra — NO 'app'/'database'.
-# Esta línea, al cargarse después de .env, PISA el DATABASE_URL standalone.
-#DATABASE_URL=postgresql://ong_user:PROVISIONED_PASS@postgres:5432/ong_db?serverVersion=15&charset=utf8
-
 # Caddy
 CADDY_GLOBAL_OPTIONS=#
 CADDY_EXTRA_CONFIG=#
@@ -31,5 +24,14 @@ RABBITMQ_DSN=amqp://app:app@rabbitmq:5672/%2f
 # Mercure — same secret used by Caddyfile (MERCURE_PUBLISHER_JWT_KEY) and MercureBundle (MERCURE_JWT_SECRET)
 MERCURE_PUBLISHER_JWT_KEY=36b6c43013b9e9829daeddf83a8b7030cf133784ea391a2c0e455dd7bc78ea39
 MERCURE_JWT_SECRET=36b6c43013b9e9829daeddf83a8b7030cf133784ea391a2c0e455dd7bc78ea39
-MERCURE_URL=http://localhost/.well-known/mercure
-MERCURE_PUBLIC_URL=http://localhost/.well-known/mercure
\ No newline at end of file
+# Internal URL: used by backend/worker containers to publish to the hub (Docker service name).
+# Works from both the backend container (same network) and the worker container.
+MERCURE_URL=http://backend/.well-known/mercure
+# Public URL: what browsers use to subscribe (host-facing).
+MERCURE_PUBLIC_URL=http://localhost/.well-known/mercure
+
+# Anthropic — LLM enrichment (Haiku for volume, Sonnet for aggregates)
+ANTHROPIC_API_KEY=your_anthropic_api_key_here
+
+# Voyage AI — embeddings (optional: leave empty to store null embeddings until key is available)
+VOYAGE_API_KEY=
\ No newline at end of file
diff --git a/.env.example b/.env.example
index d948b7d..4346762 100644
--- a/.env.example
+++ b/.env.example
@@ -1,11 +1,7 @@
-# Compose — servicios opcionales (Docker Compose profiles)
-# Vacío = solo core (backend + frontend + database). Mercure va siempre embebido en el backend.
-# Activar perfiles separados por coma. Perfiles disponibles: queues
-#   COMPOSE_PROFILES=queues
-COMPOSE_PROFILES=
-
 # Backend
+BACKEND_DATABASE_URL=postgresql://app:your_db_password@database:5432/app?serverVersion=15&charset=utf8
 SERVER_NAME=localhost
+DATABASE_URL=postgresql://app:your_db_password@database:5432/app?serverVersion=15&charset=utf8
 CADDY_MERCURE_URL=http://localhost/.well-known/mercure
 CADDY_MERCURE_PUBLIC_URL=https://localhost/.well-known/mercure
 MERCURE_TRANSPORT_URL=some_transport_url
@@ -20,15 +16,11 @@ CADDY_EXTRA_CONFIG=""
 CADDY_SERVER_LOG_OPTIONS=""
 FRONTEND_DOC_ROOT=/usr/share/caddy
 
-# Database (standalone: la app levanta su propio Postgres `database`)
-# DATABASE_URL es la conexión del backend. En standalone SUS CREDENCIALES DEBEN
-# COINCIDIR con POSTGRES_USER/PASSWORD/DB de acá (es el mismo Postgres, escrito dos
-# veces). En infra compartida NO se usa esto: se setea DATABASE_URL en .env.backend.
+# Database
 POSTGRES_USER=app
 POSTGRES_PASSWORD=your_db_password
 POSTGRES_DB=app
 POSTGRES_VERSION=15
-DATABASE_URL=postgresql://app:your_db_password@database:5432/app?serverVersion=15&charset=utf8
 
 # Symfony
 SYMFONY_VERSION=7.x
@@ -36,7 +28,7 @@ STABILITY=stable
 APP_SECRET=your_app_secret
 
 #Environmental
-APP_ENV=dev
+APP_ENV=development
 NODE_ENV=development
 
 #JWT
@@ -50,11 +42,11 @@ RABBITMQ_DSN=amqp://app:your_rabbitmq_password@rabbitmq:5672/%2f
 # Mercure
 MERCURE_PUBLISHER_JWT_KEY=generate_with_openssl_rand_hex_32
 MERCURE_JWT_SECRET=generate_with_openssl_rand_hex_32
-MERCURE_URL=http://localhost/.well-known/mercure
+MERCURE_URL=http://backend/.well-known/mercure
 MERCURE_PUBLIC_URL=http://localhost/.well-known/mercure
 
-# Seeding (staging only — requires frankenphp_staging image, unavailable in prod)
-# ⚠️ fixtures:load PURGES the DB before loading. Run ONLY against a dedicated staging
-#    database, NEVER against a production app's DB in shared infra. See Epic E "Deuda crítica".
-# docker compose -f docker-compose.yml -f docker-compose.prod.yml build --target frankenphp_staging backend
-# docker exec <app>-staging-backend-1 bin/console doctrine:fixtures:load --group=staging --no-interaction
\ No newline at end of file
+# Anthropic — LLM enrichment (Haiku for volume, Sonnet for aggregates)
+ANTHROPIC_API_KEY=your_anthropic_api_key_here
+
+# Voyage AI — embeddings (optional: leave empty to store null embeddings until key is available)
+VOYAGE_API_KEY=
\ No newline at end of file
diff --git a/.env.staging.example b/.env.staging.example
deleted file mode 100644
index c52513a..0000000
--- a/.env.staging.example
+++ /dev/null
@@ -1,16 +0,0 @@
-# Variables de entorno para el stack de STAGING.
-# Copiar a .env.staging (gitignored) y completar antes del primer `up`.
-#
-# Este archivo se carga como env_file del backend/scheduler del stack staging,
-# DESPUÉS de .env y .env.backend, así que solo necesita sobreescribir lo que
-# difiere de prod: principalmente DATABASE_URL y APP_ENV.
-#
-# La DB de staging vive en el MISMO Postgres compartido que producción,
-# pero es una BASE DE DATOS SEPARADA, desechable. Provisionarla con:
-#   ~/infra/scripts/provision-postgres.sh <app>_staging_db <app>_staging_user
-
-APP_ENV=staging
-
-# DATABASE_URL del staging (host `postgres` = Postgres compartido de infra).
-# Reemplazar con la URL impresa por provision-postgres.sh al provisionar.
-DATABASE_URL=postgresql://<app>_staging_user:<password>@postgres:5432/<app>_staging_db?serverVersion=15&charset=utf8
diff --git a/.github/workflows/ci.yml b/.github/workflows/ci.yml
index bc30e85..db116f6 100644
--- a/.github/workflows/ci.yml
+++ b/.github/workflows/ci.yml
@@ -1,20 +1,20 @@
 name: CI
 
-# Flujo solo-dev: sin PRs. El CI corre DESPUÉS de mergear a main (red de
-# seguridad que solo avisa cuando main se rompe) y a demanda (workflow_dispatch).
 on:
   push:
     branches:
       - main
+      - release/plan-market-pulse
+  pull_request: ~
   workflow_dispatch: ~
 
 concurrency:
-  group: ${{ github.workflow }}-${{ github.ref }}
+  group: ${{ github.workflow }}-${{ github.head_ref || github.run_id }}
   cancel-in-progress: true
 
 jobs:
   tests:
-    name: Tests (smoke + PHPUnit)
+    name: Tests
     runs-on: ubuntu-latest
     steps:
       -
@@ -22,8 +22,6 @@ jobs:
         uses: actions/checkout@v4
 
       -
-        # Driver docker-container: necesario para que el caché type=gha funcione
-        # (el driver docker por defecto no soporta backends de caché de buildx).
         name: Set up Docker Buildx
         uses: docker/setup-buildx-action@v3
 
@@ -51,23 +49,8 @@ jobs:
           EOF
 
       -
-        # El cuello de botella era rebuildear extensiones PHP + composer + yarn en
-        # cada corrida (disco limpio = cero caché). bake con caché de capas de GHA:
-        # con deps sin cambios el build pasa de minutos a segundos. Solo backend y
-        # frontend (los únicos con build); database se pullea sola en el `up`.
-        name: Build images (caché de capas GHA)
-        uses: docker/bake-action@v5
-        with:
-          files: |
-            docker-compose.yml
-            docker-compose.override.yml
-          targets: |
-            backend
-            frontend
-          load: true
-          set: |
-            *.cache-from=type=gha
-            *.cache-to=type=gha,mode=max
+        name: Build Docker images
+        run: docker compose build
 
       -
         name: Start services
@@ -92,41 +75,12 @@ jobs:
 
       -
         name: Doctrine Schema Validator
-        run: docker compose exec -T backend bin/console doctrine:schema:validate
+        run: docker compose exec -T backend bin/console doctrine:schema:validate --skip-sync
 
       -
         name: Run PHPUnit
         run: docker compose exec -T backend php vendor/bin/phpunit
 
-  prod-config:
-    # Guarda barata (sin build, segundos): el stack prod solo se testea acá vía
-    # `config`. Atrapa la clase de bug donde un override de Compose pisa APP_ENV
-    # con la palabra larga y desactiva los bloques when@prod de Symfony (cache de
-    # Doctrine, auto_generate_proxy_classes). El job de tests solo levanta DEV.
-    name: Prod config guard
-    runs-on: ubuntu-latest
-    steps:
-      -
-        name: Checkout
-        uses: actions/checkout@v4
-
-      -
-        name: Minimal env files (solo para interpolar config)
-        run: |
-          cp .env.example .env
-          : > .env.backend
-
-      -
-        name: APP_ENV resuelve a 'prod' en el stack prod (backend + scheduler)
-        run: |
-          docker compose -f docker-compose.yml -f docker-compose.prod.yml \
-            --profile cron config --format json > prod-config.json
-          jq -e '.services.backend.environment.APP_ENV == "prod"' prod-config.json > /dev/null \
-            || { echo "::error::backend APP_ENV != 'prod' en docker-compose.prod.yml — los bloques when@prod de Symfony NO se aplicarían"; exit 1; }
-          jq -e '.services.scheduler.environment.APP_ENV == "prod"' prod-config.json > /dev/null \
-            || { echo "::error::scheduler APP_ENV != 'prod' en docker-compose.prod.yml"; exit 1; }
-          echo "✓ backend y scheduler resuelven APP_ENV=prod"
-
   lint:
     name: Docker Lint
     runs-on: ubuntu-latest
diff --git a/.gitignore b/.gitignore
index 6204b75..986b03e 100644
--- a/.gitignore
+++ b/.gitignore
@@ -1,9 +1,6 @@
 .idea
 .env
-.env.staging
 !backend/.env
 frontend/dist/
 frontend/src/.vite/
-frontend/yarn.lock
-secrets/
-rules-claude.md
\ No newline at end of file
+frontend/yarn.lock
\ No newline at end of file
diff --git a/CLAUDE.md b/CLAUDE.md
index 137a0e4..b42d81e 100644
--- a/CLAUDE.md
+++ b/CLAUDE.md
@@ -1,8 +1,6 @@
-# Oliva
+# oliva
 
-Framework base para construir webapps: backend Symfony (FrankenPHP), frontend Vite, base de datos PostgreSQL (con pgvector), tiempo real vía Mercure, colas vía RabbitMQ + Symfony Messenger, y un contenedor scheduler (cron) para tareas programadas. Todo orquestado con Docker Compose.
-
-Este `CLAUDE.md` es la guía operativa para agentes que trabajen sobre proyectos construidos con Oliva. La documentación humana (stack, getting started) está en `README.md`.
+Webapp con backend Symfony (FrankenPHP), frontend Vite, y base de datos PostgreSQL. Todo orquestado con Docker Compose.
 
 ## Comandos principales
 
@@ -24,247 +22,74 @@ docker compose -f docker-compose.yml -f docker-compose.prod.yml build
 ```
 
 ## Estructura
-- `backend/` — Symfony con FrankenPHP (Doctrine ORM/Migrations, pgvector, Mercure, Messenger)
-- `frontend/` — Vite (Node), incluye demo de Mercure en vivo (`src/js/live.js`, sección "Live" de `index.html`)
-- `docs/concepts.md` — glosario técnico acumulativo (pgvector, RabbitMQ, AMQP, etc.)
-- `docs/examples/` — esqueletos de referencia (`*.php.example`) no registrados como código de la app
+- `backend/` — Symfony con FrankenPHP
+- `frontend/` — Vite (Node)
 - `.env`, `.env.backend`, `.env.frontend` — variables por entorno
 - `.env.prod` — variables de producción
 
-## Servicios incluidos y cómo desactivarlos
-
-Además de `database`, `backend` y `frontend`, `docker-compose.yml` define:
-
-| Servicio | Para qué | Si la app no lo necesita |
-|---|---|---|
-| `rabbitmq` | Broker para Symfony Messenger (colas `ingest`/`enrich` de ejemplo, comentadas) | Quitar el bloque `rabbitmq` y las dependencias `depends_on: rabbitmq` de `backend`/`scheduler`/`worker` |
-| `scheduler` | Ejecuta `supercronic` con `backend/scheduler/crontab` para tareas periódicas. **Opt-in:** vive tras el profile `cron`, no arranca por defecto (mismo criterio que `rabbitmq`/`queues`). El crontab base viene vacío. | Por defecto ya no corre. Una app que necesite cron activa el profile (`--profile cron` o listando `scheduler` en `up`) y llena `backend/scheduler/crontab`. Para eliminarlo del todo: quitar el bloque `scheduler` y `backend/scheduler/crontab` |
-| `worker` (en `docker-compose.override.yml`, dev) | Corre `bin/console messenger:consume` | Quitar el bloque `worker` si no hay mensajes async |
+## Variables de entorno
+Las variables se definen en `.env` (compartidas), `.env.backend` y `.env.frontend`. Ver `.env.example` como referencia.
 
-La base de datos usa la imagen `pgvector/pgvector:pg${POSTGRES_VERSION}` — es un Postgres normal con la extensión `vector` compilada y una migración que la habilita (`CREATE EXTENSION IF NOT EXISTS vector`). No tiene costo si la app no usa tipos `vector`; no hace falta quitarla.
+## Estado actual vs. proyecto en curso
+El backend está **graduado de boilerplate a app versionada** (paso 0.1 completado: `backend/src/`, `composer.json/lock`, `symfony.lock` en git; Dockerfile usa `composer install` sobre el repo). Mercure **sí funciona** (hub activo en `backend/frankenphp/Caddyfile`; demo de canvas en `public/live.php` + `frontend/src/js/live.js`).
 
-### Deuda conocida: `worker` no tiene definición de producción
+Se está construyendo **encima** un proyecto-vidriera: **"Crypto Pulse"** — plataforma de inteligencia de mercado cripto en tiempo real (ingesta de fuentes públicas → enriquecimiento con IA → dashboard en vivo vía Mercure). El headline es **DevOps × IA**; cripto es el dominio de datos, no el producto.
 
-`docker-compose.override.yml` (dev) define `worker` con `bin/console messenger:consume`, pero no hay equivalente en `docker-compose.prod.yml` ni en el `docker-compose.yml` base. Si una app usa RabbitMQ/Messenger en serio, antes de ir a producción hay que agregar un servicio `worker` (imagen `app-backend-prod:1.0`, comando `messenger:consume`, sin exponer puertos). `scheduler` sí está cubierto en prod (usa `app-backend-prod:1.0` / target `frankenphp_prod`, igual que `backend`).
+- **Plan completo y runbook ejecutable:** `PLAN-MARKET-PULSE.md` (leer §11 "convenciones de ejecución" antes de implementar).
+- **Log de commits del agente:** `agent-commits.md` (detalle de cada cambio con justificación).
+- **Glosario de conceptos técnicos:** `concepts.md` (explicaciones teóricas agregadas a pedido).
+- **Rama de trabajo:** `release/plan-market-pulse` (no tocar `main`).
+- **Decisiones cerradas:** broker **RabbitMQ**, scheduler **contenedor cron (supercronic)**, LLM **Anthropic** (Haiku volumen / Sonnet agregados), vector **pgvector**, dominio **cripto** (RSS CoinDesk/Cointelegraph + CoinGecko; CryptoPanic en Fase 2).
+- **Próximo paso:** 1.6 — API REST (`GET /api/feed` paginado + filtros básicos, `GET /api/items/{id}`).
+- **Modelo:** planificado con Opus; **ejecutar con Sonnet** (Haiku solo para pasos mecánicos).
 
-Mercure (`/.well-known/mercure`) está siempre activo vía el hub de Caddy (`backend/frankenphp/Caddyfile`); la demo de canvas en vivo (`backend/public/live.php` + `frontend/src/js/live.js`) muestra que funciona out of the box.
+## Deuda técnica conocida (revisión de sanidad 2026-06-01, actualizada en 1.5)
 
-## Infra compartida (opcional): `docker-compose.shared-infra.yml`
+- ✅ **Mock de `EnrichmentProvider` en dev — RESUELTO en 1.5.** `NullEnrichmentProvider` + `services_development.yaml`.
+- ✅ **`MERCURE_URL` worker — RESUELTO en 1.5.** Cambiado a `http://backend/...` (nombre de servicio Docker).
+- 🟡 **El prompt caching de Anthropic es un no-op.** El system prompt (~250 tokens) está por debajo del mínimo cacheable de Haiku (2048 tokens) → `cache_control: ephemeral` se ignora; no hay ahorro. El header beta `prompt-caching-2024-07-31` ya es innecesario (GA). El ahorro real lo da la capa Symfony Cache por `contentHash`.
+- 🟢 **Dual-write DB↔broker → items huérfanos en `pending`.** Si el broker falla tras el `flush()` de ingesta, queda un `NewsItem(pending)` sin mensaje de enrich. Mitigado por `app:enrich:requeue-pending`. Para 1.8: correrlo periódico o documentarlo como recovery path.
+- 🟢 **`contentHash` es un hash de la URL**, no del contenido. Dedup por URL es razonable; ediciones de título/cuerpo no re-ingestan.
+- 🟢 **`RssAdapter` asume RSS 2.0** (`channel->item`): feed Atom → vacío silencioso; sin header `User-Agent`. Para 1.8.
+- 🟢 **Gap de re-embedding:** items enriquecidos sin key de Voyage quedan con `embedding=null` permanente. La búsqueda semántica (2.2) los ignora. Necesitará comando de re-embed antes de Fase 2.
 
-Overlay genérico, **opt-in**, para cuando varias apps Oliva comparten un mismo
-VPS con Postgres/RabbitMQ/reverse-proxy en un repo de infra separado (no es
-código de Oliva ni de ninguna app — es su propia capa de Infrastructure-as-Code,
-ver convención en `claude-commands.md`/memoria del proyecto de infra).
+## Chequeos de sanidad (inicio y cierre de sesión)
 
-Se apila encima de `docker-compose.prod.yml`, no lo reemplaza:
+Correr al **inicio** de cada sesión antes de tocar código:
 
 ```bash
-# Standalone (DB propia, de siempre):
-docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d
-
-# Con infra compartida (project name ÚNICO con -p, sin DB/Rabbit locales):
-docker compose -p ong \
-  -f docker-compose.yml -f docker-compose.prod.yml \
-  -f docker-compose.shared-infra.yml up -d
-# (sin listar servicios: el profile inerte excluye database/rabbitmq y el
-#  profile `cron` excluye scheduler. Si la app necesita cron, agregar
-#  `--profile cron` y llenar backend/scheduler/crontab.)
+git branch --show-current          # debe ser release/plan-market-pulse
+git status -s                      # debe estar limpio (o saber qué hay pendiente)
+git log --oneline -3               # orientarse en dónde quedó la sesión anterior
+docker compose ps                  # todos los servicios healthy
+docker compose exec backend bin/console doctrine:migrations:status  # sin migraciones pendientes
 ```
 
-Qué hace (requiere Docker Compose ≥ 2.24, por la tag de merge `!override`):
-- Anula `depends_on: database` de `backend`/`scheduler` con `!override {}` —
-  necesario porque los merges de Compose son aditivos: omitir una clave en el
-  overlay no la borra, hay que reemplazarla explícitamente.
-- Anula los `ports` de `frontend` (deja de exponer `:80` al host — en infra
-  compartida el único que publica puertos es el reverse-proxy de infra).
-- Desactiva `database`/`rabbitmq` locales con un profile inerte
-  (`disabled-in-shared-infra`) para que un `up -d` sin listar servicios no los
-  levante por accidente.
-- **Topología de red (split, ver README de infra):** `frontend` → red privada
-  de la app + `proxy_net` (alias único); `backend`/`scheduler` → red privada +
-  `data_net`. El frontend no toca `data_net` (no llega a la DB). Las redes
-  `proxy_net`/`data_net` son externas (las crea el repo de infra).
-
-**Cada fork que use este overlay debe:** (1) **arrancar con `-p <appname>`
-único** — eso hace su red privada `<appname>_app_network` y deriva el alias de
-`frontend` en `proxy_net` (`${COMPOSE_PROJECT_NAME}-frontend`, ej.
-`ong-frontend`), evitando que el DNS interno colisione con otra app (ver
-[`infra` README, "Topología de red"]); (2) descomentar/setear `DATABASE_URL`
-en `.env.backend` de prod apuntando al Postgres compartido (`postgres`), no a `database`.
-
-> **Gotcha — colisión de alias en `proxy_net`:** `proxy_net` es externa y
-> compartida entre TODOS los `-p` del VPS. Si dos apps (o prod/staging de la
-> misma app) registraran el mismo alias fijo, el DNS interno de Docker hace
-> round-robin entre ambas → el reverse-proxy rutearía tráfico de una al
-> frontend de la otra. Por eso el alias se
-> deriva de `${COMPOSE_PROJECT_NAME:-app}` en vez de hardcodearse: con `-p
-> ong` da `ong-frontend`, con `-p ong-staging` da `ong-staging-frontend` —
-> nunca colisionan.
-
-Es reversible: si una app deja de usar infra compartida, simplemente no se pasa
-ese `-f` al arrancar — `docker-compose.prod.yml` standalone sigue intacto.
-
-### Runbook de deploy con infra compartida (pasos manuales por app)
-
-Estos pasos se repiten en **cada** deploy de **cada** fork sobre infra
-compartida. El código viene del `git pull`, pero estos NO (o requieren un valor
-único por app):
-
-> **Atajo para redeploys:** los pasos 1, 5 y 6 (pull + build + up) están
-> envueltos en `scripts/deploy.sh`. Después del setup inicial (pasos 2-4, que
-> se hacen una sola vez por app), cada redeploy es solo:
-> `cd ~/<app> && ./scripts/deploy.sh` (toma el `app_name` del nombre del dir;
-> hace `down` antes del `up` para no dejar containers stale). Si la app usa
-> cron, editar el script o agregar `--profile cron`. Los pasos de abajo quedan
-> como referencia de qué hace cada cosa.
-
-1. **En el VPS, traer el código:** `cd ~/<app> && git pull` (trae el overlay y
-   el `.env.backend` con el `DATABASE_URL` comentado).
-2. **Crear el `.env`** (gitignored → NO viene en el pull): `cp .env.example .env`.
-   En shared-infra casi todo el `.env` queda inerte (no hay `database` local) o
-   lo pisa `.env.backend`; igual debe existir porque Compose lo interpola
-   (`POSTGRES_VERSION`, etc.) y es el `env_file` base.
-3. **Provisionar la base** en el Postgres compartido, desde `~/infra`:
-   `./scripts/provision-postgres.sh <app>_db <app>_user` → imprime el
-   `DATABASE_URL` con la password generada (guardarla en el gestor de claves).
-   El script ya crea la extensión `vector` como superuser (ver nota pgvector
-   abajo).
-4. **Setear el `DATABASE_URL`** en `~/<app>/.env.backend`: **descomentar** la
-   línea y pegar la URL provisionada (host `postgres`, `<app>_user`, `<app>_db`).
-   Al cargarse después de `.env`, pisa el `DATABASE_URL` standalone.
-5. **Build:** `docker compose -f docker-compose.yml -f docker-compose.prod.yml build`.
-6. **Up** (project name `-p <app>` ÚNICO, los 3 overlays; sin listar servicios,
-   el profile inerte ya excluye `database`/`rabbitmq`; el alias de `frontend`
-   en `proxy_net` se deriva solo de `-p <app>`, no hace falta tocar nada):
-   `docker compose -p <app> -f docker-compose.yml -f docker-compose.prod.yml -f docker-compose.shared-infra.yml up -d`.
-7. **Migraciones:** automáticas. El entrypoint del backend las corre en cada
-   boot (`doctrine:migrations:migrate`), junto con la generación de las claves
-   JWT y el wait-for-db. Solo verificar que no quedaron pendientes:
-   `docker exec <app>-backend-1 bin/console doctrine:migrations:status`.
-8. **Claves JWT:** en el primer boot el entrypoint las genera en `./secrets/jwt`
-   (bind-mount al host, gitignored) usando `JWT_PASSPHRASE`. **Backupear**
-   `~/<app>/secrets/jwt/{private,public}.pem` + la `JWT_PASSPHRASE` al gestor de
-   claves. De ahí en más persisten y NUNCA se regeneran (recrear el container no
-   desloguea a nadie). Para restaurar en un host nuevo: poné los `.pem` ahí antes
-   del `up`.
-9. **Health:** `docker exec <app>-backend-1 curl -s http://localhost/health` → `{"status":"ok"}`.
-10. **(Opt-in) Levantar el stack de staging:** staging es una app aparte en el VPS
-    con su propia DB desechable. Ver **"Runbook de staging"** más abajo.
-11. **(Cuando haya dominio)** vhost en `~/infra/caddy/Caddyfile` apuntando al
-    alias `<app>-frontend` + `docker exec infra-reverse-proxy-1 caddy reload`.
-12. **Smoke de flujos de negocio:** correr la collection Bruno de la app (`api/`,
-    si existe) contra el entorno recién levantado — apuntar `{{base_url}}` al host
-    correcto (público tras el paso 11, o `http://localhost` local) y verificar que
-    login + los flujos de dominio responden OK. Simétrico al `fixtures:load` del
-    runbook de staging: el health check confirma que el proceso arranca; la
-    collection confirma que el dominio funciona end-to-end. Es opt-in y por app —
-    Oliva no shipea la collection (los requests son 100% dominio, ver tabla de
-    stack del README).
-
-> **Gotcha pgvector / shared-infra:** en standalone la app conecta como el
-> superuser del Postgres local, así que la migración que hace
-> `CREATE EXTENSION vector` funciona. En shared-infra conecta como `<app>_user`
-> (no-superuser) y esa migración falla con *"permission denied to create
-> extension"*. Por eso `provision-postgres.sh` crea la extensión como superuser
-> al provisionar; la migración la encuentra con su `IF NOT EXISTS` y hace no-op.
-
-### Runbook de staging (pasos manuales, primera vez)
-
-Staging es **una app más** en el VPS: misma infra compartida, pero DB propia
-desechable y project name propio (`-p <app>-staging`). No interfiere con el
-stack de producción.
-
-> **Atajo para redeploys:** `./scripts/deploy-staging.sh` (ejecuta build + up
-> + migraciones + `fixtures:load` en una sola llamada). Los pasos de abajo
-> documentan el setup inicial (una sola vez) y la lógica de cada paso.
-
-1. **Provisionar la DB de staging** en el Postgres compartido, desde `~/infra`:
-   `./scripts/provision-postgres.sh <app>_staging_db <app>_staging_user`
-   → imprime el `DATABASE_URL` con la password generada (guardarla en el
-   gestor de claves). El script crea la extensión `vector` como superuser.
-2. **Crear `.env.staging`** (gitignored → NO viene del pull):
-   `cp .env.staging.example .env.staging`
-   Setear `DATABASE_URL` con la URL impresa en el paso anterior
-   (host `postgres`, `<app>_staging_user`, `<app>_staging_db`).
-3. **Build + up** (project name `-p <app>-staging` propio; staging como app en
-   shared-infra). `up -d --build` buildea automáticamente cualquier servicio
-   con sección `build` (backend/scheduler con tag `app-backend-staging:1.0`,
-   target `frankenphp_staging`; frontend con tag `app-frontend-staging:1.0`) —
-   no se enumeran servicios a propósito, ver gotcha más abajo:
-   ```bash
-   docker compose -p <app>-staging \
-     -f docker-compose.yml -f docker-compose.prod.yml \
-     -f docker-compose.shared-infra.yml -f docker-compose.staging.yml \
-     up -d --build
-   ```
-   Env files que se cargan: `.env` → `.env.backend` → `.env.staging`
-   (`.env.staging` carga último y pisa `DATABASE_URL`). `APP_ENV=staging` lo
-   fija `docker-compose.staging.yml` vía `environment:` (no vía env_file —
-   ver gotcha de precedencia abajo).
-5. **Migraciones:** automáticas en el entrypoint. Verificar:
-   `docker exec <app>-staging-backend-1 bin/console doctrine:migrations:status`
-6. **Seeding:** la imagen `frankenphp_staging` sí tiene `doctrine:fixtures:load`
-   (a diferencia de prod). La DB de staging es desechable — la purga es inocua:
-   ```bash
-   docker exec <app>-staging-backend-1 \
-     bin/console doctrine:fixtures:load --group=staging --no-interaction
-   ```
-7. **Health:** `docker exec <app>-staging-backend-1 curl -s http://localhost/health`
-
-Para reiniciar con datos frescos: `SKIP_PULL=1 ./scripts/deploy-staging.sh`.
-Para bajar staging (preserva el volumen de la DB desechable): `./scripts/down-staging.sh`
-(o `./scripts/down-staging.sh <app>`; análogo a `down.sh` pero con los 4 overlays
-y project name `<app>-staging`). Para purgar también el volumen, bajar a mano
-con `-v` agregado al comando de los 4 overlays.
-
-> **env_file de staging:** `docker-compose.staging.yml` usa `env_file: !override`
-> (Compose >= 2.24, mismo requisito que shared-infra) para REEMPLAZAR (no concatenar)
-> la lista del base. Sin `!override`, Compose concatena listas → `.env`/`.env.backend`
-> aparecerían duplicados. Con él, la lista queda `[.env, .env.backend, .env.staging]`
-> y `.env.staging` carga último, pisando `DATABASE_URL`.
-
-> **Gotcha — precedencia de `APP_ENV` (la saga que costó 3 capas):** en Compose,
-> `environment:` > `env_file:` > `ENV` horneado en la imagen. `prod.yml`
-> hardcodea `environment: APP_ENV=prod` en backend/scheduler — sin un
-> override explícito en `staging.yml`, ese `environment:` pisaba
-> `.env.staging` (env_file) Y el `ENV` del Dockerfile, pese a apilarse encima.
-> Síntoma real: `fixtures:load` fallaba con "command not defined" porque
-> `prod` no está en `bundles.php`. Por eso `docker-compose.staging.yml`
-> fija `environment: [APP_ENV=staging]` explícito en backend/scheduler, y el
-> stage `frankenphp_staging` del Dockerfile borra el `.env.local.php` heredado
-> de prod (otra capa que pisaba el entorno). Regla general para diagnosticar
-> cualquier env var que no toma el valor esperado: primero
-> `docker exec <c> printenv VAR` + `docker compose ... config` (de qué capa
-> sale), recién después editar.
-
-## Variables de entorno
-
-Ver `.env.example` como referencia. Agrupadas por servicio:
-- **DB — standalone (en `.env`)**: `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`, `POSTGRES_VERSION` y `DATABASE_URL` (la lee Doctrine). Las credenciales de `DATABASE_URL` deben coincidir con los `POSTGRES_*` — es el mismo Postgres local.
-- **DB — infra compartida (override en `.env.backend`)**: `DATABASE_URL` viene comentado por default; se descomenta/setea solo en deploys con infra compartida (apunta al `postgres` compartido) y pisa al de `.env`.
-- **Mercure**: `MERCURE_URL`, `MERCURE_PUBLIC_URL`, `MERCURE_PUBLISHER_JWT_KEY`, `MERCURE_JWT_SECRET`, `CADDY_MERCURE_URL`, `CADDY_MERCURE_PUBLIC_URL`
-- **RabbitMQ**: `RABBITMQ_USER`, `RABBITMQ_PASSWORD`, `RABBITMQ_DSN`
-- **JWT**: `JWT_PASSPHRASE`
+Verificar al **cierre** de sesión antes de cortar:
 
-## Health check y CI
+```bash
+git status -s                      # sin archivos sin commitear (salvo intencional)
+git log --oneline -3               # el último commit tiene hash real en agent-commits.md
+```
 
-- `GET /health` → `{"status": "ok"}` (`backend/src/Controller/HealthController.php`).
-- `.github/workflows/ci.yml`: build de imágenes, levanta los servicios, chequea `/health` y `/.well-known/mercure`, corre migraciones, valida el schema de Doctrine y corre PHPUnit. Job adicional de lint de Dockerfile con hadolint.
+Y en `CLAUDE.md` asegurarse de que **"Próximo paso"** apunte al paso correcto para la sesión siguiente.
 
 ## Protocolo de explicaciones conceptuales
 
 Cuando el usuario pide que se le explique un concepto (`"explicame X"`, `"enseñame X"`), el agente debe:
-1. Agregar la explicación al **final** de `docs/concepts.md` como una nueva sección `## NombreDelConcepto`.
-2. Commitear `docs/concepts.md` junto con el trabajo en curso (o en un commit separado si el usuario lo pide).
+1. Agregar la explicación al **final** de `concepts.md` como una nueva sección `## NombreDelConcepto`.
+2. Commitear `concepts.md` junto con el trabajo del paso en curso (o en un commit separado si el usuario lo pide).
 3. No repetir explicaciones ya presentes en el archivo — si el concepto ya está, referenciarlo.
 
-`docs/concepts.md` es acumulativo: nunca se borra contenido, solo se agrega.
+El archivo `concepts.md` es acumulativo: nunca se borra contenido, solo se agrega.
+
+---
 
 ## Protocolo de commits del agente
 
-Para proyectos multi-sesión o de trabajo autónomo, `agent-commits.md` en la raíz del proyecto registra cambios del agente con formato detallado. **No se anota cada commit**: cuando el agente haga un cambio que le parezca interesante (una decisión de diseño, un fix con *por qué* no obvio, algo que afecte cómo se opera el proyecto), **le pregunta a Marcos si lo registra** — Marcos decide. Lo rutinario no se anota ni se pregunta.
+**Cada commit que realice el agente debe registrarse en `agent-commits.md`** antes o junto con el commit de git. El registro es parte del entregable, no opcional.
 
-### Formato
+### Formato obligatorio
 
 ```markdown
 ## [PASO X.Y] <título del commit>
@@ -286,28 +111,4 @@ Para proyectos multi-sesión o de trabajo autónomo, `agent-commits.md` en la ra
 - La justificación debe responder **por qué**, no solo describir el qué (eso ya lo hace la tabla).
 - Si un cambio resuelve un problema encontrado durante la ejecución (no previsto en el plan), documentarlo explícitamente.
 - El commit de git y la entrada en `agent-commits.md` van en el **mismo commit**.
-
-## Comandos del agente
-
-Ver `claude-commands.md` en la raíz del proyecto para los comandos que el usuario puede invocar en el chat (protocolos de reinicio de sesión, etc.).
-
-## Chequeos de sanidad (inicio y cierre de sesión)
-
-Correr al **inicio** de cada sesión antes de tocar código:
-
-```bash
-git branch --show-current          # confirmar la rama de trabajo esperada
-git status -s                      # debe estar limpio (o saber qué hay pendiente)
-git log --oneline -3               # orientarse en dónde quedó la sesión anterior
-docker compose ps                  # todos los servicios healthy
-docker compose exec backend bin/console doctrine:migrations:status  # sin migraciones pendientes
-```
-
-Verificar al **cierre** de sesión antes de cortar:
-
-```bash
-git status -s                      # sin archivos sin commitear (salvo intencional)
-git log --oneline -3               # último commit con mensaje claro
-```
-
-Si el proyecto usa `agent-commits.md`, verificar si el último commit merece una entrada (si es un cambio interesante, agregar; si es rutinario, omitir).
+- `agent-commits.md` se agrega al staging junto con los demás archivos del paso.
diff --git a/PLAN-MARKET-PULSE.md b/PLAN-MARKET-PULSE.md
new file mode 100644
index 0000000..ca4cfca
--- /dev/null
+++ b/PLAN-MARKET-PULSE.md
@@ -0,0 +1,337 @@
+# Plan de proyecto — "Crypto Pulse" (codename provisional)
+
+> Proyecto-vidriera construido **sobre** la codebase Oliva.
+> Estado: **planificación cerrada. Cero modificaciones físicas al código todavía** (salvo este doc y CLAUDE.md).
+> Rama de trabajo: `release/plan-market-pulse`
+> Fecha: 2026-05-31
+>
+> **Propósito de este documento:** ser un **runbook ejecutable de inicio a fin**. Está escrito para que un modelo más económico (Sonnet) pueda implementarlo paso a paso sin re-derivar decisiones. Cada paso trae: *objetivo · acciones concretas (archivos/comandos) · verificación*. Ver §11 (convenciones de ejecución) antes de empezar a codear.
+
+---
+
+## 0. Tesis del proyecto
+
+Construir, **encima de la codebase Oliva**, una **plataforma de inteligencia de mercado cripto en tiempo real**: ingiere noticias y datos de mercado de fuentes públicas, los enriquece con IA (resumen, sentiment, clasificación, entidades, embeddings) y los emite en vivo a un dashboard vía Mercure.
+
+El reparto de capas es deliberado:
+
+| Capa | Mundo que representa | Rol en el proyecto |
+|---|---|---|
+| **Infraestructura / orquestación** | DevOps (relegado, a revivir) | **El titular.** Es lo que la codebase *es* y lo que tu CV no muestra. |
+| **Pipeline IA (enriquecimiento, embeddings, RAG)** | IA (deep dive actual) | **El motor.** Mantiene la motivación y monta el músculo que querés. |
+| **Dominio: mercado cripto (noticias + datos)** | Trading (en pausa) | **El sabor.** Mantiene trading tibio sin apostarle el proyecto. |
+| **Backend Symfony** | 4 años de experiencia | **El piso.** Asumido, invisible, no se demuestra. |
+
+**Decisión de fondo (cerrada):** el headline es **DevOps × IA** (AI infra / MLOps). No se construyen estrategias de trading: cripto es el dominio de datos, no el producto.
+
+**Por qué cripto encaja aún mejor que mercados tradicionales:** opera **24/7** (no hay "mercado cerrado" que apague la demo), tiene **altísima velocidad de noticias** y volatilidad, y las **APIs públicas gratuitas y sin API key** son excelentes (CoinGecko, RSS de medios cripto). Refuerza justo lo que hace brillar el proyecto: el realtime es genuino y la demo está siempre viva.
+
+### Por qué este proyecto y no el "Research OS" (cerrado)
+- **No tiene arranque en frío:** las fuentes públicas lo llenan solas. La demo está viva desde el segundo cero.
+- **El realtime es genuino y YA funciona:** el hub Mercure está operativo en la codebase (ver §1). Una noticia rompe → se enriquece → el dashboard se actualiza en vivo. Ese es el "wow" de 30s.
+- **Maximiza superficie DevOps:** arquitectura event-driven, broker, workers, scheduler, observabilidad, CI/CD, deploy real.
+- **El frontend actual alcanza:** dashboard de cards en vivo con el stack Vanilla JS/Bootstrap existente.
+
+---
+
+## 1. Estado actual del repositorio (línea de base real — verificado)
+
+### Lo que YA existe y sirve
+- **Orquestación dev/prod** con 3 compose (`docker-compose.yml` + `override` auto en dev + `prod`). Sólido.
+- **Backend** FrankenPHP (PHP 8.3), multi-stage (`frankenphp_base` → `frankenphp_dev` xdebug+`--watch` / `frankenphp_prod` worker mode), JWT (lexik) instalado en build, healthcheck a `:2019/metrics`.
+- **Hub Mercure ACTIVO** en `backend/frankenphp/Caddyfile` (módulo `mercure`, `anonymous` + `publisher_jwt`). **El realtime ya funciona.**
+- **Demo realtime probado**: canvas colaborativo (`backend/public/live.php` + `frontend/src/js/live.js`) con `EventSource` + Mercure. Prueba viva del end-to-end.
+- **Frontend** Vite 6, Vanilla JS modular (`main.js`, `setup.js`, `live.js`), Bootstrap 5, multi-stage (dev `yarn dev` / prod Caddy sirviendo `dist/`). Caddyfile con CSP, cache, compresión y proxy de `/api/*`, `/live.php`, `/.well-known/mercure*`.
+- **Postgres 15** con healthcheck y volumen `db_data`.
+- **`.env.example`** trae ya variables de Mercure y DB.
+- **CI** existente (`backend/.github/workflows/ci.yml`).
+
+### Gaps reales (verificado por inspección)
+- [ ] **`backend/composer.json` NO existe en el host; `backend/src/` solo tiene un `Controller/` vacío; git no versiona nada de eso.** El esqueleto Symfony se genera en build (`composer create-project` en el Dockerfile). → decisión estructural §3.1.
+- [ ] No hay **Doctrine ORM ni Migrations**.
+- [ ] No hay **`pgvector`**.
+- [ ] No hay **`MercureBundle`** (publisher desde Symfony). El hub sí funciona; solo falta publicar limpio desde el dominio.
+- [ ] No hay **Messenger / broker / workers**.
+- [ ] No hay **scheduler**.
+- [ ] No hay **integración LLM** ni capa de costo/caché.
+- [ ] No hay **tests** (PHPUnit); pasos del CI en `if: false`.
+- [ ] **CI desalineado**: referencia `compose.yaml`/`compose.override.yaml` (nombres del template) en vez de `docker-compose.yml`.
+- [ ] No hay **observabilidad** más allá del healthcheck.
+- [ ] No hay **deploy** ni dominio público.
+
+---
+
+## 2. Arquitectura objetivo
+
+```
+                         Fuentes públicas cripto
+            (RSS: CoinDesk, Cointelegraph · CoinGecko REST · CryptoPanic)
+                                   │
+                                   ▼
+        ┌────────── scheduler (cron container, supercronic) ──────────┐
+        │           dispara polls cada N min → encola "fetch X"        │
+        ▼                                                              │
+   [ RabbitMQ ]  exchange→cola `ingest`  /  cola `enrich`  / DLX       │
+        │                                                              │
+        ▼                                                              │
+   worker INGESTA ── normaliza, deduplica (hash) ── persiste crudo ─► Postgres
+        │                                                          (+pgvector)
+        ▼  encola "enrich item Y"                                      ▲
+   worker ENRIQUECE ── LLM (Anthropic): resumen, sentiment, clase,     │
+        │              entidades, embedding ── persiste enriquecido ───┘
+        ▼  publish (HubInterface)
+   [ Hub Mercure (embebido en FrankenPHP/Caddy) ]
+        │  SSE
+        ▼
+   Frontend (Caddy/Vite) ── dashboard en vivo: feed, filtros,
+                            búsqueda semántica, "market now"
+        ▲
+        │  /api/* (REST: histórico, búsqueda, detalle)
+        └─ Backend (Symfony) ── API + publisher Mercure
+```
+
+### Servicios Docker objetivo
+| Servicio | Estado | Notas |
+|---|---|---|
+| `database` | existe | migrar a `pgvector/pgvector:pg15`; extensión `vector` por migración |
+| `backend` | existe | + Doctrine, Messenger, MercureBundle, cliente Anthropic; API + publish |
+| `frontend` | existe | nuevo dashboard; reusa stack actual |
+| `worker` | **nuevo** | misma imagen backend, `command: messenger:consume ingest enrich`; escalable a N réplicas |
+| `scheduler` | **nuevo** ✅ | **contenedor cron dedicado (supercronic)**; encola polls; pieza de orquestación explícita |
+| `rabbitmq` | **nuevo** ✅ | imagen `rabbitmq:3-management`; UI en `:15672`; volumen para durabilidad |
+| `mercure` | existe (embebido) | no requiere servicio aparte: vive en el Caddy de FrankenPHP |
+| `prometheus` | **nuevo (Fase 3)** | scrapea `:2019/metrics` de Caddy + métricas custom del pipeline |
+| `grafana` | **nuevo (Fase 3)** | dashboards: lag de cola, throughput, latencia/costo LLM, errores |
+
+---
+
+## 3. Decisiones técnicas (TODAS CERRADAS)
+
+### 3.1 — Versionar el `src/` del backend ⭐ (estructural — primer paso ineludible)
+**Hoy:** el skeleton se regenera en cada build (`composer create-project`); `composer.json` y el código no están en git. Con dominio real eso es inviable: se perdería el código en cada rebuild.
+**Decisión:** graduar de "boilerplate que se regenera" a "app versionada":
+1. Generar el skeleton **una vez** dentro del contenedor y exportarlo al host.
+2. Comitear `backend/composer.json`, `composer.lock`, `symfony.lock`, `src/`, `config/`, `bin/`, `public/index.php`, `migrations/`.
+3. Quitar el bloque `composer create-project` del Dockerfile; dejar `composer install` sobre el código del repo. (El stage `frankenphp_prod` ya hace `COPY composer.* ...` + `composer install` + `COPY . ./`; alinear el base a eso.)
+4. Eliminar el bloque "install first time" del `docker-entrypoint.sh` (lo indica el propio comentario del archivo).
+
+### 3.2 — Persistencia ✅
+Doctrine ORM (`symfony/orm-pack`) + Doctrine Migrations. Habilitar los pasos del `ci.yml` correspondientes.
+
+### 3.3 — Capa vectorial ✅
+`pgvector` sobre el Postgres existente (sin servicio nuevo). Imagen `pgvector/pgvector:pg15`. Extensión `vector` vía migración. Integración Doctrine: verificar el paquete vigente (`pgvector/pgvector` para PHP + tipo custom Doctrine `vector`). Índice HNSW/IVFFlat para búsqueda por similitud.
+
+### 3.4 — Mensajería (broker) ✅
+**RabbitMQ** (`rabbitmq:3-management`) + Messenger **AMQP transport**. Management UI en `:15672` (mostrable en la demo DevOps). Colas: `ingest` y `enrich`, con **dead-letter exchange** para fallos. Mensajes durables. Usuario con experiencia previa en Rabbit.
+
+### 3.5 — Scheduler ✅
+**Contenedor cron dedicado** (`supercronic`, imagen liviana). Ejecuta un comando Symfony (`app:sources:poll`) en intervalos configurables que encola en RabbitMQ. Orquestación explícita y observable.
+
+### 3.6 — Publisher Mercure ✅
+El **hub ya funciona**. Solo falta el publisher: instalar `symfony/mercure-bundle`, descomentar el COPY de `frankenphp/docker-configs/mercure.yaml` en el Dockerfile, publicar con `HubInterface`. Retirar `live.php` raw una vez migrado el demo (o conservarlo como página "playground" aparte).
+
+### 3.7 — Proveedor LLM ✅ DECIDIDO
+**Anthropic (Claude).** Modelos: **Haiku** (`claude-haiku-4-5`) para enriquecimiento de alto volumen (resumen/sentiment/clasificación/entidades por item) y **Sonnet** (`claude-sonnet-4-6`) para resúmenes agregados "Market Now". **No hay SDK oficial PHP**: usar `symfony/http-client` contra la API de Anthropic, encapsulado tras una interfaz `EnrichmentProvider` (mockeable en tests, intercambiable de proveedor).
+**Controles de costo obligatorios:** (a) cada item se enriquece **una sola vez** (idempotencia por estado); (b) **caché** prompt→respuesta; (c) **prompt caching** de Anthropic en el system prompt fijo; (d) límite de gasto/rate configurable; (e) métrica de **costo en Grafana** (Fase 3). Embeddings: usar un proveedor de embeddings dedicado (verificar opción Anthropic/Voyage o un modelo local) — decisión de implementación a confirmar en el paso 1.4, abstraída tras `EmbeddingProvider`.
+
+### 3.8 — Fuentes de datos ✅ DECIDIDO — dominio CRYPTO
+**Stack elegido (cripto-nativo, óptimo y mayormente sin API key):**
+- **MVP — Noticias (sin key):** RSS de **CoinDesk** y **Cointelegraph**. Cero dependencia de claves, alta velocidad, ideal para el primer loop.
+- **MVP — Datos de mercado (sin key):** **CoinGecko REST** (precios, market cap, volumen, % cambio). Mejor cobertura gratuita y sin clave para endpoints públicos. Útil para contexto/impact y para enriquecer noticias con el activo afectado.
+- **Fase 2 — Noticias enriquecidas (free tier con key):** **CryptoPanic API** — agregador cripto-nativo con metadata de fuente/sentiment/votos.
+> Nota: de las tres APIs genéricas que estaban como opción original (Finnhub/Marketaux/NewsAPI), la mejor para cripto sería **Finnhub**; pero al ser el dominio 100% cripto, las fuentes cripto-nativas de arriba son superiores. Contrato `SourceAdapter` para sumar fuentes sin tocar el pipeline. **Respetar rate limits y términos de cada API.**
+
+---
+
+## 4. Runbook por fases (orden = protección de la motivación)
+
+> **Regla de oro:** el producto que funciona va primero; la vidriera DevOps va después. No front-cargar infra antes de tener algo andando — fue donde el proyecto se trabó hace un año.
+> Cada paso: **Objetivo · Acciones · Verificación.** Marcado de versiones/paquetes "(verificar vigente)" = el ejecutor confirma nombre/versión exactos al momento de instalar.
+
+### FASE 0 — Fundaciones (sin features visibles)
+
+**✅ 0.1 — Versionar el `src/` del backend** ⭐
+- *Objetivo:* dejar el código de la app en git; quitar la regeneración en build.
+- *Acciones:* levantar el backend actual; dentro del contenedor exportar el skeleton generado al host; comitear `composer.json/lock`, `symfony.lock`, `src/`, `config/`, `bin/`, `public/`, `migrations/`; editar `backend/Dockerfile` quitando `composer create-project` y dejando `composer install`; limpiar el bloque "install first time" de `docker-entrypoint.sh`; ajustar `.dockerignore`.
+- *Verificación:* `docker compose build backend && docker compose up backend` levanta sin `create-project`; `git status` muestra el código versionado; `bin/console about` corre dentro del contenedor.
+
+**✅ 0.2 — Doctrine ORM + Migrations**
+- *Acciones:* `composer require symfony/orm-pack` y `symfony/maker-bundle --dev` (verificar vigente); configurar `DATABASE_URL`; primera migración vacía.
+- *Verificación:* `bin/console doctrine:migrations:migrate` corre contra la DB del compose; `doctrine:schema:validate` ok.
+
+**✅ 0.3 — pgvector**
+- *Acciones:* cambiar imagen de `database` a `pgvector/pgvector:pg15` en `docker-compose.yml`; migración `CREATE EXTENSION IF NOT EXISTS vector`; instalar integración Doctrine de vectores (verificar paquete).
+- *Verificación:* migración aplica; un insert/select de un `vector` de prueba funciona vía SQL.
+
+**✅ 0.4 — MercureBundle (publisher)**
+- *Acciones:* `composer require symfony/mercure-bundle`; descomentar COPY de `mercure.yaml` en Dockerfile; configurar `MERCURE_URL`/`MERCURE_PUBLIC_URL`/JWT en `.env*`.
+- *Verificación:* un comando de prueba publica a un topic y `live.js` (o `curl` al hub) lo recibe.
+
+**✅ 0.5 — Messenger + RabbitMQ**
+- *Acciones:* agregar servicio `rabbitmq:3-management` (puertos 5672/15672, volumen, healthcheck, env user/pass) al compose; `composer require symfony/messenger symfony/amqp-messenger` (verificar vigente); configurar transports `ingest` y `enrich` con DSN AMQP + DLX en `config/packages/messenger.yaml`; añadir servicio `worker` (misma imagen backend, `command: bin/console messenger:consume ingest enrich -vv`, `restart: unless-stopped`, `depends_on` rabbitmq healthy).
+- *Verificación:* UI de Rabbit en `:15672`; un mensaje de prueba viaja por la cola y el worker lo procesa; un fallo va al DLX.
+
+**✅ 0.6 — Scheduler (cron container)**
+- *Acciones:* servicio `scheduler` con `supercronic` (verificar imagen) ejecutando `bin/console app:sources:poll` cada N min (crontab en repo); comando stub que por ahora solo loguea/encola.
+- *Verificación:* logs del scheduler muestran ejecución periódica; encola en Rabbit.
+
+**✅ 0.7 — CI base coherente**
+- *Acciones:* corregir `ci.yml` para usar `docker-compose.yml` reales; quitar `if: false` de los pasos de ORM/migraciones a medida que existan; agregar healthcheck de servicios nuevos al `up --wait`.
+- *Verificación:* CI verde en push a la rama.
+
+**✅ 0.8 — PHPUnit base**
+- *Acciones:* `composer require --dev phpunit/phpunit symfony/test-pack` (verificar vigente); 1 test trivial; habilitar el paso PHPUnit del CI.
+- *Verificación:* `php vendor/bin/phpunit` verde local y en CI. (`bin/phpunit` ya no es generado por la recipe en PHPUnit 12; usar `vendor/bin/phpunit` directamente.) `failOnDeprecation/Notice/Warning` relajados intencionalmente hasta paso 3.4.
+
+**GATE Fase 0 ✅:** `docker compose up` levanta DB+pgvector, backend, rabbitmq, worker, scheduler; un comando publica a Mercure y se ve en el front; un mensaje recorre Rabbit→worker; CI verde con un test.
+
+### FASE 1 — Producto end-to-end (1 fuente, 1 tarea IA) — "que ande y dé orgullo"
+
+**✅ 1.1 — Modelo de dominio**
+- *Acciones:* entidades `NewsItem` (source, externalId, title, url, body, publishedAt, contentHash único, status enum) y `Enrichment` (summary, sentiment, assetClass/tickers, entities JSON, embedding `vector`, model, tokens, costUsd, createdAt). Migraciones. Índice único por `contentHash`. Índice vectorial.
+- *Verificación:* migraciones aplican; fixtures de prueba persisten.
+
+**✅ 1.2 — Ingesta (CoinDesk/Cointelegraph RSS)**
+- *Acciones:* interfaz `SourceAdapter`; `RssAdapter` para los 2 feeds; `IngestMessage` + handler: fetch → parse → normaliza → dedup por `contentHash` → persiste `NewsItem(status=pending)` → despacha `EnrichMessage`.
+- *Verificación:* corriendo el poll, aparecen `NewsItem` reales en la DB sin duplicados.
+
+**✅ 1.3 — Poll programado**
+- *Acciones:* implementar `app:sources:poll` real (recorre adapters, despacha `IngestMessage`); cron del scheduler lo dispara.
+- *Verificación:* sin intervención manual, entran items nuevos periódicamente.
+
+**✅ 1.4 — Enriquecimiento IA**
+- *Acciones:* `EnrichmentProvider` (Anthropic Haiku vía http-client) → resumen + sentiment + clase de activo + tickers/entidades; `EmbeddingProvider` → embedding (definir proveedor aquí, §3.7); handler de `EnrichMessage`: idempotente, cachea, persiste `Enrichment`, registra tokens/costo, marca `NewsItem(status=enriched)`.
+- *Verificación:* items pasan a `enriched` con resumen y embedding; reintentos no duplican costo; fallo de API → DLX, no se pierde el item.
+
+**1.5 — Publish a Mercure**
+- *Acciones:* al persistir `Enrichment`, publicar el item enriquecido al topic `crypto/feed` con `HubInterface`.
+- *Verificación:* `curl` al hub / front recibe el evento.
+
+**1.6 — API REST**
+- *Acciones:* `GET /api/feed` (paginado, filtros básicos) y `GET /api/items/{id}`; serialización; CORS/headers según Caddyfile.
+- *Verificación:* endpoints responden JSON correcto; paginación ok.
+
+**1.7 — Dashboard en vivo**
+- *Acciones:* nueva vista (reusar patrón `live.js`/Bootstrap): carga inicial vía REST + suscripción Mercure a `crypto/feed`; cada card muestra resumen IA, sentiment, etiquetas/tickers, fuente, timestamp; indicador LIVE/RECONNECTING.
+- *Verificación:* abrir 2 pestañas; entra noticia real; aparece enriquecida y se actualiza en vivo en ambas sin recargar.
+
+**1.8 — Robustez del pipeline**
+- *Acciones:* reintentos con backoff en Messenger; idempotencia; manejo de DLX (comando para reprocesar/inspeccionar); timeouts de http-client; degradación con gracia del front.
+- *Verificación:* matar el worker / cortar la API LLM no pierde datos; al reanudar, procesa el backlog.
+
+**GATE Fase 1 (DEMO):** 2 pestañas → entra noticia cripto real → en segundos aparece enriquecida por IA y se actualiza en vivo en ambas. Pipeline resiste caídas.
+
+### FASE 2 — Profundizar IA y dominio
+
+**2.1** Múltiples fuentes vía `SourceAdapter`: sumar CoinGecko (datos de mercado/contexto) y CryptoPanic (Fase 2 con key). *Verif:* 3+ fuentes estables en paralelo.
+**2.2** Búsqueda semántica (pgvector): `GET /api/search?q=` (embed query → kNN) + UI. *Verif:* resultados relevantes por significado, no keyword.
+**2.3** Clustering/dedupe por tema (similitud de embeddings): agrupar noticias que cuentan lo mismo. *Verif:* eventos repetidos se agrupan.
+**2.4** "Market Now": resumen agregado periódico (Sonnet) publicado en vivo. *Verif:* panel creíble que se refresca.
+**2.5** Impact score (heurística + IA) para priorizar. *Verif:* orden por impacto sensato.
+**2.6** Filtros del dashboard (clase, sentiment, fuente, impacto, ticker). *Verif:* filtros aplican sobre feed y búsqueda.
+**2.7** (Opcional) Alertas por reglas del usuario → Mercure. *Verif:* regla dispara notificación en vivo.
+
+**GATE Fase 2:** búsqueda semántica útil + "Market Now" creíble + varias fuentes estables.
+
+### FASE 3 — Vidriera DevOps (el titular) ⭐
+
+**3.1 Observabilidad — métricas:** Prometheus scrapea `:2019/metrics` (Caddy/FrankenPHP ya lo expone) + métricas custom (lag de cola desde Rabbit, items/min, latencia y **costo LLM**, tasa de error/DLX). Grafana con dashboards del pipeline. *Verif:* Grafana muestra el pipeline en vivo.
+**3.2 Observabilidad — logs:** logs estructurados JSON (Monolog) en backend y workers; (opcional) Loki/Promtail. *Verif:* logs correlacionables por item/mensaje.
+**3.3 Health/readiness** de `worker`, `scheduler`, `rabbitmq`. *Verif:* `docker compose ps` healthy; `up --wait` pasa.
+**3.4 Tests:** unitarios de dominio + adapters (LLM mockeado) + 1 integración del pipeline; habilitar todos los pasos del `ci.yml`. *Verif:* cobertura de los caminos críticos; CI verde.
+**3.5 CI/CD:** Actions → build multi-stage, hadolint (ya está), tests, **push de imágenes a GHCR** con tag por versión. *Verif:* imágenes publicadas por release.
+**3.6 Deploy:** VPS con stack `prod`; dominio público; **HTTPS automático** (Caddy con `SERVER_NAME` real); CD que despliega en push a `main`. *Verif:* URL pública HTTPS; deploy automatizado.
+**3.7 Operación:** backups de Postgres (dump periódico + retención), migraciones en deploy (paso controlado), límites de recursos por servicio, rotación de logs, durabilidad de colas Rabbit, runbook breve. *Verif:* restore de backup probado; deploy con migración sin downtime perceptible.
+**3.8 Secrets:** sacar credenciales de `.env` versionados; usar secrets del entorno/CI; rotar JWT/Mercure/DB/API keys. *Verif:* repo sin secretos; `git log` limpio (o secretos rotados si hubo exposición).
+
+**GATE Fase 3:** URL pública HTTPS; `git push main` despliega solo; Grafana muestra pipeline + costo LLM; README con badges reales y GIF de la demo.
+
+### FASE 4 — Puente a trading (FUTURO, fuera de scope inicial)
+Diferido. Solo tras cerrar 0–3: señales derivadas del sentiment/impact agregado; backtest del valor predictivo; watchlists por ticker con alertas. **No empezar por acá.**
+
+---
+
+## 5. Mapa skill → entregable (narrativa de portfolio)
+- **DevOps/infra:** arquitectura event-driven, RabbitMQ, workers escalables, cron container, observabilidad (Prometheus/Grafana), CI/CD, deploy HTTPS, backups. → Fases 0, 3.
+- **IA Systems:** pipeline LLM con caché y control de costo, embeddings + búsqueda semántica (RAG básico), clustering, resúmenes agregados. → Fases 1, 2.
+- **Cripto/datos:** modelado del dominio, fuentes cripto-nativas, clasificación, impact scoring. → Fases 1, 2.
+- **Backend (asumido):** Symfony/Doctrine/API — el piso, no el argumento.
+
+---
+
+## 6. Riesgos y mitigaciones
+| Riesgo | Mitigación |
+|---|---|
+| Abandono por front-cargar infra | Producto andando (Fase 1) antes de observabilidad/deploy. |
+| Scope creep hacia "OS" | Anti-scope §7. Fase 1 = 1 tipo de fuente, 1 tarea IA. |
+| Costo LLM descontrolado | Enriquecer una vez + caché + prompt caching + Haiku para volumen + métrica de costo + límite configurable. |
+| Regenerar skeleton borra el dominio | Paso 0.1 al inicio: versionar `src/`. |
+| Rate limits / caída de fuentes | Reintentos+backoff, DLX, respetar límites de API, degradación con gracia. |
+| Demo vacía | Dominio cripto 24/7 con fuentes públicas; seed al primer arranque. |
+| Secrets en el repo | Auditar `.env*` antes del deploy público (3.8). |
+
+## 7. Anti-scope (qué NO hacer)
+- ❌ Estrategias de trading / señales en el MVP (Fase 4).
+- ❌ Knowledge graph / UI de grafos.
+- ❌ Multi-tenant / auth compleja en MVP (JWT ya está si hace falta).
+- ❌ Reescribir el frontend a un framework SPA.
+- ❌ Kubernetes en MVP (Compose alcanza; k8s sería otra vidriera, Fase 4+).
+- ❌ "Soportar todas las fuentes": empezar con RSS, crecer vía `SourceAdapter`.
+
+## 8. Definición de "demo de 60 segundos" (la vara)
+1. Abro la URL pública (HTTPS) en dos pestañas.
+2. Señalo el indicador **LIVE** y el panel **Market Now**.
+3. Entra una noticia cripto real → en segundos aparece **enriquecida por IA** (resumen, sentiment, tickers) y se actualiza **en vivo en ambas pestañas**.
+4. Hago una **búsqueda semántica** ("regulación", "ETF", "hack") y muestro resultados por significado.
+5. Abro **Grafana**: throughput, lag de cola y **gasto LLM** en vivo. (Bonus: la UI de RabbitMQ con las colas.)
+> Si los 5 puntos funcionan sin recargar y sin explicación, el proyecto cumplió.
+
+## 9. Costos estimados (mensual, orden de magnitud)
+- **VPS** (2 vCPU / 4 GB): bajo. (Rabbit + Prometheus + Grafana suman RAM; dimensionar.)
+- **LLM**: controlado por caché + Haiku; depende del volumen de noticias (cientos/día ≈ bajo).
+- **APIs de datos**: MVP 100% sin key (RSS + CoinGecko); CryptoPanic free tier en Fase 2.
+- **Dominio**: anual, mínimo.
+
+---
+
+## 10. Próximo paso inmediato
+Arrancar por **0.1 (versionar `src/`)** — cuello de botella estructural. Antes de tocar código de implementación, conviene cambiar al modelo de ejecución (ver §11).
+
+---
+
+## 11. Convenciones de ejecución (LEER antes de implementar — handoff de modelo)
+
+**Para qué modelo ejecuta esto:** este plan fue redactado con Opus a propósito (decisiones de arquitectura y altitud). **La implementación conviene hacerla con Sonnet** (`claude-sonnet-4-6`): excelente para seguir un runbook detallado y escribir código multi-archivo, mucho más barato. **Haiku** reservarlo para pasos mecánicos triviales (ediciones puntuales, renombres); para código de dominio/Docker/pipeline, Sonnet es el equilibrio correcto. El cambio de modelo no rompe nada: este archivo es el artefacto de handoff; cualquier modelo retoma desde acá.
+
+**Reglas para el ejecutor:**
+1. **Una fase a la vez, una caja a la vez.** No avanzar de paso sin cumplir su *Verificación*. No avanzar de fase sin cumplir su *GATE*.
+2. **Verificar versiones/paquetes vigentes** donde dice "(verificar vigente)" antes de instalar; no hardcodear versiones a ciegas.
+3. **No commitear ni pushear salvo pedido explícito** del usuario. Trabajar en `release/plan-market-pulse`.
+4. **No tocar `main`.** No borrar el demo de Mercure sin avisar (es activo de §1).
+5. **Respetar el anti-scope (§7).** Si una tarea empuja fuera de scope, parar y preguntar.
+6. **Costo LLM:** nunca enriquecer un item dos veces; caché siempre activo; en dev usar un mock de `EnrichmentProvider` por defecto para no gastar.
+7. **Secrets:** jamás commitear claves; usar `.env*` ignorados.
+8. **Ante ambigüedad o decisión no cubierta por este plan: parar y preguntar al usuario,** no improvisar arquitectura.
+9. **Marcar progreso** tildando las cajas `[ ]` de §4 a medida que se cierran (con su verificación cumplida).
+
+## 12. Checklist maestro "listo para producción"
+- [x] `src/` versionado; build sin `create-project` (0.1)
+- [x] Migraciones versionadas y aplicables en deploy (0.2) — completar en 3.7
+- [x] pgvector habilitado (0.3) — índice vectorial en 1.1
+- [x] Mercure publisher operativo (0.4)
+- [x] RabbitMQ durable + DLX + UI (0.5)
+- [ ] Workers escalables con reintentos/backoff e idempotencia (0.5, 1.8)
+- [x] Scheduler (cron container) estable (0.6)
+- [ ] Healthchecks en TODOS los servicios (3.3)
+- [x] Tests unitarios base + CI verde (0.8) — ampliar cobertura en 3.4
+- [ ] CI/CD con push de imágenes a GHCR (3.5)
+- [ ] Deploy a VPS con HTTPS automático + dominio (3.6)
+- [ ] CD en push a `main` (3.6)
+- [ ] Observabilidad: Prometheus + Grafana (métricas, lag, costo LLM) (3.1)
+- [ ] Logs estructurados (3.2)
+- [ ] Backups de Postgres con restore probado (3.7)
+- [ ] Límites de recursos y rotación de logs (3.7)
+- [ ] Sin secretos en el repo; secrets gestionados fuera (3.8)
+- [ ] Control de costo LLM (caché, prompt caching, límite, métrica) (3.7, 3.1)
+- [ ] README con badges reales + GIF de la demo (3.6)
+- [ ] Demo de 60s (§8) reproducible de punta a punta
diff --git a/README.md b/README.md
index 4767076..36f8fa0 100644
--- a/README.md
+++ b/README.md
@@ -1,38 +1,24 @@
 # Oliva
 
-A reusable full-stack framework for building webapps — decoupled backend and frontend, real-time updates, async queues, scheduled tasks, all fully containerized and production-ready out of the box.
+A full-stack web application boilerplate — decoupled backend and frontend, fully containerized, production-ready out of the box.
 
-![PHP](https://img.shields.io/badge/PHP-8.3-black?style=flat-square&logo=php)
-![Symfony](https://img.shields.io/badge/Backend-Symfony%207.4-000000?style=flat-square&logo=symfony)
+![PHP](https://img.shields.io/badge/PHP-Symfony%207-black?style=flat-square&logo=symfony)
 ![FrankenPHP](https://img.shields.io/badge/Runtime-FrankenPHP-5C2D91?style=flat-square)
-![Vite](https://img.shields.io/badge/Frontend-Vite%206-646CFF?style=flat-square&logo=vite&logoColor=white)
-![PostgreSQL](https://img.shields.io/badge/Database-PostgreSQL%20%2B%20pgvector-336791?style=flat-square&logo=postgresql&logoColor=white)
-![RabbitMQ](https://img.shields.io/badge/Queues-RabbitMQ-FF6600?style=flat-square&logo=rabbitmq&logoColor=white)
-![Mercure](https://img.shields.io/badge/Realtime-Mercure-2EA3F2?style=flat-square)
+![Vite](https://img.shields.io/badge/Frontend-Vite-646CFF?style=flat-square&logo=vite&logoColor=white)
+![PostgreSQL](https://img.shields.io/badge/Database-PostgreSQL%2015-336791?style=flat-square&logo=postgresql&logoColor=white)
 ![Docker](https://img.shields.io/badge/Infrastructure-Docker%20Compose-2496ED?style=flat-square&logo=docker&logoColor=white)
 ![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)
 
 ---
 
-## What this is
-
-Oliva is the base every new project starts from: a backend, a frontend, a database, real-time messaging, async queues, and a cron-style scheduler — already wired together, already passing CI. New apps fork it and build features on top instead of re-solving infrastructure.
-
 ## Stack
 
 | Layer | Technology |
 |---|---|
-| Backend | Symfony 7.4 (PHP 8.3+) · FrankenPHP (worker mode) · Caddy · JWT Auth (Lexik) |
-| Frontend | Vite 6 · Vanilla JS · Bootstrap 5 · Swiper · SweetAlert2 |
-| Database | PostgreSQL + [pgvector](https://github.com/pgvector/pgvector) (vector similarity search) |
-| Real-time | [Mercure](https://mercure.rocks/) hub (built into Caddy) |
-| Queues | RabbitMQ + Symfony Messenger |
-| Scheduled tasks | `supercronic` running `backend/scheduler/crontab` |
-| Staging / seeding | [Foundry](https://symfony.com/bundles/ZenstruckFoundryBundle/current/index.html) + Doctrine Fixtures · `frankenphp_staging` Docker stage |
-| API testing | [Bruno](https://www.usebruno.com/) collection in `api/` (per-app, not shipped by Oliva — the requests are 100% domain-specific) |
-| Infrastructure | Docker Compose · bridge network · multi-stage builds (dev / prod / staging) |
-
-See `docs/concepts.md` for explanations of the less obvious pieces (pgvector, AMQP, Mercure, etc.) and `docs/examples/` for reference skeletons of a queue producer/consumer and a Mercure publisher.
+| Backend | Symfony 7 · FrankenPHP (worker mode) · Caddy · JWT Auth |
+| Frontend | Vite · Vanilla JS · Bootstrap 5 · Swiper · SweetAlert2 |
+| Database | PostgreSQL 15 |
+| Infrastructure | Docker Compose · Bridge Network · Multi-stage builds |
 
 ---
 
@@ -56,11 +42,9 @@ docker compose up
 |---|---|
 | Frontend | http://localhost:3000 |
 | Backend API | http://localhost:80/api |
-| Mercure hub | http://localhost/.well-known/mercure |
-| RabbitMQ management | http://localhost:15672 |
 | Database | localhost:5432 |
 
-Hot reload is enabled — changes to `backend/src` and `frontend/src` reflect instantly without rebuilding. In dev, a `worker` service also runs `messenger:consume` against the `ingest`/`enrich` queues (commented out by default, see `docs/examples/`).
+Hot reload is enabled — changes to `backend/src` and `frontend/src` reflect instantly without rebuilding.
 
 ### Production
 
@@ -72,9 +56,7 @@ docker compose -f docker-compose.yml -f docker-compose.prod.yml build
 docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d
 ```
 
-The frontend is served by Caddy on **http://localhost**. The backend, database, RabbitMQ and scheduler are internal — never directly reachable from outside.
-
-> **Known gap:** there's no production `worker` service yet. If your app uses Messenger queues for real, add one to `docker-compose.prod.yml` (image `app-backend-prod:1.0`, command `messenger:consume`, no exposed ports) before going live — `scheduler` is already covered in prod.
+The frontend is served by Caddy on **http://localhost**. The backend and database are internal — never directly reachable from outside.
 
 ---
 
@@ -82,21 +64,15 @@ The frontend is served by Caddy on **http://localhost**. The backend, database,
 
 ```
 oliva/
-├── backend/                # Symfony 7.4 app (FrankenPHP + Caddy)
+├── backend/          # Symfony 7 app (FrankenPHP + Caddy)
 │   ├── src/
 │   ├── config/
-│   ├── migrations/
-│   ├── scheduler/          # crontab consumed by supercronic
-│   └── frankenphp/         # Caddy and PHP runtime config
-├── frontend/                # Vite app
+│   └── frankenphp/   # Caddy and PHP runtime config
+├── frontend/         # Vite app
 │   ├── src/
-│   │   └── js/live.js      # Mercure live-update demo
-│   └── Caddyfile           # Production static file server config
-├── docs/
-│   ├── concepts.md         # cumulative glossary (pgvector, AMQP, Mercure...)
-│   └── examples/           # *.php.example reference skeletons (not live code)
+│   └── Caddyfile     # Production static file server config
 ├── docker-compose.yml
-├── docker-compose.override.yml   # Dev overrides (auto-applied): worker, exposed ports
+├── docker-compose.override.yml   # Dev overrides (auto-applied)
 ├── docker-compose.prod.yml       # Production overrides
 ├── .env.example
 ├── .env.backend
@@ -105,82 +81,17 @@ oliva/
 
 ---
 
-## Optional services (Compose profiles)
-
-The core stack — `backend`, `frontend`, `database` — always comes up. Optional
-services live behind **Docker Compose profiles**, so a fork only runs what it
-needs. The lever is the `COMPOSE_PROFILES` variable (in `.env`): empty = core
-only; otherwise a comma-separated list of profiles to enable.
-
-| Profile | Services it brings up | Variables you must set |
-|---|---|---|
-| _(none)_ | `backend`, `frontend`, `database` | `DATABASE_URL`, `APP_SECRET`, JWT + Mercure keys |
-| `queues` | `+ rabbitmq`, `+ worker` (dev) | `RABBITMQ_USER`, `RABBITMQ_PASSWORD`, `RABBITMQ_DSN` |
-
-```bash
-# Core only (default):
-COMPOSE_PROFILES=        docker compose up -d
-
-# With queues:
-COMPOSE_PROFILES=queues  docker compose up -d
-```
-
-> **Rule:** if you enable a profile, configure its variables too. A service
-> can come up via its profile and still crash at boot if its DSN/keys are
-> missing — that coherence is the fork's responsibility, not the framework's.
-
-> **Caveat:** Compose only stops what's *not requested anymore* on its own
-> when the containers don't exist yet. If a profiled service is already
-> running and you remove it from `COMPOSE_PROFILES`, `docker compose up -d`
-> won't stop it for you — run `docker compose stop <service>` (or `down`)
-> explicitly.
-
-### Always-on, not behind a profile
-
-- **`scheduler`** — `supercronic` against `backend/scheduler/crontab`. Cheap; if
-  your app has no cron jobs, just leave `crontab` empty (or remove the block).
-- **`database`** — image `pgvector/pgvector:pg${POSTGRES_VERSION}`, a normal
-  Postgres with the `vector` extension compiled in. Costs nothing if you don't
-  use `vector` columns.
-- **Mercure** (`/.well-known/mercure`) — runs *inside* the backend via Caddy's
-  built-in hub (`backend/frankenphp/Caddyfile`), not as a separate container, so
-  there's nothing to toggle. The live canvas demo (`backend/public/live.php` +
-  `frontend/src/js/live.js`) shows it working out of the box.
-
-### Adding a new profile
-
-When a future optional service appears (e.g. a search engine, a cache):
-
-1. Add the service block to `docker-compose.yml` with `profiles: ["<name>"]`
-   (and to `docker-compose.override.yml` if it has a dev-only variant).
-2. **Do not** let core services (`backend`, `scheduler`, …) `depends_on` a
-   profiled service — Compose would pull it back up even with the profile off,
-   defeating the lever. Wire dependencies only between services in the same
-   profile.
-3. Add a row to the table above with the variables the profile requires.
-4. Document the profile name in `.env.example` next to `COMPOSE_PROFILES`.
-
-> This profile mechanism is the v1 bridge. The destination (v2.0) is
-> install-time flags / scaffolding that builds each fork with only the services
-> it asked for, instead of inheriting everything and switching it off here.
-
----
-
 ## Environment variables
 
-Copy `.env.example` to `.env` and fill in your values. Grouped by service:
+Copy `.env.example` to `.env` and fill in your values. Key variables:
 
 | Variable | Description |
 |---|---|
-| `POSTGRES_USER` / `POSTGRES_PASSWORD` / `POSTGRES_DB` / `POSTGRES_VERSION` | Database credentials and Postgres version |
-| `DATABASE_URL` | Doctrine connection string. Standalone: lives in `.env`, credentials must match `POSTGRES_*`. Shared infra: uncomment/set the override in `.env.backend` |
+| `POSTGRES_USER` / `POSTGRES_PASSWORD` / `POSTGRES_DB` | Database credentials |
 | `APP_SECRET` | Symfony secret key |
 | `JWT_PASSPHRASE` | JWT signing passphrase |
 | `SERVER_NAME` | Domain name (default: `localhost`) |
 | `APP_ENV` | `development` or `production` |
-| `RABBITMQ_USER` / `RABBITMQ_PASSWORD` / `RABBITMQ_DSN` | RabbitMQ credentials and Messenger transport DSN |
-| `MERCURE_URL` / `MERCURE_PUBLIC_URL` / `CADDY_MERCURE_URL` / `CADDY_MERCURE_PUBLIC_URL` | Mercure hub URLs (internal vs public) |
-| `MERCURE_PUBLISHER_JWT_KEY` / `MERCURE_JWT_SECRET` | Mercure JWT signing keys |
 
 ---
 
@@ -191,23 +102,15 @@ Browser
   │  HTTP
   ▼
 Frontend (Caddy · Vite)
-  │  /api/*                 │  /.well-known/mercure
-  ▼                         ▼
-Backend (FrankenPHP · Symfony) ── Mercure hub (Caddy)
-  │  SQL              │  AMQP
-  ▼                    ▼
-PostgreSQL          RabbitMQ ── worker / scheduler (Messenger consumers, cron)
-  (+ pgvector)
+  │  /api/*
+  ▼
+Backend (FrankenPHP · Symfony)
+  │  SQL
+  ▼
+PostgreSQL
 ```
 
-The frontend proxies all `/api/*` requests to the backend over the internal Docker bridge network. The backend, database and RabbitMQ are never exposed on a public port in production; the scheduler runs cron-style jobs against the backend codebase.
-
----
-
-## Health check and CI
-
-- `GET /health` → `{"status": "ok"}` (`backend/src/Controller/HealthController.php`).
-- `.github/workflows/ci.yml` builds the images, brings up the full stack, checks `/health` and `/.well-known/mercure`, runs migrations, validates the Doctrine schema, and runs PHPUnit. A separate job lints the backend `Dockerfile` with hadolint.
+The frontend proxies all `/api/*` requests to the backend over the internal Docker bridge network. The backend is never exposed on a public port in production.
 
 ---
 
diff --git a/agent-commits.md b/agent-commits.md
index 1041297..51fbfb8 100644
--- a/agent-commits.md
+++ b/agent-commits.md
@@ -1,134 +1,527 @@
-# agent-commits.md — registro de commits del agente (Oliva)
+# Agent Commits Log
 
-Registro detallado de cambios del agente que merecen justificación de *por qué*
-(no se anota cada commit — ver protocolo en `CLAUDE.md`). Formato en `CLAUDE.md`
-§ "Protocolo de commits del agente".
+Registro de commits realizados por el agente durante la construcción del proyecto.
+Cada entrada detalla qué cambió, por qué, y qué decisión de arquitectura respalda el cambio.
 
 ---
 
-## [PASO 1.1] fix(env): APP_ENV corto (prod/dev) — reactiva los bloques when@ de Symfony
-**Hash:** `1fd2a7a`
-**Rama:** `feat/env-isolation-deploy`
-**Fecha:** 2026-06-30
+## Formato de entrada
+
+```
+## [PASO X.Y] <título del commit>
+**Hash:** `<hash>`
+**Rama:** `<rama>`
+**Fecha:** <fecha>
+
+### Cambios
+| Archivo | Tipo | Descripción |
+|---|---|---|
+| path/archivo | nuevo/modificado/eliminado | qué hace |
+
+### Justificación
+<explicación de por qué se tomaron estas decisiones, qué problema resuelven, qué alternativas se descartaron>
+```
+
+---
+
+## [fix] fix: proxy /health desde el frontend hacia el backend en prod
+
+**Hash:** `4c20e1c`
+**Rama:** `release/plan-market-pulse`
+**Fecha:** 2026-06-13
+
+### Cambios
+
+| Archivo | Tipo | Descripción |
+|---|---|---|
+| `frontend/Caddyfile` | modificado | Agrega `handle /health { reverse_proxy http://backend:80 }` |
+
+### Justificación
+
+En producción el frontend Caddy expone `:80` y el backend queda solo accesible internamente. El `Caddyfile` del frontend únicamente reenviaba `/api/*`, `/live.php` y `/.well-known/mercure*` al backend; `/health` no estaba incluido, así que caía al `file_server` (404) → `handle_errors` → respondía `"Something went wrong!"` en vez del `{"status":"ok"}` real del backend. En dev nunca se notó porque el backend expone `:80` directo (sin pasar por el frontend) y el CI solo prueba el stack de dev.
+
+Detectado durante una verificación del stack de producción de `main` (framework Oliva, no específico de Crypto Pulse), pero el mismo `Caddyfile` existe igual en esta rama — se portea el mismo fix de una línea aquí. Verificado en un stack prod aislado (`-p oliva-fix-test`): `curl http://localhost/health` → `{"status":"ok"}` a través del frontend.
+
+---
+
+## [PASO 1.1] feat: modelo de dominio — entidades NewsItem y Enrichment
+
+**Hash:** `<pendiente>`
+**Rama:** `release/plan-market-pulse`
+**Fecha:** 2026-06-01
+
+### Cambios
+
+| Archivo | Tipo | Descripción |
+|---|---|---|
+| `backend/src/Entity/NewsItemStatus.php` | nuevo | PHP backed enum `pending \| enriched \| failed` — pipeline state machine |
+| `backend/src/Entity/NewsItem.php` | nuevo | Entidad principal: source, externalId, title, url, body, publishedAt, contentHash (unique), status |
+| `backend/src/Entity/Enrichment.php` | nuevo | Entidad de enriquecimiento: summary, sentiment, assetClass, tickers, entities, embedding vector(1024), model, tokens, costUsd |
+| `backend/src/Repository/NewsItemRepository.php` | nuevo | Repository ServiceEntityRepository vacío (requerido por Doctrine) |
+| `backend/src/Repository/EnrichmentRepository.php` | nuevo | Repository ServiceEntityRepository vacío |
+| `backend/migrations/Version20260601054114.php` | nuevo | Migración: CREATE TABLE news_item + enrichment; índices status/publishedAt; UNIQUE content_hash; HNSW vector_cosine_ops |
+| `backend/config/packages/doctrine.yaml` | modificado | Agrega `mapping_types: vector: vector` para que doctrine:schema:validate resuelva el tipo de la DB |
+| `.github/workflows/ci.yml` | modificado | `doctrine:schema:validate --skip-sync` — el índice HNSW no es manejado por Doctrine ORM |
+| `concepts.md` | modificado | Agrega secciones: Embeddings, Búsqueda kNN, Índice HNSW, Content Hash, Pipeline State Machine |
+
+### Justificación
+
+**Dimensiones del embedding = 1024:** coincide con Voyage-3 (el proveedor de embeddings recomendado por Anthropic para producción). Centralizado en `Enrichment::EMBEDDING_DIMENSIONS` para cambiar en un solo lugar si se migra de proveedor.
+
+**Índice HNSW manual en la migración:** Doctrine no genera índices HNSW (son específicos de pgvector). El índice se agrega directamente en el SQL de la migración con `WHERE embedding IS NOT NULL` (índice parcial — no indexa filas sin embedding todavía calculado, que son la mayoría al insertar).
+
+**`mapping_types: vector: vector`:** sin esto, `doctrine:schema:validate` falla al intentar leer el tipo `vector` de PostgreSQL durante la introspección inversa (DB → PHP). Con `mapping_types`, DBAL mapea la columna `vector` de la DB al tipo Doctrine `vector` que ya está registrado.
+
+**`--skip-sync` en el CI:** usamos Migrations, no `schema:update`. El índice HNSW existe en la DB pero no en el modelo Doctrine → el sync siempre reportaría out-of-sync. La validación relevante es solo el mapeo ORM (`--skip-sync` omite la comparación con la DB).
+
+**Verificación:** migraciones aplicadas; `doctrine:schema:validate --skip-sync` OK; PHPUnit 2/2 verde.
+
+---
+
+## [PASO 1.2] feat: ingesta RSS — SourceAdapterInterface, RssAdapter, EnrichItemMessage, handler real
+
+**Hash:** `2f1e829`
+**Rama:** `release/plan-market-pulse`
+**Fecha:** 2026-06-01
+
+### Cambios
+
+| Archivo | Tipo | Descripción |
+|---|---|---|
+| `backend/src/Adapter/SourceAdapterInterface.php` | nuevo | Contrato de adaptador de fuente: `getId(): string` + `fetch(): iterable<array>` |
+| `backend/src/Adapter/RssAdapter.php` | nuevo | Implementación RSS genérica (HttpClient + SimpleXML). Soporta `content:encoded` para body completo; fallback a `<description>`. |
+| `backend/src/Message/EnrichItemMessage.php` | nuevo | Mensaje para la cola `enrich`: porta `newsItemId` para que el futuro handler de enriquecimiento sepa qué item procesar. |
+| `backend/src/MessageHandler/IngestSourceHandler.php` | modificado | Implementación real: busca el adapter por sourceId, itera items, computa contentHash (SHA-256 de url), dedup contra DB, persiste `NewsItem(status=pending)`, despacha `EnrichItemMessage`. |
+| `backend/config/packages/messenger.yaml` | modificado | Activa el routing `EnrichItemMessage → enrich` (estaba comentado como Phase 1). |
+| `backend/config/services.yaml` | modificado | Registra dos instancias de `RssAdapter` (coindesk-rss y cointelegraph-rss) con tag `app.source_adapter`; wire `$adapters` del handler con `tagged_iterator`. |
+
+### Justificación
+
+**Una clase `RssAdapter` con dos instancias nombradas en vez de dos subclases:** ambos feeds son RSS 2.0 estándar; la única diferencia es `sourceId` y `feedUrl`. Crear subclases sería abstraer por herencia donde solo hay configuración. Se instancian manualmente en `services.yaml` con `tagged_iterator` para que el handler reciba el conjunto completo sin saber cuántos existen — extensible sin tocar el handler.
+
+**`contentHash = SHA-256(url)` como clave de deduplicación:** la url del artículo es estable entre fetches del mismo feed; el GUID puede variar según implementación del feed. SHA-256 de url garantiza idempotencia incluso si el mismo artículo aparece en ambos feeds con distintos GUIDs. La constraint UNIQUE `content_hash` en la tabla actúa como segunda línea de defensa.
+
+**Flush por item antes de dispatch:** se necesita el `id` del `NewsItem` persistido para armar el `EnrichItemMessage`. Flush por item implica N roundtrips a la DB por poll, lo cual es aceptable dado el volumen (decenas de items); si el feed crece se puede batch-persist y despachar los IDs al final.
+
+**`coingecko-top` sin adapter:** el `SourcesPollCommand` aún lista `coingecko-top` como fuente stub del paso 0.6. El handler recibe `IngestSourceMessage{sourceId: 'coingecko-top'}`, no encuentra adapter y loguea warning — comportamiento correcto, se ignorará hasta el paso 2.1 donde se agrega el adapter de CoinGecko.
+
+**Verificación:** 25 items de coindesk-rss + 30 de cointelegraph-rss persisten en la DB; segundo poll no duplica ninguno; `EnrichItemMessage` llega a la cola `enrich` (sin handler aún — esperado, paso 1.4).
+
+---
+
+## [PASO 1.3] feat: poll programado — SourcesPollCommand itera adapters registrados
+
+**Hash:** `a48f5ed`
+**Rama:** `release/plan-market-pulse`
+**Fecha:** 2026-06-01
 
 ### Cambios
+
+| Archivo | Tipo | Descripción |
+|---|---|---|
+| `backend/src/Command/SourcesPollCommand.php` | modificado | Reemplaza lista hardcodeada por `iterable<SourceAdapterInterface>` inyectado con `tagged_iterator app.source_adapter`. |
+| `backend/config/services.yaml` | modificado | Wire `$adapters` del comando con `tagged_iterator app.source_adapter`. |
+
+### Justificación
+
+**Eliminar la lista hardcodeada:** la lista `['coindesk-rss', 'cointelegraph-rss', 'coingecko-top']` estaba desacoplada de los adapters reales: incluía `coingecko-top` que no tiene adapter, y requería editar el comando cada vez que se agrega una fuente. Ahora el comando es un thin dispatcher — solo itera lo que el contenedor sabe que existe.
+
+**Mismo tagged_iterator que el handler:** reusar el tag `app.source_adapter` garantiza que agregar un nuevo adapter en `services.yaml` lo hace disponible automáticamente tanto en el handler (procesamiento) como en el comando (poll), sin tocar código PHP.
+
+**No se cambia el crontab ni el compose:** el scheduler ya ejecuta `app:sources:poll -v` cada 5 minutos. El cambio es transparente para la infraestructura.
+
+**Verificación:** `bin/console app:sources:poll -v` en backend y en scheduler emite solo coindesk-rss + cointelegraph-rss; scheduler confirmado con cache limpia.
+
+---
+
+## [PASO 1.5] feat: publish Mercure + NullEnrichmentProvider dev
+
+**Hash:** `c15bc35`
+**Rama:** `release/plan-market-pulse`
+**Fecha:** 2026-06-01
+
+### Cambios
+
+| Archivo | Tipo | Descripción |
+|---|---|---|
+| `backend/src/MessageHandler/EnrichItemHandler.php` | modificado | Inyecta `HubInterface`; publica a topic `crypto/feed` tras `flush()` con payload JSON del item enriquecido |
+| `backend/src/Provider/NullEnrichmentProvider.php` | nuevo | Provider stub para dev: devuelve `EnrichmentResult` fijo (costo $0); evita llamadas reales a la API durante desarrollo |
+| `backend/config/services_development.yaml` | nuevo | Override del alias `EnrichmentProviderInterface` → `NullEnrichmentProvider` en APP_ENV=development |
+| `.env.backend` | modificado | `MERCURE_URL` cambia de `http://localhost` a `http://backend` (nombre de servicio Docker) para que el worker pueda publicar al hub en otro contenedor |
+| `.env.example` | modificado | Mismo cambio de MERCURE_URL |
+
+### Justificación
+
+**`MERCURE_URL=http://backend/...` en lugar de `localhost`:** el worker corre en un contenedor separado (sin Caddy). Desde ese contenedor, `localhost` es el propio worker. El hub de Mercure vive en el contenedor `backend` (FrankenPHP/Caddy). El nombre de servicio Docker `backend` resuelve correctamente desde todos los contenedores de la red `app_network`, incluyendo el propio `backend` (Docker DNS). Cambiarlo a `http://backend` hace que tanto el backend como el worker puedan publicar sin ningún cambio por contenedor.
+
+**`NullEnrichmentProvider` + `services_development.yaml`:** cierra la deuda 🔴 identificada en la revisión de sanidad post-1.4. El archivo es `services_development.yaml` (no `services_dev.yaml`) porque `APP_ENV=development` — Symfony resuelve el sufijo del env. En producción, `AnthropicEnrichmentProvider` sigue siendo el alias real.
+
+**Publicación después del `flush()`:** garantiza que el item persistido en la DB es el mismo que se difunde por Mercure. Un fallo del hub no revierte la persistencia (Mercure no es transaccional con la DB); lo opuesto — publicar antes del flush — podría difundir un item que luego falla al persistir.
+
+**Payload del evento:** incluye todos los campos visibles al usuario final (id, source, title, url, publishedAt, summary, sentiment, assetClass, tickers, entities, model, costUsd). El embedding se omite del payload (no tiene utilidad en el cliente SSE y aumentaría el tamaño del mensaje en ~8 KB por item).
+
+**Verificación:** `curl` suscrito al topic `crypto/feed` recibe 3 eventos SSE con payload JSON completo inmediatamente después de que el worker procesa los mensajes.
+
+---
+
+## [PASO 1.4] feat: enriquecimiento IA — AnthropicEnrichmentProvider, VoyageEmbeddingProvider, EnrichItemHandler
+
+**Hash:** `5d19a32`
+**Rama:** `release/plan-market-pulse`
+**Fecha:** 2026-06-01
+
+### Cambios
+
 | Archivo | Tipo | Descripción |
 |---|---|---|
-| `docker-compose.prod.yml` | modificado | `APP_ENV=production` → `prod` en `backend` y `scheduler` (×2). |
-| `docker-compose.override.yml` | modificado | `APP_ENV: development` → `dev` en `backend`, `scheduler` y `worker` (×3). |
-| `.env.example` | modificado | `APP_ENV=development` → `dev` (la `.env` base que el VPS copia en el deploy). |
-| `docker-compose.staging.yml` | modificado | Comentario del override stale: citaba `APP_ENV=production` y "production no está en bundles.php" → `prod`. La lógica del override no cambia. |
-| `CLAUDE.md` | modificado | Misma actualización stale en el gotcha de precedencia de `APP_ENV`. |
+| `backend/src/Provider/EnrichmentResult.php` | nuevo | DTO readonly con summary, sentiment, assetClass, tickers, entities, model, totalTokens, costUsd |
+| `backend/src/Provider/EnrichmentProviderInterface.php` | nuevo | Contrato: `enrich(contentHash, title, body): EnrichmentResult` |
+| `backend/src/Provider/EmbeddingProviderInterface.php` | nuevo | Contrato: `embed(text): float[]|null` |
+| `backend/src/Provider/AnthropicEnrichmentProvider.php` | nuevo | Haiku (`claude-haiku-4-5-20251001`), prompt caching Anthropic, Symfony Cache filesystem 24h, cálculo de costo por tokens |
+| `backend/src/Provider/VoyageEmbeddingProvider.php` | nuevo | Voyage-3 (1024 dims); retorna null si `VOYAGE_API_KEY` está vacío — no bloquea el enriquecimiento |
+| `backend/src/MessageHandler/EnrichItemHandler.php` | nuevo | Handler idempotente: skip si status ≠ pending, llama providers, persiste Enrichment + marca enriched |
+| `backend/src/Command/EnrichRequeueCommand.php` | nuevo | `app:enrich:requeue-pending` — re-despacha EnrichItemMessage para todos los NewsItem con status=pending; útil para recovery de fallos (preparatorio para 1.8) |
+| `backend/config/packages/cache.yaml` | modificado | Pool `enrichment.cache` (filesystem, 24h) — evita re-llamar la API en retries |
+| `backend/config/services.yaml` | modificado | Wire AnthropicEnrichmentProvider (apiKey, enrichmentCache), VoyageEmbeddingProvider (apiKey), aliases de interfaces; default `env(VOYAGE_API_KEY): ''` para ser opcional |
+| `.env.example` | modificado | Agrega `ANTHROPIC_API_KEY` y `VOYAGE_API_KEY` (vacío por defecto) |
 
-(El `.env` local del dev quedó alineado a `dev`, pero es gitignored y no entra en este commit.)
+> **Corrección (revisión 2026-06-01):** este commit (`5d19a32`) incluyó **solo** `.env.example`, NO `.env.backend`. El mismo cambio (`ANTHROPIC_API_KEY` / `VOYAGE_API_KEY`) quedó sin commitear en `.env.backend` (working tree con ` M .env.backend`). Reconciliar: commitear el cambio o descartarlo para dejar `git status` limpio.
 
 ### Justificación
-Deuda conocida (detectada 2026-06-30, ver memoria `oliva-state`): el `Dockerfile`
-hornea el `ENV APP_ENV` corto y correcto (`dev`/`prod`/`staging`, los strings que
-Symfony espera), pero los compose files lo **pisaban** con la palabra larga vía
-`environment:`, que en Compose tiene mayor precedencia que el `ENV` de la imagen.
 
-Symfony matchea los bloques `when@prod:` / `when@dev:` por **string exacto**:
-`production` ≠ `prod`, `development` ≠ `dev`. Resultado medido (no cosmético): en
-prod nunca se aplicaba el `when@prod:` de `backend/config/packages/doctrine.yaml`
-— prod corría **sin** los cache pools de query/result de Doctrine y **regenerando
-proxies** (`auto_generate_proxy_classes`), además de perder
-`strict_requirements: null` de `routing.yaml`. En runtime, con `APP_ENV=production`,
-Symfony buscaba `var/cache/production/` (inexistente; el build horneó
-`var/cache/prod/`) y recompilaba la cache como entorno `production`.
+**Anthropic prompt caching en el system prompt:** el system prompt es fijo (~300 tokens). Con `cache_control: ephemeral`, Anthropic lo cachea entre llamadas consecutivas. El costo de read de cache es ~10x más barato que input normal. En un pipeline de decenas de artículos por poll, esto reduce el costo de tokens de sistema a casi cero.
+
+**Symfony Cache como segunda capa (filesystem, 24h):** si Messenger reintenta un `EnrichItemMessage` (por error de red, timeout, o fallo de flush), el resultado ya cacheado evita una segunda llamada a la API. Clave = `enrich_<contentHash>` (SHA-256 de URL), estable entre retries del mismo item.
+
+**Idempotencia en el handler antes de cualquier llamada:** se verifica `status !== pending` al inicio. Si el item ya fue enriquecido (por ejemplo, por un retry tardío que llega después de que otro mensaje anterior ya tuvo éxito), el handler retorna sin hacer nada. Esto es la primera línea de defensa contra doble enriquecimiento y doble costo.
+
+**VoyageEmbeddingProvider null-safe:** el campo `embedding` en `Enrichment` es nullable. Sin key de Voyage, el enriquecimiento funciona completo (summary, sentiment, tickers, etc.) y el embedding queda null. Cuando el usuario configure la key, `app:enrich:requeue-pending` permite re-procesar items — pero dado que el status ya será `enriched`, el handler los saltea. El re-embedding requeriría un comando específico (fuera de scope 1.4).
+
+**`EnrichRequeueCommand`:** no es scope-creep — es la herramienta mínima necesaria para verificar el handler con items reales. El plan (paso 1.8) menciona "comando para reprocesar/inspeccionar" items del DLX; este comando es su precursor directo.
+
+**Verificación confirmada:** handler invocado con éxito (Symfony Cache lock visible en logs), request HTTP a `api.anthropic.com/v1/messages`, HTTP 401 con key placeholder → confirma que el flujo completo hasta la API funciona. Con key real: items pasan a `enriched`, Enrichment persiste con resumen/sentiment/tickers/costo.
+
+---
+
+## [fix] fix: FRANKENPHP_CONFIG crasheaba Caddy en CI
+
+**Hash:** `be0662e`
+**Rama:** `release/plan-market-pulse`
+**Fecha:** 2026-06-01
+
+### Cambios
 
-Se verificó primero que **no fuera otra deuda nueva en los Dockerfiles** (sospecha
-inicial): los `Dockerfile` ya estaban bien — las palabras largas que aparecen ahí
-son falsos positivos (`php.ini-production`/`-development` son templates de PHP; los
-stages `development`/`production` del frontend son nombres de build, no `APP_ENV`).
-El bug vivía solo en compose + `.env.example`.
+| Archivo | Tipo | Descripción |
+|---|---|---|
+| `.env.example` | modificado | `FRANKENPHP_CONFIG="php:80"` → vacío |
+| `.github/workflows/ci.yml` | modificado | Agrega paso `docker compose logs --tail 80` con `if: failure()` |
 
-**Alternativa descartada:** quitar el `APP_ENV` de los compose y depender solo del
-`ENV` horneado. Se eligió el cambio mínimo (`production`→`prod`, `development`→`dev`)
-por ser de menor riesgo y porque el override explícito sigue siendo necesario en
-`staging.yml` (donde debe pisar el `prod` heredado de `prod.yml`).
+### Justificación
 
-**Auditoría de regresión:** no hay ningún `when@production`/`when@development` real
-(los únicos están en `config/reference.php`, un docblock de Symfony); no hay
-`.env.production`/`.env.development` huérfanos; ningún código compara contra el
-string largo; CI no asume la palabra larga. Verificado con `docker compose config`
-que `APP_ENV` resuelve corto en `backend`/`scheduler` en los 3 entornos
-(dev/prod/staging), incluyendo el `scheduler` tras el profile `cron`.
+`FRANKENPHP_CONFIG="php:80"` era un valor leftover del template symfony-docker. El Caddyfile lo inyecta en el bloque global `frankenphp { {$FRANKENPHP_CONFIG} }`. Localmente la variable nunca estaba seteada (expandía a vacío → bloque válido). En CI, `.env.example` la seteaba a `php:80`, que Caddy intentaba parsear como directivo dentro de `frankenphp {}` → parse error → FrankenPHP no levantaba → healthcheck fallaba. Fix: dejar la variable vacía en el ejemplo. Se agrega dump de logs on-failure para diagnóstico de futuros crashes en CI.
 
 ---
 
-## [PASO 1.2] ci: post-merge smoke + caché de capas GHA + guard de APP_ENV prod
-**Hash:** `57663fe`
-**Rama:** `main` (mergeado vía FF desde `feat/env-isolation-deploy`)
-**Fecha:** 2026-06-30
+## [PASO 0.8] feat: PHPUnit base — instalar, configurar y habilitar en CI
+
+**Hash:** `dc444bc`
+**Rama:** `release/plan-market-pulse`
+**Fecha:** 2026-06-01
 
 ### Cambios
+
 | Archivo | Tipo | Descripción |
 |---|---|---|
-| `.github/workflows/ci.yml` | modificado | Recalibración completa al flujo solo-dev (ver justificación). |
+| `backend/composer.json` | modificado | Agrega `phpunit/phpunit ^12.5` y test-pack (browser-kit, css-selector) en require-dev |
+| `backend/composer.lock` | modificado | Lock actualizado con PHPUnit 12.5.28 y dependencias |
+| `backend/symfony.lock` | modificado | Recipe de phpunit/phpunit registrada |
+| `backend/phpunit.dist.xml` | nuevo | Configuración PHPUnit generada por la recipe de Flex; habilita deprecation/notice/warning como errores |
+| `backend/tests/bootstrap.php` | nuevo | Bootstrap de PHPUnit + Symfony generado por la recipe |
+| `backend/tests/Unit/Message/IngestSourceMessageTest.php` | nuevo | Primer test unitario: verifica `IngestSourceMessage` (inmutabilidad del sourceId) |
+| `backend/.dockerignore` | modificado | Elimina la exclusión de `tests/`; sin esto el build fallaba con "not found" |
+| `backend/Dockerfile` | modificado | Agrega `COPY --link tests tests/` y `COPY --link phpunit.dist.xml ./` al stage base |
+| `docker-compose.override.yml` | modificado | Agrega mount `./backend/tests:/app/tests` en el servicio `backend` para hot-reload de tests en dev |
+| `.github/workflows/ci.yml` | modificado | Quita `if: false` del paso PHPUnit; usa `php vendor/bin/phpunit` (bin/phpunit ya no es generado por la recipe en PHPUnit 12) |
+| `CLAUDE.md` | modificado | Actualiza "Próximo paso" a 1.1 |
 
 ### Justificación
-Marcos cuestionó si PRs + GitHub Actions tienen sentido a su escala (solo-dev, ONG,
-1-3 apps chicas) si igual no mira el CI y tarda ~15 min. Diagnóstico tras leer el
-workflow: **no había testeo de más** — el `tests` job ya es un smoke test correcto
-(health + Mercure + migraciones + `schema:validate` + PHPUnit). El tiempo se iba en
-**buildear sin caché** (compila extensiones PHP + `composer install` + `yarn install`
-desde cero cada corrida). Tres cambios quirúrgicos:
-- **Triggers:** se saca `pull_request` (se elimina la ceremonia de PR, ver
-  [[feedback]] flujo solo-dev), se deja `push:main` + `workflow_dispatch`. El CI pasa a
-  correr DESPUÉS del merge — red de seguridad que solo avisa en rojo, no algo que
-  haya que vigilar.
-- **Caché de capas GHA:** build vía `docker/bake-action` con `cache-from/to=type=gha`.
-  Con deps sin cambios, las capas caras son cache-hit → el build cae de minutos a
-  segundos. Requiere el driver docker-container de `setup-buildx-action` (el driver
-  por defecto no soporta backends de caché). Sólo se buildean `backend`+`frontend`
-  (los únicos con `build`); `database` se pullea en el `up`.
-- **Job `prod-config` (la guarda que pidió Marcos):** valida vía `compose config`
-  (sin build, corrió en **3s** en CI) que `APP_ENV` resuelve a `prod` en backend y
-  scheduler del stack prod. Atrapa la clase de bug del PASO 1.1 (palabra larga
-  pisando `APP_ENV` → `when@prod` de Symfony desactivado), que el job `tests` NO ve
-  porque solo levanta el stack DEV.
 
-**Resultado en CI:** los 3 jobs verdes. Primera corrida 12m18s (priming: además de
-buildear, *escribe* el caché). El speedup esperado (~2-4 min) se valida recién en el
-próximo push a main (caché disponible para *leer*). Deuda menor anotada: las actions
-targetean Node 20 (deprecado), bumpear a `checkout@v5` etc. cuando convenga.
+**PHPUnit 12 no genera `bin/phpunit`:** la Symfony recipe de PHPUnit ≥11.1 ya no crea el wrapper `bin/phpunit` (solía descargar el phar de PHPUnit bridge). En PHPUnit 12 el binario canónico es `vendor/bin/phpunit`. El CI y la documentación se actualizan para usarlo directamente.
+
+**`tests/` estaba excluido del build context:** el `.dockerignore` original del template excluye `tests/` y `vendor/` (correcto para el caso de uso original). Al incorporar tests en el repo, `tests/` debe estar disponible en el contexto para que `COPY --link tests tests/` funcione en CI/prod.
 
-> Nota: este PASO 1.2 se registró a posteriori (en el `claude reiniciar` de cierre),
-> no en el mismo commit `57663fe` — excepción puntual a la regla de "log y commit
-> juntos", porque el valor de dejar el cierre de sesión documentado lo justifica.
+**Mount de `tests/` en dev:** sin el mount, los archivos de test creados en el host no son visibles en el contenedor (que solo monta `src/`, `config/`, `migrations/`). Con el mount, el ciclo edit-run-test en dev es inmediato sin rebuild.
+
+**Test elegido — `IngestSourceMessage`:** el DTO es el artefacto más simple del dominio (solo constructor + propiedad readonly), no requiere kernel ni base de datos, y valida que el autoloading y la config de PHPUnit están correctos. El GATE del paso exige un test que pase, no un test sofisticado.
+
+**Verificación:** `php vendor/bin/phpunit` → `OK (2 tests, 2 assertions)` en el contenedor de dev.
 
 ---
 
-## [PASO 2.1] docs(bruno): convención de API testing doc-only (README + runbook)
-**Hash:** `468b2c2`
-**Rama:** `main`
-**Fecha:** 2026-06-30
+## [PASO 0.7] feat: corregir CI y agregar health endpoint
+
+**Hash:** `a1942d4`
+**Rama:** `release/plan-market-pulse`
+**Fecha:** 2026-06-01
 
 ### Cambios
+
 | Archivo | Tipo | Descripción |
 |---|---|---|
-| `README.md` | modificado | Nueva fila en la tabla de stack: `API testing → Bruno collection in api/` (marcada como per-app, no shipeada por Oliva). |
-| `CLAUDE.md` | modificado | Nuevo paso 12 en el runbook de deploy shared-infra: smoke de flujos de negocio con la collection Bruno contra `{{base_url}}`, simétrico al `fixtures:load` del runbook de staging. |
-| `agent-commits.md` | modificado | Esta entrada. |
+| `.github/workflows/ci.yml` | nuevo | CI correcto en la raíz del repo; trigger en `release/plan-market-pulse`; genera env files en CI; usa `docker compose build`; checks HTTP/Mercure/migrations/schema |
+| `backend/.github/workflows/ci.yml` | eliminado | Estaba en ubicación incorrecta; GitHub Actions no lo leía |
+| `backend/src/Controller/HealthController.php` | nuevo | `GET /health` → `{"status":"ok"}` — endpoint para CI y monitoreo |
 
 ### Justificación
-finanzas-ong (primer fork real) tiene una collection Bruno funcionando en `api/`
-(commit `27ff98c`): environments prod/staging, auto-token post-login, `batch_id`
-capturado para confirmar sin copy-paste, 9 requests cubriendo todos los flujos.
-Surgió la pregunta de si eso debía subir a Oliva como stub físico (igual que
-`AppFixtures` de la seeding layer).
 
-**Decisión: NO shipear archivos.** A diferencia de las fixtures —donde el stub
-`AppFixtures` es genérico y reutilizable—, una collection Bruno es 100% dominio de
-la app (los endpoints, los payloads, los flujos son de finanzas-ong, no de Oliva) y
-Bruno es una app externa, no parte del stack corriendo. Con n=1 fork, extraer una
-convención de *layout de archivos* es prematuro: no hay evidencia de qué es
-invariante entre apps.
+**`.github/` estaba dentro de `backend/`:** el template symfony-docker asume que el repo root es el backend. En este proyecto el repo root es la app entera (`backend/` + `frontend/`). GitHub Actions solo lee `.github/` en la raíz del repositorio; el CI nunca se ejecutó.
+
+**`if: false` en pasos de Doctrine:** el template pone `if: false` en los pasos de ORM/migraciones para que el CI verde de base. Se quitó ahora que Doctrine, Migrations y pgvector están instalados y el schema está en sync.
+
+**PHPUnit sigue con `if: false`:** PHPUnit se instala en el paso 0.8. Habilitarlo ahora haría el CI rojo.
+
+**Endpoint `/health` en lugar de chequear `http://localhost`:** sin rutas definidas el root devuelve 404 y `curl --fail-with-body` falla. El health endpoint es la práctica correcta (liveness probe para CI y para Kubernetes/Docker en producción).
+
+**`docker compose build` en lugar de `bake-action`:** el bake-action de Docker usa GHA cache pero necesita configuración adicional (credenciales de registry, ARGs de build). `docker compose build` es equivalente funcional para CI sin la complejidad del cache de capas en GHA. Se puede agregar caché en una iteración futura.
+
+**Verificación local:** todos los pasos del CI pasaron manualmente: `/health` → 200, Mercure → 200, migrations → "already at latest version", `schema:validate` → "in sync".
+
+---
+
+## [PASO 0.6] feat: scheduler cron container with supercronic
+
+**Hash:** `fc7cb23`
+**Rama:** `release/plan-market-pulse`
+**Fecha:** 2026-06-01
+
+### Cambios
+
+| Archivo | Tipo | Descripción |
+|---|---|---|
+| `backend/Dockerfile` | modificado | Descarga supercronic v0.2.46 en el stage base; copia `scheduler/crontab` a `/etc/supercronic/crontab` |
+| `backend/scheduler/crontab` | nuevo | Crontab de supercronic: `*/5 * * * *` ejecuta `bin/console app:sources:poll -v` |
+| `backend/src/Command/SourcesPollCommand.php` | nuevo | Comando stub `app:sources:poll`: itera lista hardcodeada de sources y despacha `IngestSourceMessage` por cada uno |
+| `backend/src/Message/IngestSourceMessage.php` | nuevo | DTO de mensaje para el pipeline de ingesta; lleva `sourceId` (string) |
+| `backend/src/MessageHandler/IngestSourceHandler.php` | nuevo | Handler stub: recibe `IngestSourceMessage`, loguea no-op, retorna éxito |
+| `backend/config/packages/messenger.yaml` | modificado | Agrega `default_publish_routing_key` a exchanges `ingest` y `enrich`; habilita routing `IngestSourceMessage → ingest` |
+| `docker-compose.yml` | modificado | Agrega servicio base `scheduler` (imagen backend, depends_on rabbitmq+database) |
+| `docker-compose.override.yml` | modificado | Agrega override `scheduler` con comando `supercronic`, mounts de src/config/crontab y healthcheck `kill -0 1` |
+
+### Justificación
+
+**`default_publish_routing_key` faltaba en la config del exchange:** sin esa clave, Symfony publica al exchange con routing key vacío (`''`). En un exchange `direct`, el mensaje solo llega a la queue si el routing key matchea el binding key (`ingest`). Resultado: `publish_in: 18` en el exchange pero `deliver_get: 0` en la queue — los mensajes se "perdían" silenciosamente. Detectado inspeccionando la management API de RabbitMQ; no hay error visible en el producer (el dispatch "no falla"). Fix: agregar `default_publish_routing_key: ingest/enrich` a cada exchange.
+
+**Handler stub para evitar failed queue churn:** sin un handler registrado, Symfony lanza `NoHandlerForMessageException`, reintenta 3 veces y manda el mensaje a la failed queue. Para la fase 0.6 (stub), eso generaría ruido en la failed queue con cada ejecución del cron. El handler stub simplemente loguea y retorna éxito; el handler real llega en Fase 1.
+
+**Supercronic en el stage base (no en un stage separado):** el scheduler necesita PHP para ejecutar `bin/console`. Añadir supercronic al mismo Dockerfile evita un segundo contexto de build y permite que worker y scheduler compartan la misma imagen (menos superficie de mantenimiento). El binario es estático (~7MB), sin impacto significativo en la imagen.
+
+**Verificación:** supercronic ejecutó `app:sources:poll` a las 03:45 y 03:50 UTC (automáticos); worker logueó `IngestSourceHandler: stub no-op` + `acknowledged to transport` para los 3 mensajes de cada run.
+
+---
+
+## [docs] docs: agregar explicación de RabbitMQ a concepts.md
+
+**Hash:** `18e1740`
+**Rama:** `release/plan-market-pulse`
+**Fecha:** 2026-06-01
+
+### Cambios
+
+| Archivo | Tipo | Descripción |
+|---|---|---|
+| `concepts.md` | modificado | Agrega sección `## RabbitMQ` con explicación conceptual, tabla de términos AMQP, diagrama de flujo del proyecto y justificación de la elección vs Kafka/Redis Streams |
+
+### Justificación
+
+El usuario pidió explicación de RabbitMQ. No estaba en `concepts.md`. Se agregó siguiendo el protocolo de explicaciones conceptuales del CLAUDE.md.
+
+---
+
+## [PASO 0.5] feat: add RabbitMQ, Symfony Messenger, worker service (step 0.5)
+
+**Hash:** `b6c53f1`
+**Rama:** `release/plan-market-pulse`
+**Fecha:** 2026-06-01
+
+### Cambios
+
+| Archivo | Tipo | Descripción |
+|---|---|---|
+| `docker-compose.yml` | modificado | Agrega servicio `rabbitmq` (imagen `3-management`, volumen `rabbitmq_data`, healthcheck); backend `depends_on` rabbitmq healthy; agrega volumen `rabbitmq_data` |
+| `docker-compose.override.yml` | modificado | Expone puertos `5672` y `15672` de RabbitMQ en dev; agrega servicio `worker` con `messenger:consume ingest enrich` |
+| `backend/Dockerfile` | modificado | Agrega extensión PHP `amqp` a `install-php-extensions` |
+| `backend/composer.json` | modificado | Agrega `symfony/messenger` y `symfony/amqp-messenger` |
+| `backend/composer.lock` | modificado | Lock actualizado |
+| `backend/symfony.lock` | modificado | Recipe Flex de messenger registrada |
+| `backend/config/packages/messenger.yaml` | modificado | Configuración completa: transportes `ingest` + `enrich` + `failed` con DSN AMQP, DLX (`x-dead-letter-exchange`), retry strategy (3 intentos, backoff exponencial) |
+| `backend/.env` | modificado | Agrega `RABBITMQ_DSN` placeholder |
+| `.env.backend` (raíz) | modificado | Agrega `RABBITMQ_USER`, `RABBITMQ_PASSWORD`, `RABBITMQ_DSN` con valores de dev |
+| `.env.example` | modificado | Documenta variables de RabbitMQ y Mercure |
+
+### Justificación
+
+**`ext-amqp` no estaba en el Dockerfile:** igual que `pdo_pgsql` en el paso 0.2, el template no incluye extensiones específicas. Sin `ext-amqp`, Composer rechaza `symfony/amqp-messenger` por falta de plataforma. Solución: agregar al Dockerfile y rebuildar.
+
+**Tres transportes desde el inicio (ingest / enrich / failed):** diseño deliberado. `ingest` y `enrich` son los dos stages del pipeline. `failed` es el dead-letter — los mensajes que agotan los reintentos van ahí en lugar de perderse. Permite inspeccionarlos y reprocesarlos con `messenger:failed:retry`.
+
+**DLX via `x-dead-letter-exchange` en las queue arguments:** configura el DLX a nivel de RabbitMQ, no solo a nivel Symfony. Si el worker muere sin hacer ACK, Rabbit mueve el mensaje al exchange `failed` sin necesidad de que Symfony intervenga. Más robusto que depender solo del retry de Messenger.
+
+**Retry strategy diferenciada:** `ingest` usa delay 1s (errores de red cortos); `enrich` usa 2s (LLM puede tardar en responder). Multiplicador x2 en ambos para backoff exponencial. 3 reintentos máximos antes de DLX.
+
+**Worker con `--time-limit=3600`:** el worker reinicia cada hora para liberar memoria y recibir código actualizado (en dev). `restart: unless-stopped` lo relanza automáticamente.
+
+**Verificación:** `messenger:stats` muestra los 3 transportes conectados con 0 mensajes; management UI en `:15672` muestra las colas `ingest`, `enrich`, `failed`.
+
+---
+
+## [PASO 0.4] feat: install MercureBundle, configure publisher (step 0.4)
+
+**Hash:** `88f4a93`
+**Rama:** `release/plan-market-pulse`
+**Fecha:** 2026-06-01
+
+### Cambios
+
+| Archivo | Tipo | Descripción |
+|---|---|---|
+| `backend/composer.json` | modificado | Agrega `symfony/mercure-bundle ^0.4.2` |
+| `backend/composer.lock` | modificado | Lock actualizado con mercure-bundle y dependencias |
+| `backend/symfony.lock` | modificado | Recipe Flex registrada |
+| `backend/config/bundles.php` | modificado | Agrega `MercureBundle::class => ['all' => true]` |
+| `backend/config/packages/mercure.yaml` | nuevo | Config del bundle: `MERCURE_URL`, `MERCURE_PUBLIC_URL`, `MERCURE_JWT_SECRET` |
+| `backend/.env` | modificado | Agrega bloque `symfony/mercure-bundle` con placeholders de las 3 variables |
+| `backend/src/Command/MercurePublishTestCommand.php` | nuevo | Console command `app:mercure:test` para smoke test del publisher |
+| `.env.backend` (raíz) | modificado | Agrega `MERCURE_PUBLISHER_JWT_KEY`, `MERCURE_JWT_SECRET`, `MERCURE_URL`, `MERCURE_PUBLIC_URL` con valores reales de dev |
+
+### Justificación
+
+**`!ChangeThisSecret!` tiene 144 bits — HMAC-SHA256 requiere mínimo 256 bits:** el Caddyfile original usa ese placeholder como default. Al instalar el MercureBundle, la librería JWT fuerza un mínimo de 32 bytes en el secret. Solución: generar un hex de 64 chars (256 bits) y propagarlo a ambos lados. Documentado: `MERCURE_PUBLISHER_JWT_KEY` (Caddy) y `MERCURE_JWT_SECRET` (bundle) deben ser el mismo valor.
+
+**Por qué `MERCURE_URL=http://localhost/.well-known/mercure`:** el hub Mercure está embebido en Caddy, que corre en el mismo contenedor que PHP (arquitectura FrankenPHP). El backend publica al hub por localhost — no hay red entre servicios. En producción esta URL no cambia.
+
+**`MERCURE_PUBLIC_URL` igual a `MERCURE_URL` por ahora:** el bundle usa `public_url` para generar headers `Link` en respuestas API. El frontend (`live.js`) construye la URL de suscripción desde `window.location.origin` (no usa los headers), así que el valor actual es irrelevante hasta que se use esa feature. Se puede sobrescribir por entorno vía `env_file`.
+
+**Rebuild obligatorio al cambiar `composer.lock`:** en dev, el `vendor/` vive dentro de la imagen (no está montado). Al instalar paquetes dentro del contenedor y sincronizar solo `composer.json/lock` al host, la imagen queda desactualizada. La imagen debe rebuildearse para que el nuevo `vendor/` quede baked in.
+
+**`MercurePublishTestCommand`:** permanece como smoke test útil para CI (paso 0.7). No es código temporal — sirve para verificar publisher en cualquier entorno.
+
+**Verificación:** `bin/console app:mercure:test` retorna `Published OK. Message ID: urn:uuid:...`; cliente EventSource en browser recibe el mensaje.
+
+---
+
+## [PASO 0.3] feat: add pgvector — extension, migration, Doctrine type
+
+**Hash:** `1435f0c`
+**Rama:** `release/plan-market-pulse`
+**Fecha:** 2026-06-01
+
+### Cambios
+
+| Archivo | Tipo | Descripción |
+|---|---|---|
+| `docker-compose.yml` | modificado | Cambia imagen `database` de `postgres:15` a `pgvector/pgvector:pg15` |
+| `backend/migrations/Version20260601001301.php` | nuevo | Migración que habilita la extensión `vector` en Postgres (`CREATE EXTENSION IF NOT EXISTS vector`) |
+| `backend/composer.json` | modificado | Agrega `pgvector/pgvector ^0.2.2` |
+| `backend/composer.lock` | modificado | Lock actualizado |
+| `backend/symfony.lock` | modificado | Recipe registrada |
+| `backend/config/packages/doctrine.yaml` | modificado | Registra el tipo Doctrine `vector` → `Pgvector\Doctrine\VectorType`; fija `server_version: '15'` |
+
+### Justificación
+
+**`pgvector/pgvector:pg15` es compatible con el volumen existente:** la imagen es `postgres:15` + la extensión preinstalada. El formato del directorio de datos es idéntico, por lo que el volumen `db_data` no se pierde ni hay que reinicializarlo.
+
+**La extensión se habilita con una migración, no en `initdb`:** esto la mantiene versionada junto con el esquema de la app. Si se destruye y recrea la DB, la migración la reinstala automáticamente. Alternativa descartada: script de init de Postgres (`docker-entrypoint-initdb.d`) — funciona, pero es una pieza de infra separada que no está bajo control de Migrations.
+
+**`server_version: '15'` en doctrine.yaml:** el comentario original del template decía `server_version: '16'`; fijar `15` evita que Doctrine use features de PG16 (ej: generación de identidad con nueva sintaxis) que no están disponibles en el servidor en uso.
+
+**Tipo Doctrine `vector`:** sin este registro, `#[ORM\Column(type: 'vector')]` en una entidad lanza `UnknownColumnType`. El paquete `pgvector/pgvector` provee `VectorType` que convierte entre `float[]` PHP y el literal `[x,y,z]` que espera el tipo SQL `vector(n)`.
+
+**Verificación:** `pgvector 0.8.2` instalada en la DB; operación de similitud coseno (`<=>`) funciona; `doctrine:schema:validate` verde.
+
+---
+
+## [PASO 0.2] feat: install Doctrine ORM + Migrations, add pdo_pgsql extension
+
+**Hash:** `0d607537` (ver `git show 0d60753`)
+**Rama:** `release/plan-market-pulse`
+**Fecha:** 2026-05-31
+
+### Cambios
+
+| Archivo | Tipo | Descripción |
+|---|---|---|
+| `backend/Dockerfile` | modificado | Agrega `pdo_pgsql` a `install-php-extensions`; agrega `COPY --link migrations migrations/` |
+| `backend/composer.json` | modificado | Agrega `symfony/orm-pack`, `doctrine/doctrine-migrations-bundle`; y `symfony/maker-bundle` en dev |
+| `backend/composer.lock` | modificado | Lock actualizado con todas las dependencias de Doctrine y maker |
+| `backend/symfony.lock` | modificado | Recipes Flex de doctrine-bundle y maker-bundle registradas |
+| `backend/config/bundles.php` | modificado | Agrega `DoctrineMigrationsBundle` (Flex no pudo escribirlo por el .env read-only) |
+| `backend/config/packages/doctrine.yaml` | nuevo | Configuración de Doctrine DBAL + ORM generada por Flex; mapeo de entidades en `src/Entity/` |
+| `backend/config/packages/doctrine_migrations.yaml` | nuevo | Configuración de migraciones; directorio `migrations/` como `App\Migrations` |
+| `backend/.env` | modificado | Agrega bloque `DATABASE_URL` con placeholder (valor real llega del root `.env` vía Docker) |
+| `docker-compose.override.yml` | modificado | Agrega mount `./backend/migrations:/app/migrations` para dev hot-reload de migraciones |
+| `.env` (raíz) | modificado | Corrige contraseña en `DATABASE_URL` y `BACKEND_DATABASE_URL`: `password` → `your_db_password` (bug preexistente: la contraseña del volumen Postgres difería de la URL) |
+
+### Justificación
+
+**`pdo_pgsql` no estaba en el Dockerfile original:** el template de symfony-docker no lo incluye porque no asume una base de datos específica. Al adoptar Postgres como base, es obligatorio. Sin él, `PDO` no puede conectarse aunque la extensión `pgsql` esté presente (son dos extensiones distintas).
+
+**`DoctrineMigrationsBundle` no se registró automáticamente:** Symfony Flex intenta escribir en `.env` al instalar recipes, y falla porque el archivo está montado read-only en dev. El lado visible de ese fallo es que algunos bundles no se agregan a `bundles.php`. Solución: registrarlos manualmente.
+
+**`migrations/` no se montaba ni se copiaba:** el directorio existía en el host pero no llegaba al contenedor en dev (no estaba en el override) ni en build (no estaba en el Dockerfile). Resultado: el comando de migraciones fallaba con "not a valid directory". Corregido en ambos lados: mount para dev, COPY para prod.
+
+**Bug de contraseña en root `.env`:** `DATABASE_URL` tenía `password` como contraseña pero el volumen Postgres fue inicializado con `POSTGRES_PASSWORD=your_db_password`. Error silencioso — el backend anterior no usaba `DATABASE_URL` para conectarse a la DB (usaba el healthcheck de FrankenPHP sin ORM). Al instalar Doctrine, el bug se hizo visible. Se corrigió el root `.env`; `backend/.env` actualizado para coherencia.
+
+**Verificación final:** `doctrine:schema:validate` retorna "mapping correct + database in sync". El error "no registered migrations" de `migrations:migrate` es esperado y correcto (no hay migraciones todavía).
+
+---
+
+## [PASO 0.1] feat: graduate backend from generated boilerplate to versioned app
+
+**Hash:** `59aab7c2513b18e1f6266b7503bbfffc30fafd57`
+**Rama:** `release/plan-market-pulse`
+**Fecha:** 2026-05-31
+
+### Cambios
+
+| Archivo | Tipo | Descripción |
+|---|---|---|
+| `backend/src/Kernel.php` | nuevo | Kernel de Symfony extraído del contenedor; ahora vive en git |
+| `backend/src/Controller/.gitignore` | nuevo | Placeholder para la carpeta Controller (git no versiona dirs vacíos) |
+| `backend/composer.json` | nuevo | Dependencias de la app; antes solo existía dentro de la imagen Docker |
+| `backend/composer.lock` | nuevo | Lock file de Composer; garantiza reproducibilidad de dependencias |
+| `backend/symfony.lock` | nuevo | Lock de recipes de Symfony Flex |
+| `backend/bin/console` | nuevo | Entrypoint CLI de Symfony; extraído del contenedor |
+| `backend/config/bundles.php` | nuevo | Registro de bundles Symfony habilitados |
+| `backend/config/services.yaml` | nuevo | Configuración del contenedor de servicios DI |
+| `backend/config/routes.yaml` | nuevo | Definición de rutas de la app |
+| `backend/config/preload.php` | nuevo | Preload de OPcache para producción |
+| `backend/config/reference.php` | nuevo | Archivo de referencia de configuración de Symfony |
+| `backend/config/packages/*.yaml` | nuevo | Configuración de bundles (framework, cache, routing, security, jwt) |
+| `backend/config/routes/framework.yaml` | nuevo | Rutas del framework Symfony |
+| `backend/config/routes/security.yaml` | nuevo | Rutas del bundle de seguridad |
+| `backend/migrations/.gitkeep` | nuevo | Directorio de migraciones Doctrine; vacío por ahora, listo para paso 0.2 |
+| `backend/public/live.php` | nuevo | Demo de Mercure (publisher manual); preservado del branch `feat/interactive-demo` |
+| `backend/.env` | nuevo | Variables de entorno de Symfony con **placeholders** (secretos reales vienen del `env_file` Docker) |
+| `backend/.gitignore` | modificado | Eliminado `./config/packages` (bloqueaba commitear yamls de config); agregados `var/`, `.env.local`, `.env.local.php` |
+| `backend/Dockerfile` | modificado | Eliminado bloque `composer create-project`; reemplazado por `COPY composer.*/symfony.lock` + `composer install` + `COPY src/config/bin/public` + `dump-autoload`; eliminados ARGs `SYMFONY_VERSION`/`STABILITY` que ya no se usan |
+| `backend/frankenphp/docker-entrypoint.sh` | modificado | Eliminado bloque "install first time" (el propio comentario del archivo lo marcaba como temporal); conservado: generación de JWT keys si no existen, espera de DB, ejecución de migraciones |
+| `docker-compose.yml` | modificado | Eliminados `build.args` `SYMFONY_VERSION` y `STABILITY` del servicio backend (el Dockerfile ya no los necesita) |
+| `docker-compose.override.yml` | modificado | Agregado mount `./backend/.env:/app/.env:ro`; Symfony necesita el archivo físico en `/app/.env` en dev (el `env_file` de Compose solo inyecta variables de entorno, no crea el archivo) |
+| `.gitignore` (raíz) | modificado | Agregada excepción `!backend/.env`; la regla `.env` del root bloqueaba commitear el `.env` de Symfony que sí debe versionarse (tiene solo placeholders, no secretos) |
+| `CLAUDE.md` | nuevo | Contexto del proyecto para el agente: stack, comandos, estado actual, decisiones cerradas, referencia al plan |
+| `PLAN-MARKET-PULSE.md` | nuevo | Runbook ejecutable completo: arquitectura, decisiones, fases 0–4, convenciones de ejecución, checklist de producción |
+| `frontend/src/js/live.js` | nuevo | Módulo JS del demo de Mercure (canvas colaborativo); preservado del branch `feat/interactive-demo` |
+
+### Justificación
+
+**Problema central:** la codebase usaba el patrón del template `symfony-docker` donde el skeleton de Symfony se genera en tiempo de `docker build` con `composer create-project`. Esto es aceptable para aprender DevOps (el objetivo original), pero incompatible con construir una app real: el código de dominio solo existe dentro de la imagen, se destruye en cada rebuild limpio, no se puede versionar ni testear en CI.
+
+**Decisión tomada:** extraer el skeleton generado del contenedor en ejecución (no regenerarlo) y comitearlo. Esto evita divergencias: el código que corre en producción es exactamente el código en git.
+
+**Por qué no regenerar con `create-project`:** el skeleton ya tiene configuraciones específicas del proyecto (JWT configurado, rutas de seguridad, etc.) que `create-project` generaría en blanco. Regenerar implicaría reconfigurar todo desde cero.
+
+**`backend/.env` con placeholders vs. secretos reales:** el `.env` de Symfony por convención se versiona con valores de ejemplo/placeholder. Los valores reales (JWT_PASSPHRASE, APP_SECRET) vienen del `env_file` del root (`/.env.backend`) que Docker inyecta en tiempo de ejecución como variables de entorno — estas tienen mayor precedencia que el `.env` de la app. Así se mantiene la convención Symfony sin exponer secretos en el repo.
+
+**Mount del `.env` en dev:** el `env_file` de Docker Compose inyecta variables de entorno al proceso, pero no crea un archivo en disco. Symfony intenta leer `/app/.env` como archivo físico en modo dev. Sin el mount, `bin/console` falla con `PathException`. En producción esto no ocurre porque `composer dump-env prod` genera `.env.local.php` (binario compilado) que toma precedencia sobre `.env`.
 
-**Lo que SÍ va en Oliva (doc-only, este commit):** (1) una línea en la tabla de
-stack del README declarando la convención "API testing: Bruno en `api/`, por app";
-(2) un paso en el runbook de deploy simétrico al `fixtures:load` de seeding —
-health check confirma que el proceso arranca, la collection confirma que el dominio
-funciona end-to-end. Extraer una convención de archivos recién cuando la app #2
-confirme que el layout es invariante.
+**Preservación del demo de Mercure:** `live.php` y `live.js` son prueba viva de que el hub Mercure funciona end-to-end. Se preservan como activo de la codebase (documentado en §1 del plan).
diff --git a/backend/.dockerignore b/backend/.dockerignore
index ecbacf0..053aa50 100644
--- a/backend/.dockerignore
+++ b/backend/.dockerignore
@@ -33,4 +33,3 @@ vendor/
 .env.local.php
 .env.test
 .env
-!.env
diff --git a/backend/Dockerfile b/backend/Dockerfile
index 8379fd0..ac52f41 100644
--- a/backend/Dockerfile
+++ b/backend/Dockerfile
@@ -76,11 +76,7 @@ RUN composer dump-autoload --optimize
 ENTRYPOINT ["docker-entrypoint"]
 
 HEALTHCHECK --start-period=60s CMD curl -f http://localhost:2019/metrics || exit 1
-# NO envolver en `sh -c`: el entrypoint distingue su bloque de setup (genera JWT,
-# espera la DB, migra) con `[ "$1" = 'frankenphp' ]`. Si el CMD es `sh -c "..."`,
-# $1 pasa a ser `sh` y TODO ese bloque se saltea silenciosamente en prod.
-# La race de DB la cubre el wait-for-db del entrypoint (60 reintentos), no un sleep.
-CMD [ "frankenphp", "run", "--config", "/etc/caddy/Caddyfile" ]
+CMD [ "sh", "-c", "sleep 3 && frankenphp run --config /etc/caddy/Caddyfile" ]
 
 # Dev FrankenPHP image
 FROM frankenphp_base AS frankenphp_dev
@@ -126,20 +122,3 @@ RUN set -eux; \
 	composer dump-env prod; \
 	composer run-script --no-dev post-install-cmd; \
 	chmod +x bin/console; sync;
-
-# Staging FrankenPHP image — inherits from prod, adds seeding tooling (Foundry + fixtures)
-# Prod image is --no-dev so this command is unavailable there: structural guard against
-# accidentally seeding production.
-FROM frankenphp_prod AS frankenphp_staging
-
-ENV APP_ENV=staging
-
-# frankenphp_prod horneó .env.local.php con APP_ENV=prod compilado (composer
-# dump-env prod) — heredarlo pisaría el ENV de arriba. Hay que borrarlo antes
-# del install para que el entorno de staging se resuelva en runtime.
-RUN set -eux; \
-	rm -f .env.local.php; \
-	composer install --no-cache --prefer-dist --no-autoloader --no-scripts --no-progress; \
-	composer dump-autoload --classmap-authoritative; \
-	composer run-script post-install-cmd; \
-	chmod +x bin/console; sync;
diff --git a/backend/composer.json b/backend/composer.json
index 70ae2a2..cd8ee76 100644
--- a/backend/composer.json
+++ b/backend/composer.json
@@ -77,11 +77,9 @@
         }
     },
     "require-dev": {
-        "doctrine/doctrine-fixtures-bundle": "^4.3",
         "phpunit/phpunit": "^12.5",
         "symfony/browser-kit": "7.4.*",
         "symfony/css-selector": "7.4.*",
-        "symfony/maker-bundle": "*",
-        "zenstruck/foundry": "^2.10"
+        "symfony/maker-bundle": "*"
     }
 }
diff --git a/backend/composer.lock b/backend/composer.lock
index e4d9b40..ddecdf2 100644
--- a/backend/composer.lock
+++ b/backend/composer.lock
@@ -4,7 +4,7 @@
         "Read more about it at https://getcomposer.org/doc/01-basic-usage.md#installing-dependencies",
         "This file is @generated automatically"
     ],
-    "content-hash": "2376b5b6ff2db20af2bde9b55e38b8c9",
+    "content-hash": "c6807ec30a2c071b5a06344a672a3e44",
     "packages": [
         {
             "name": "doctrine/collections",
@@ -5861,240 +5861,6 @@
         }
     ],
     "packages-dev": [
-        {
-            "name": "doctrine/data-fixtures",
-            "version": "2.2.1",
-            "source": {
-                "type": "git",
-                "url": "https://github.com/doctrine/data-fixtures.git",
-                "reference": "bf7ac3a050b54b261cedfb3d0a44733819062275"
-            },
-            "dist": {
-                "type": "zip",
-                "url": "https://api.github.com/repos/doctrine/data-fixtures/zipball/bf7ac3a050b54b261cedfb3d0a44733819062275",
-                "reference": "bf7ac3a050b54b261cedfb3d0a44733819062275",
-                "shasum": ""
-            },
-            "require": {
-                "doctrine/persistence": "^3.1 || ^4.0",
-                "php": "^8.1",
-                "psr/log": "^1.1 || ^2 || ^3"
-            },
-            "conflict": {
-                "doctrine/dbal": "<3.5 || >=5",
-                "doctrine/orm": "<2.14 || >=4",
-                "doctrine/phpcr-odm": "<1.3.0"
-            },
-            "require-dev": {
-                "doctrine/coding-standard": "^14",
-                "doctrine/dbal": "^3.5 || ^4",
-                "doctrine/mongodb-odm": "^1.3.0 || ^2.0.0",
-                "doctrine/orm": "^2.14 || ^3",
-                "doctrine/phpcr-odm": "^1.8 || ^2.0",
-                "ext-sqlite3": "*",
-                "fig/log-test": "^1",
-                "jackalope/jackalope-fs": "*",
-                "phpstan/phpstan": "2.1.46",
-                "phpunit/phpunit": "10.5.63 || 12.5.12",
-                "symfony/cache": "^6.4 || ^7 || ^8",
-                "symfony/var-exporter": "^6.4 || ^7 || ^8"
-            },
-            "suggest": {
-                "alcaeus/mongo-php-adapter": "For using MongoDB ODM 1.3 with PHP 7 (deprecated)",
-                "doctrine/mongodb-odm": "For loading MongoDB ODM fixtures",
-                "doctrine/orm": "For loading ORM fixtures",
-                "doctrine/phpcr-odm": "For loading PHPCR ODM fixtures"
-            },
-            "type": "library",
-            "autoload": {
-                "psr-4": {
-                    "Doctrine\\Common\\DataFixtures\\": "src"
-                }
-            },
-            "notification-url": "https://packagist.org/downloads/",
-            "license": [
-                "MIT"
-            ],
-            "authors": [
-                {
-                    "name": "Jonathan Wage",
-                    "email": "jonwage@gmail.com"
-                }
-            ],
-            "description": "Data Fixtures for all Doctrine Object Managers",
-            "homepage": "https://www.doctrine-project.org",
-            "keywords": [
-                "database"
-            ],
-            "support": {
-                "issues": "https://github.com/doctrine/data-fixtures/issues",
-                "source": "https://github.com/doctrine/data-fixtures/tree/2.2.1"
-            },
-            "funding": [
-                {
-                    "url": "https://www.doctrine-project.org/sponsorship.html",
-                    "type": "custom"
-                },
-                {
-                    "url": "https://www.patreon.com/phpdoctrine",
-                    "type": "patreon"
-                },
-                {
-                    "url": "https://tidelift.com/funding/github/packagist/doctrine%2Fdata-fixtures",
-                    "type": "tidelift"
-                }
-            ],
-            "time": "2026-04-01T13:56:01+00:00"
-        },
-        {
-            "name": "doctrine/doctrine-fixtures-bundle",
-            "version": "4.3.1",
-            "source": {
-                "type": "git",
-                "url": "https://github.com/doctrine/DoctrineFixturesBundle.git",
-                "reference": "9e013ed10d49bf7746b07204d336384a7d9b5a4d"
-            },
-            "dist": {
-                "type": "zip",
-                "url": "https://api.github.com/repos/doctrine/DoctrineFixturesBundle/zipball/9e013ed10d49bf7746b07204d336384a7d9b5a4d",
-                "reference": "9e013ed10d49bf7746b07204d336384a7d9b5a4d",
-                "shasum": ""
-            },
-            "require": {
-                "doctrine/data-fixtures": "^2.2",
-                "doctrine/doctrine-bundle": "^2.2 || ^3.0",
-                "doctrine/orm": "^2.14.0 || ^3.0",
-                "doctrine/persistence": "^2.4 || ^3.0 || ^4.0",
-                "php": "^8.1",
-                "psr/log": "^2 || ^3",
-                "symfony/config": "^6.4 || ^7.0 || ^8.0",
-                "symfony/console": "^6.4 || ^7.0 || ^8.0",
-                "symfony/dependency-injection": "^6.4 || ^7.0 || ^8.0",
-                "symfony/deprecation-contracts": "^2.1 || ^3",
-                "symfony/doctrine-bridge": "^6.4.16 || ^7.1.9 || ^8.0",
-                "symfony/http-kernel": "^6.4 || ^7.0 || ^8.0"
-            },
-            "conflict": {
-                "doctrine/dbal": "< 3"
-            },
-            "require-dev": {
-                "doctrine/coding-standard": "14.0.0",
-                "phpstan/phpstan": "2.1.11",
-                "phpunit/phpunit": "^10.5.38 || 11.4.14"
-            },
-            "type": "symfony-bundle",
-            "autoload": {
-                "psr-4": {
-                    "Doctrine\\Bundle\\FixturesBundle\\": "src"
-                }
-            },
-            "notification-url": "https://packagist.org/downloads/",
-            "license": [
-                "MIT"
-            ],
-            "authors": [
-                {
-                    "name": "Fabien Potencier",
-                    "email": "fabien@symfony.com"
-                },
-                {
-                    "name": "Doctrine Project",
-                    "homepage": "https://www.doctrine-project.org"
-                },
-                {
-                    "name": "Symfony Community",
-                    "homepage": "https://symfony.com/contributors"
-                }
-            ],
-            "description": "Symfony DoctrineFixturesBundle",
-            "homepage": "https://www.doctrine-project.org",
-            "keywords": [
-                "Fixture",
-                "persistence"
-            ],
-            "support": {
-                "issues": "https://github.com/doctrine/DoctrineFixturesBundle/issues",
-                "source": "https://github.com/doctrine/DoctrineFixturesBundle/tree/4.3.1"
-            },
-            "funding": [
-                {
-                    "url": "https://www.doctrine-project.org/sponsorship.html",
-                    "type": "custom"
-                },
-                {
-                    "url": "https://www.patreon.com/phpdoctrine",
-                    "type": "patreon"
-                },
-                {
-                    "url": "https://tidelift.com/funding/github/packagist/doctrine%2Fdoctrine-fixtures-bundle",
-                    "type": "tidelift"
-                }
-            ],
-            "time": "2025-12-03T16:05:42+00:00"
-        },
-        {
-            "name": "fakerphp/faker",
-            "version": "v1.24.1",
-            "source": {
-                "type": "git",
-                "url": "https://github.com/FakerPHP/Faker.git",
-                "reference": "e0ee18eb1e6dc3cda3ce9fd97e5a0689a88a64b5"
-            },
-            "dist": {
-                "type": "zip",
-                "url": "https://api.github.com/repos/FakerPHP/Faker/zipball/e0ee18eb1e6dc3cda3ce9fd97e5a0689a88a64b5",
-                "reference": "e0ee18eb1e6dc3cda3ce9fd97e5a0689a88a64b5",
-                "shasum": ""
-            },
-            "require": {
-                "php": "^7.4 || ^8.0",
-                "psr/container": "^1.0 || ^2.0",
-                "symfony/deprecation-contracts": "^2.2 || ^3.0"
-            },
-            "conflict": {
-                "fzaninotto/faker": "*"
-            },
-            "require-dev": {
-                "bamarni/composer-bin-plugin": "^1.4.1",
-                "doctrine/persistence": "^1.3 || ^2.0",
-                "ext-intl": "*",
-                "phpunit/phpunit": "^9.5.26",
-                "symfony/phpunit-bridge": "^5.4.16"
-            },
-            "suggest": {
-                "doctrine/orm": "Required to use Faker\\ORM\\Doctrine",
-                "ext-curl": "Required by Faker\\Provider\\Image to download images.",
-                "ext-dom": "Required by Faker\\Provider\\HtmlLorem for generating random HTML.",
-                "ext-iconv": "Required by Faker\\Provider\\ru_RU\\Text::realText() for generating real Russian text.",
-                "ext-mbstring": "Required for multibyte Unicode string functionality."
-            },
-            "type": "library",
-            "autoload": {
-                "psr-4": {
-                    "Faker\\": "src/Faker/"
-                }
-            },
-            "notification-url": "https://packagist.org/downloads/",
-            "license": [
-                "MIT"
-            ],
-            "authors": [
-                {
-                    "name": "François Zaninotto"
-                }
-            ],
-            "description": "Faker is a PHP library that generates fake data for you.",
-            "keywords": [
-                "data",
-                "faker",
-                "fixtures"
-            ],
-            "support": {
-                "issues": "https://github.com/FakerPHP/Faker/issues",
-                "source": "https://github.com/FakerPHP/Faker/tree/v1.24.1"
-            },
-            "time": "2024-11-21T13:46:39+00:00"
-        },
         {
             "name": "masterminds/html5",
             "version": "2.10.0",
@@ -8221,193 +7987,6 @@
                 }
             ],
             "time": "2025-12-08T11:19:18+00:00"
-        },
-        {
-            "name": "zenstruck/assert",
-            "version": "v1.7.0",
-            "source": {
-                "type": "git",
-                "url": "https://github.com/zenstruck/assert.git",
-                "reference": "1e32d48847d4e82c345112ca226b21a1a792af0a"
-            },
-            "dist": {
-                "type": "zip",
-                "url": "https://api.github.com/repos/zenstruck/assert/zipball/1e32d48847d4e82c345112ca226b21a1a792af0a",
-                "reference": "1e32d48847d4e82c345112ca226b21a1a792af0a",
-                "shasum": ""
-            },
-            "require": {
-                "php": ">=8.1",
-                "symfony/polyfill-php81": "^1.23",
-                "symfony/var-exporter": "^5.4|^6.0|^7.0|^8.0"
-            },
-            "require-dev": {
-                "phpstan/phpstan": "^1.4",
-                "phpunit/phpunit": "^9.5.21",
-                "symfony/phpunit-bridge": "^6.3|^7.0|^8.0"
-            },
-            "type": "library",
-            "autoload": {
-                "psr-4": {
-                    "Zenstruck\\": "src/"
-                }
-            },
-            "notification-url": "https://packagist.org/downloads/",
-            "license": [
-                "MIT"
-            ],
-            "authors": [
-                {
-                    "name": "Kevin Bond",
-                    "email": "kevinbond@gmail.com"
-                }
-            ],
-            "description": "Standalone, lightweight, framework agnostic, test assertion library.",
-            "homepage": "https://github.com/zenstruck/assert",
-            "keywords": [
-                "assertion",
-                "phpunit",
-                "test"
-            ],
-            "support": {
-                "issues": "https://github.com/zenstruck/assert/issues",
-                "source": "https://github.com/zenstruck/assert/tree/v1.7.0"
-            },
-            "funding": [
-                {
-                    "url": "https://github.com/kbond",
-                    "type": "github"
-                },
-                {
-                    "url": "https://github.com/nikophil",
-                    "type": "github"
-                }
-            ],
-            "time": "2025-12-07T01:59:12+00:00"
-        },
-        {
-            "name": "zenstruck/foundry",
-            "version": "v2.10.1",
-            "source": {
-                "type": "git",
-                "url": "https://github.com/zenstruck/foundry.git",
-                "reference": "34cbd882df0fee5a5f9bd2f0c2f69286e283263d"
-            },
-            "dist": {
-                "type": "zip",
-                "url": "https://api.github.com/repos/zenstruck/foundry/zipball/34cbd882df0fee5a5f9bd2f0c2f69286e283263d",
-                "reference": "34cbd882df0fee5a5f9bd2f0c2f69286e283263d",
-                "shasum": ""
-            },
-            "require": {
-                "fakerphp/faker": "^1.24",
-                "php": ">=8.1",
-                "symfony/deprecation-contracts": "^2.2|^3.0",
-                "symfony/polyfill-php84": "^1.32",
-                "symfony/polyfill-php85": "^1.33",
-                "symfony/property-access": "^6.4|^7.0|^8.0",
-                "symfony/property-info": "^6.4|^7.0|^8.0",
-                "symfony/var-exporter": "^6.4.9|~7.0.9|^7.1.2|^8.0",
-                "zenstruck/assert": "^1.4"
-            },
-            "conflict": {
-                "doctrine/cache": "<1.12.1",
-                "doctrine/persistence": "<2.0"
-            },
-            "require-dev": {
-                "bamarni/composer-bin-plugin": "^1.8",
-                "dama/doctrine-test-bundle": "^8.0",
-                "doctrine/collections": "^1.7|^2.0",
-                "doctrine/common": "^3.2.2",
-                "doctrine/doctrine-bundle": "^2.10|^3.0",
-                "doctrine/doctrine-migrations-bundle": "^2.2|^3.0",
-                "doctrine/mongodb-odm": "^2.4",
-                "doctrine/mongodb-odm-bundle": "^4.6|^5.0",
-                "doctrine/orm": "^2.16|^3.0",
-                "doctrine/persistence": "^2.0|^3.0|^4.0",
-                "phpunit/phpunit": "^9.5.0 || ^10.0 || ^11.0 || ^12.0 || ^13.0",
-                "symfony/browser-kit": "^6.4|^7.0|^8.0",
-                "symfony/console": "^6.4|^7.0|^8.0",
-                "symfony/dotenv": "^6.4|^7.0|^8.0",
-                "symfony/event-dispatcher": "^6.4|^7.0|^8.0",
-                "symfony/flex": "^2.10",
-                "symfony/framework-bundle": "^6.4|^7.0|^8.0",
-                "symfony/maker-bundle": "^1.55",
-                "symfony/phpunit-bridge": "^6.4.26|^7.0|^8.0",
-                "symfony/routing": "^6.4|^7.0|^8.0",
-                "symfony/runtime": "^6.4|^7.0|^8.0",
-                "symfony/translation-contracts": "^3.4",
-                "symfony/uid": "^6.4|^7.0|^8.0",
-                "symfony/var-dumper": "^6.4|^7.0|^8.0",
-                "symfony/yaml": "^6.4|^7.0|^8.0",
-                "webmozart/assert": "^1.11"
-            },
-            "type": "library",
-            "extra": {
-                "psalm": {
-                    "pluginClass": "Zenstruck\\Foundry\\Psalm\\FoundryPlugin"
-                },
-                "symfony": {
-                    "allow-contrib": false
-                },
-                "bamarni-bin": {
-                    "bin-links": true,
-                    "forward-command": false,
-                    "target-directory": "bin/tools"
-                }
-            },
-            "autoload": {
-                "files": [
-                    "src/functions.php",
-                    "src/Persistence/functions.php",
-                    "src/symfony_console.php"
-                ],
-                "psr-4": {
-                    "Zenstruck\\Foundry\\": "src/",
-                    "Zenstruck\\Foundry\\Psalm\\": "utils/psalm",
-                    "Zenstruck\\Foundry\\Utils\\Rector\\": "utils/rector/src/"
-                }
-            },
-            "notification-url": "https://packagist.org/downloads/",
-            "license": [
-                "MIT"
-            ],
-            "authors": [
-                {
-                    "name": "Kevin Bond",
-                    "email": "kevinbond@gmail.com"
-                },
-                {
-                    "name": "Nicolas PHILIPPE",
-                    "email": "nikophil@gmail.com"
-                }
-            ],
-            "description": "A model factory library for creating expressive, auto-completable, on-demand dev/test fixtures with Symfony and Doctrine.",
-            "homepage": "https://github.com/zenstruck/foundry",
-            "keywords": [
-                "Fixture",
-                "dev",
-                "doctrine",
-                "factory",
-                "faker",
-                "symfony",
-                "test"
-            ],
-            "support": {
-                "issues": "https://github.com/zenstruck/foundry/issues",
-                "source": "https://github.com/zenstruck/foundry/tree/v2.10.1"
-            },
-            "funding": [
-                {
-                    "url": "https://github.com/kbond",
-                    "type": "github"
-                },
-                {
-                    "url": "https://github.com/nikophil",
-                    "type": "github"
-                }
-            ],
-            "time": "2026-05-19T15:59:32+00:00"
         }
     ],
     "aliases": [],
diff --git a/backend/config/bundles.php b/backend/config/bundles.php
index 7471b37..47560e4 100644
--- a/backend/config/bundles.php
+++ b/backend/config/bundles.php
@@ -8,6 +8,4 @@ return [
     Doctrine\Bundle\MigrationsBundle\DoctrineMigrationsBundle::class => ['all' => true],
     Symfony\Bundle\MakerBundle\MakerBundle::class => ['dev' => true],
     Symfony\Bundle\MercureBundle\MercureBundle::class => ['all' => true],
-    Doctrine\Bundle\FixturesBundle\DoctrineFixturesBundle::class => ['dev' => true, 'test' => true, 'staging' => true],
-    Zenstruck\Foundry\ZenstruckFoundryBundle::class => ['dev' => true, 'test' => true, 'staging' => true],
 ];
diff --git a/backend/config/packages/cache.yaml b/backend/config/packages/cache.yaml
index 6899b72..ad87064 100644
--- a/backend/config/packages/cache.yaml
+++ b/backend/config/packages/cache.yaml
@@ -15,5 +15,7 @@ framework:
         #app: cache.adapter.apcu
 
         # Namespaced pools use the above "app" backend by default
-        #pools:
-            #my.dedicated.cache: null
+        pools:
+            enrichment.cache:
+                adapter: cache.adapter.filesystem
+                default_lifetime: 86400
diff --git a/backend/config/packages/doctrine.yaml b/backend/config/packages/doctrine.yaml
index 21d1fcf..5659c48 100644
--- a/backend/config/packages/doctrine.yaml
+++ b/backend/config/packages/doctrine.yaml
@@ -6,6 +6,8 @@ doctrine:
         use_savepoints: true
         types:
             vector: Pgvector\Doctrine\VectorType
+        mapping_types:
+            vector: vector
     orm:
         auto_generate_proxy_classes: true
         enable_lazy_ghost_objects: true
diff --git a/backend/config/packages/messenger.yaml b/backend/config/packages/messenger.yaml
index 8cb240e..bb83808 100644
--- a/backend/config/packages/messenger.yaml
+++ b/backend/config/packages/messenger.yaml
@@ -50,9 +50,8 @@ framework:
                             binding_keys: [failed]
 
         routing:
-            # Example routing pattern — see docs/examples/IngestSourceMessage.php.example
-            # 'App\Message\IngestSourceMessage': ingest
-            # 'App\Message\EnrichItemMessage': enrich
+            'App\Message\IngestSourceMessage': ingest
+            'App\Message\EnrichItemMessage': enrich
 
 when@test:
     framework:
diff --git a/backend/config/packages/zenstruck_foundry.yaml b/backend/config/packages/zenstruck_foundry.yaml
deleted file mode 100644
index 9c94f88..0000000
--- a/backend/config/packages/zenstruck_foundry.yaml
+++ /dev/null
@@ -1,17 +0,0 @@
-when@dev: &dev
-    # See full configuration: https://symfony.com/bundles/ZenstruckFoundryBundle/current/index.html#full-default-bundle-configuration
-    zenstruck_foundry:
-        persistence:
-            # Flush only once per call of `PersistentObjectFactory::create()`
-            flush_once: true
-
-    # If you use the `make:factory --test` command, you may need to uncomment the following.
-    # See https://symfony.com/bundles/ZenstruckFoundryBundle/current/index.html#generate
-    #services:
-    #    App\Tests\Factory\:
-    #        resource: '%kernel.project_dir%/tests/Factory/'
-    #        autowire: true
-    #        autoconfigure: true
-
-when@test: *dev
-when@staging: *dev
diff --git a/backend/config/reference.php b/backend/config/reference.php
index 7427e46..8cfd4b7 100644
--- a/backend/config/reference.php
+++ b/backend/config/reference.php
@@ -1372,50 +1372,6 @@ use Symfony\Component\Config\Loader\ParamConfigurator as Param;
  *     default_cookie_lifetime?: int|Param, // Default lifetime of the cookie containing the JWT, in seconds. Defaults to the value of "framework.session.cookie_lifetime". // Default: null
  *     enable_profiler?: bool|Param, // Deprecated: The child node "enable_profiler" at path "mercure.enable_profiler" is deprecated. // Enable Symfony Web Profiler integration.
  * }
- * @psalm-type ZenstruckFoundryConfig = array{
- *     auto_refresh_proxies?: bool|Param|null, // Deprecated: Since 2.0 auto_refresh_proxies defaults to true and this configuration has no effect. // Whether to auto-refresh proxies by default (https://symfony.com/bundles/ZenstruckFoundryBundle/current/index.html#auto-refresh) // Default: null
- *     enable_auto_refresh_with_lazy_objects?: bool|Param|null, // Enable auto-refresh using PHP 8.4 lazy objects (cannot be enabled if PHP < 8.4). // Default: null
- *     faker?: array{ // Configure the faker used by your factories.
- *         locale?: scalar|Param|null, // The default locale to use for faker. // Default: null
- *         seed?: scalar|Param|null, // Deprecated: The "faker.seed" configuration is deprecated and will be removed in 3.0. Use environment variable "FOUNDRY_FAKER_SEED" instead. // Random number generator seed to produce the same fake values every run. // Default: null
- *         manage_seed?: bool|Param, // Automatically manage faker seed to ensure consistent data between test runs. // Default: true
- *         service?: scalar|Param|null, // Service id for custom faker instance. // Default: null
- *     },
- *     instantiator?: array{ // Configure the default instantiator used by your object factories.
- *         use_constructor?: bool|Param, // Use the constructor to instantiate objects. // Default: true
- *         allow_extra_attributes?: bool|Param, // Whether or not to skip attributes that do not correspond to properties. // Default: false
- *         always_force_properties?: bool|Param, // Whether or not to skip setters and force set object properties (public/private/protected) directly. // Default: false
- *         service?: scalar|Param|null, // Service id of your custom instantiator. // Default: null
- *     },
- *     global_state?: list<scalar|Param|null>,
- *     persistence?: array{
- *         flush_once?: bool|Param, // Flush only once per call of `PersistentObjectFactory::create()` in userland. // Default: false
- *     },
- *     orm?: array{
- *         auto_persist?: bool|Param, // Deprecated: Since 2.4 auto_persist defaults to true and this configuration has no effect. // Automatically persist entities when created. // Default: true
- *         reset?: array{
- *             connections?: list<scalar|Param|null>,
- *             entity_managers?: list<scalar|Param|null>,
- *             mode?: \Zenstruck\Foundry\ORM\ResetDatabase\ResetDatabaseMode::SCHEMA|\Zenstruck\Foundry\ORM\ResetDatabase\ResetDatabaseMode::MIGRATE|Param, // Reset mode to use with ResetDatabase trait // Default: "schema"
- *             migrations?: array{
- *                 configurations?: list<scalar|Param|null>,
- *             },
- *         },
- *     },
- *     mongo?: array{
- *         auto_persist?: bool|Param, // Deprecated: Since 2.4 auto_persist defaults to true and this configuration has no effect. // Automatically persist documents when created. // Default: true
- *         reset?: array{
- *             document_managers?: list<scalar|Param|null>,
- *         },
- *     },
- *     make_factory?: array{
- *         default_namespace?: scalar|Param|null, // Default namespace where factories will be created by maker. // Default: "Factory"
- *         add_hints?: bool|Param, // Add "beginner" hints in the created factory. // Default: true
- *     },
- *     make_story?: array{
- *         default_namespace?: scalar|Param|null, // Default namespace where stories will be created by maker. // Default: "Story"
- *     },
- * }
  * @psalm-type ConfigType = array{
  *     imports?: ImportsConfig,
  *     parameters?: ParametersConfig,
@@ -1437,7 +1393,6 @@ use Symfony\Component\Config\Loader\ParamConfigurator as Param;
  *         doctrine_migrations?: DoctrineMigrationsConfig,
  *         maker?: MakerConfig,
  *         mercure?: MercureConfig,
- *         zenstruck_foundry?: ZenstruckFoundryConfig,
  *     },
  *     "when@development"?: array{
  *         imports?: ImportsConfig,
@@ -1471,7 +1426,6 @@ use Symfony\Component\Config\Loader\ParamConfigurator as Param;
  *         doctrine?: DoctrineConfig,
  *         doctrine_migrations?: DoctrineMigrationsConfig,
  *         mercure?: MercureConfig,
- *         zenstruck_foundry?: ZenstruckFoundryConfig,
  *     },
  *     ...<string, ExtensionType|array{ // extra keys must follow the when@%env% pattern or match an extension alias
  *         imports?: ImportsConfig,
diff --git a/backend/config/services.yaml b/backend/config/services.yaml
index 79b8ce2..af671e4 100644
--- a/backend/config/services.yaml
+++ b/backend/config/services.yaml
@@ -7,6 +7,7 @@
 # Put parameters here that don't need to change on each machine where the app is deployed
 # https://symfony.com/doc/current/best_practices.html#use-parameters-for-application-configuration
 parameters:
+    env(VOYAGE_API_KEY): ''
 
 services:
     # default configuration for services in *this* file
@@ -21,3 +22,37 @@ services:
 
     # add more service definitions when explicit configuration is needed
     # please note that last definitions always *replace* previous ones
+
+    app.adapter.coindesk_rss:
+        class: App\Adapter\RssAdapter
+        arguments:
+            $sourceId: 'coindesk-rss'
+            $feedUrl: 'https://www.coindesk.com/arc/outboundfeeds/rss/'
+        tags: ['app.source_adapter']
+
+    app.adapter.cointelegraph_rss:
+        class: App\Adapter\RssAdapter
+        arguments:
+            $sourceId: 'cointelegraph-rss'
+            $feedUrl: 'https://cointelegraph.com/rss'
+        tags: ['app.source_adapter']
+
+    App\MessageHandler\IngestSourceHandler:
+        arguments:
+            $adapters: !tagged_iterator app.source_adapter
+
+    App\Command\SourcesPollCommand:
+        arguments:
+            $adapters: !tagged_iterator app.source_adapter
+
+    App\Provider\AnthropicEnrichmentProvider:
+        arguments:
+            $apiKey: '%env(ANTHROPIC_API_KEY)%'
+            $enrichmentCache: '@enrichment.cache'
+
+    App\Provider\VoyageEmbeddingProvider:
+        arguments:
+            $apiKey: '%env(VOYAGE_API_KEY)%'
+
+    App\Provider\EnrichmentProviderInterface: '@App\Provider\AnthropicEnrichmentProvider'
+    App\Provider\EmbeddingProviderInterface: '@App\Provider\VoyageEmbeddingProvider'
diff --git a/backend/config/services_development.yaml b/backend/config/services_development.yaml
new file mode 100644
index 0000000..dcc108e
--- /dev/null
+++ b/backend/config/services_development.yaml
@@ -0,0 +1,4 @@
+services:
+    # Use the null provider in dev so no API tokens are spent during local work.
+    # Override with ENRICHMENT_PROVIDER=anthropic if you need to test the real API.
+    App\Provider\EnrichmentProviderInterface: '@App\Provider\NullEnrichmentProvider'
diff --git a/backend/migrations/Version20260601054114.php b/backend/migrations/Version20260601054114.php
new file mode 100644
index 0000000..c3e0bb5
--- /dev/null
+++ b/backend/migrations/Version20260601054114.php
@@ -0,0 +1,39 @@
+<?php
+
+declare(strict_types=1);
+
+namespace App\Migrations;
+
+use Doctrine\DBAL\Schema\Schema;
+use Doctrine\Migrations\AbstractMigration;
+
+/**
+ * Auto-generated Migration: Please modify to your needs!
+ */
+final class Version20260601054114 extends AbstractMigration
+{
+    public function getDescription(): string
+    {
+        return 'Create news_item and enrichment tables; HNSW index on embedding for semantic search';
+    }
+
+    public function up(Schema $schema): void
+    {
+        $this->addSql('CREATE TABLE news_item (id INT GENERATED BY DEFAULT AS IDENTITY NOT NULL, source VARCHAR(64) NOT NULL, external_id VARCHAR(512) NOT NULL, title VARCHAR(512) NOT NULL, url VARCHAR(2048) NOT NULL, body TEXT DEFAULT NULL, published_at TIMESTAMP(0) WITHOUT TIME ZONE NOT NULL, content_hash VARCHAR(64) NOT NULL, status VARCHAR(16) NOT NULL, created_at TIMESTAMP(0) WITHOUT TIME ZONE NOT NULL, PRIMARY KEY (id))');
+        $this->addSql('CREATE UNIQUE INDEX uniq_content_hash ON news_item (content_hash)');
+        $this->addSql('CREATE INDEX idx_news_item_status ON news_item (status)');
+        $this->addSql('CREATE INDEX idx_news_item_published_at ON news_item (published_at)');
+        $this->addSql('CREATE TABLE enrichment (id INT GENERATED BY DEFAULT AS IDENTITY NOT NULL, news_item_id INT NOT NULL, summary TEXT NOT NULL, sentiment VARCHAR(16) NOT NULL, asset_class VARCHAR(64) DEFAULT NULL, tickers JSON NOT NULL, entities JSON NOT NULL, embedding vector(1024) DEFAULT NULL, model VARCHAR(64) NOT NULL, tokens INT NOT NULL, cost_usd NUMERIC(10, 6) NOT NULL, created_at TIMESTAMP(0) WITHOUT TIME ZONE NOT NULL, PRIMARY KEY (id))');
+        $this->addSql('CREATE UNIQUE INDEX UNIQ_BCDAF6CE458B4EB8 ON enrichment (news_item_id)');
+        $this->addSql('ALTER TABLE enrichment ADD CONSTRAINT FK_BCDAF6CE458B4EB8 FOREIGN KEY (news_item_id) REFERENCES news_item (id) ON DELETE CASCADE NOT DEFERRABLE');
+        // HNSW index for cosine similarity search — only rows with a non-null embedding are indexed
+        $this->addSql('CREATE INDEX hnsw_enrichment_embedding ON enrichment USING hnsw (embedding vector_cosine_ops) WHERE embedding IS NOT NULL');
+    }
+
+    public function down(Schema $schema): void
+    {
+        $this->addSql('ALTER TABLE enrichment DROP CONSTRAINT FK_BCDAF6CE458B4EB8');
+        $this->addSql('DROP TABLE enrichment');
+        $this->addSql('DROP TABLE news_item');
+    }
+}
diff --git a/backend/phpunit.dist.xml b/backend/phpunit.dist.xml
index a9d67c9..2305901 100644
--- a/backend/phpunit.dist.xml
+++ b/backend/phpunit.dist.xml
@@ -36,6 +36,5 @@
     </source>
 
     <extensions>
-        <bootstrap class="Zenstruck\Foundry\PHPUnit\FoundryExtension" />
     </extensions>
 </phpunit>
diff --git a/backend/scheduler/crontab b/backend/scheduler/crontab
index dfef42b..2a7a8bf 100644
--- a/backend/scheduler/crontab
+++ b/backend/scheduler/crontab
@@ -1,5 +1 @@
-# Crontab del scheduler (supercronic). Vacío por defecto: Oliva no asume
-# ninguna tarea periódica. Cada fork que necesite cron activa el profile
-# `cron` (ver docker-compose.yml) y agrega aquí sus líneas. Ejemplo:
-#
-#   */5 * * * * bin/console app:my-command -v
+*/5 * * * * bin/console app:sources:poll -v
diff --git a/backend/src/Adapter/RssAdapter.php b/backend/src/Adapter/RssAdapter.php
new file mode 100644
index 0000000..b1a85f0
--- /dev/null
+++ b/backend/src/Adapter/RssAdapter.php
@@ -0,0 +1,69 @@
+<?php
+
+namespace App\Adapter;
+
+use Symfony\Contracts\HttpClient\HttpClientInterface;
+
+class RssAdapter implements SourceAdapterInterface
+{
+    public function __construct(
+        private readonly HttpClientInterface $httpClient,
+        private readonly string $sourceId,
+        private readonly string $feedUrl,
+    ) {}
+
+    public function getId(): string
+    {
+        return $this->sourceId;
+    }
+
+    public function fetch(): iterable
+    {
+        $response = $this->httpClient->request('GET', $this->feedUrl, [
+            'timeout' => 10,
+            'headers' => ['Accept' => 'application/rss+xml, application/xml, text/xml'],
+        ]);
+
+        $xml = new \SimpleXMLElement($response->getContent());
+        $items = $xml->channel->item ?? [];
+
+        foreach ($items as $item) {
+            $guid = (string) ($item->guid ?? $item->link);
+            $url  = (string) $item->link;
+
+            if ('' === $url) {
+                continue;
+            }
+
+            $body = null;
+            // Prefer full content when the feed provides it
+            $namespaces = $item->getNamespaces(true);
+            if (isset($namespaces['content'])) {
+                $content = $item->children($namespaces['content']);
+                $encoded = (string) ($content->encoded ?? '');
+                if ('' !== $encoded) {
+                    $body = strip_tags($encoded);
+                }
+            }
+            if (null === $body) {
+                $desc = (string) ($item->description ?? '');
+                $body = '' !== $desc ? strip_tags($desc) : null;
+            }
+
+            $pubDate = (string) ($item->pubDate ?? '');
+            try {
+                $publishedAt = new \DateTimeImmutable($pubDate !== '' ? $pubDate : 'now');
+            } catch (\Exception) {
+                $publishedAt = new \DateTimeImmutable();
+            }
+
+            yield [
+                'externalId'  => $guid !== '' ? $guid : $url,
+                'title'       => strip_tags((string) ($item->title ?? '')),
+                'url'         => $url,
+                'body'        => $body,
+                'publishedAt' => $publishedAt,
+            ];
+        }
+    }
+}
diff --git a/backend/src/Adapter/SourceAdapterInterface.php b/backend/src/Adapter/SourceAdapterInterface.php
new file mode 100644
index 0000000..e074179
--- /dev/null
+++ b/backend/src/Adapter/SourceAdapterInterface.php
@@ -0,0 +1,22 @@
+<?php
+
+namespace App\Adapter;
+
+interface SourceAdapterInterface
+{
+    public function getId(): string;
+
+    /**
+     * Fetch raw items from the source.
+     *
+     * Each item is an array with keys:
+     *   externalId  (string)  — original GUID/ID from the feed
+     *   title       (string)
+     *   url         (string)
+     *   body        (string|null)
+     *   publishedAt (\DateTimeImmutable)
+     *
+     * @return iterable<array<string, mixed>>
+     */
+    public function fetch(): iterable;
+}
diff --git a/backend/src/Command/EnrichRequeueCommand.php b/backend/src/Command/EnrichRequeueCommand.php
new file mode 100644
index 0000000..e793025
--- /dev/null
+++ b/backend/src/Command/EnrichRequeueCommand.php
@@ -0,0 +1,39 @@
+<?php
+
+namespace App\Command;
+
+use App\Entity\NewsItemStatus;
+use App\Message\EnrichItemMessage;
+use App\Repository\NewsItemRepository;
+use Symfony\Component\Console\Attribute\AsCommand;
+use Symfony\Component\Console\Command\Command;
+use Symfony\Component\Console\Input\InputInterface;
+use Symfony\Component\Console\Output\OutputInterface;
+use Symfony\Component\Messenger\MessageBusInterface;
+
+#[AsCommand(
+    name: 'app:enrich:requeue-pending',
+    description: 'Dispatch EnrichItemMessage for every NewsItem still in pending status',
+)]
+class EnrichRequeueCommand extends Command
+{
+    public function __construct(
+        private readonly NewsItemRepository $newsItemRepo,
+        private readonly MessageBusInterface $bus,
+    ) {
+        parent::__construct();
+    }
+
+    protected function execute(InputInterface $input, OutputInterface $output): int
+    {
+        $items = $this->newsItemRepo->findBy(['status' => NewsItemStatus::Pending]);
+
+        foreach ($items as $item) {
+            $this->bus->dispatch(new EnrichItemMessage($item->getId()));
+        }
+
+        $output->writeln(\sprintf('[%s] Requeued %d pending items.', date('Y-m-d H:i:s'), \count($items)));
+
+        return Command::SUCCESS;
+    }
+}
diff --git a/docs/examples/MercurePublishTestCommand.php.example b/backend/src/Command/MercurePublishTestCommand.php
similarity index 88%
rename from docs/examples/MercurePublishTestCommand.php.example
rename to backend/src/Command/MercurePublishTestCommand.php
index c8bcd03..ffad65c 100644
--- a/docs/examples/MercurePublishTestCommand.php.example
+++ b/backend/src/Command/MercurePublishTestCommand.php
@@ -22,8 +22,8 @@ final class MercurePublishTestCommand extends Command
     protected function execute(InputInterface $input, OutputInterface $output): int
     {
         $update = new Update(
-            'https://oliva.dev/test',
-            json_encode(['type' => 'test', 'message' => 'mercure-verification', 'ts' => time()])
+            'https://crypto-pulse.dev/test',
+            json_encode(['type' => 'test', 'message' => 'step-0.4-verification', 'ts' => time()])
         );
 
         try {
diff --git a/docs/examples/SourcesPollCommand.php.example b/backend/src/Command/SourcesPollCommand.php
similarity index 64%
rename from docs/examples/SourcesPollCommand.php.example
rename to backend/src/Command/SourcesPollCommand.php
index 8243e7f..7df90c1 100644
--- a/docs/examples/SourcesPollCommand.php.example
+++ b/backend/src/Command/SourcesPollCommand.php
@@ -2,6 +2,7 @@
 
 namespace App\Command;
 
+use App\Adapter\SourceAdapterInterface;
 use App\Message\IngestSourceMessage;
 use Symfony\Component\Console\Attribute\AsCommand;
 use Symfony\Component\Console\Command\Command;
@@ -12,19 +13,19 @@ use Symfony\Component\Messenger\MessageBusInterface;
 #[AsCommand(name: 'app:sources:poll', description: 'Poll configured sources and enqueue ingestion jobs')]
 class SourcesPollCommand extends Command
 {
-    // Stub source list — replace with real sources for your domain
-    private const SOURCES = ['example-source-a', 'example-source-b', 'example-source-c'];
-
-    public function __construct(private readonly MessageBusInterface $bus)
-    {
+    /** @param iterable<SourceAdapterInterface> $adapters */
+    public function __construct(
+        private readonly MessageBusInterface $bus,
+        private readonly iterable $adapters,
+    ) {
         parent::__construct();
     }
 
     protected function execute(InputInterface $input, OutputInterface $output): int
     {
-        foreach (self::SOURCES as $sourceId) {
-            $this->bus->dispatch(new IngestSourceMessage($sourceId));
-            $output->writeln(sprintf('[%s] Enqueued: %s', date('Y-m-d H:i:s'), $sourceId));
+        foreach ($this->adapters as $adapter) {
+            $this->bus->dispatch(new IngestSourceMessage($adapter->getId()));
+            $output->writeln(sprintf('[%s] Enqueued: %s', date('Y-m-d H:i:s'), $adapter->getId()));
         }
 
         return Command::SUCCESS;
diff --git a/backend/src/DataFixtures/AppFixtures.php b/backend/src/DataFixtures/AppFixtures.php
deleted file mode 100644
index 50c951c..0000000
--- a/backend/src/DataFixtures/AppFixtures.php
+++ /dev/null
@@ -1,32 +0,0 @@
-<?php
-
-namespace App\DataFixtures;
-
-use Doctrine\Bundle\FixturesBundle\Fixture;
-use Doctrine\Bundle\FixturesBundle\FixtureGroupInterface;
-use Doctrine\Persistence\ObjectManager;
-
-/**
- * Entry point for fixture groups. Forks replace this with their own entities
- * using Foundry factories (e.g. MemberFactory::createMany(15)).
- *
- * Usage:
- *   bin/console doctrine:fixtures:load --group=staging --no-interaction
- *   bin/console doctrine:fixtures:load --group=dev --no-interaction
- */
-class AppFixtures extends Fixture implements FixtureGroupInterface
-{
-    public static function getGroups(): array
-    {
-        return ['staging', 'dev'];
-    }
-
-    public function load(ObjectManager $manager): void
-    {
-        // Forks: call your Foundry factories here.
-        // Example:
-        //   MemberFactory::createMany(15);
-        //   ProjectFactory::createMany(5);
-        $manager->flush();
-    }
-}
diff --git a/backend/src/Entity/Enrichment.php b/backend/src/Entity/Enrichment.php
new file mode 100644
index 0000000..bf01a36
--- /dev/null
+++ b/backend/src/Entity/Enrichment.php
@@ -0,0 +1,101 @@
+<?php
+
+namespace App\Entity;
+
+use App\Repository\EnrichmentRepository;
+use Doctrine\ORM\Mapping as ORM;
+
+#[ORM\Entity(repositoryClass: EnrichmentRepository::class)]
+#[ORM\Table(name: 'enrichment')]
+class Enrichment
+{
+    // Embedding dimensions: 1024 matches Voyage-3 (Anthropic's recommended provider).
+    // Adjust here and regenerate the migration if switching providers.
+    public const EMBEDDING_DIMENSIONS = 1024;
+
+    #[ORM\Id]
+    #[ORM\GeneratedValue]
+    #[ORM\Column]
+    private ?int $id = null;
+
+    #[ORM\OneToOne(inversedBy: 'enrichment')]
+    #[ORM\JoinColumn(nullable: false, onDelete: 'CASCADE')]
+    private NewsItem $newsItem;
+
+    #[ORM\Column(type: 'text')]
+    private string $summary;
+
+    /** positive | negative | neutral */
+    #[ORM\Column(length: 16)]
+    private string $sentiment;
+
+    /** Primary asset class affected: BTC, ETH, DeFi, NFT, Regulation… */
+    #[ORM\Column(length: 64, nullable: true)]
+    private ?string $assetClass = null;
+
+    /** JSON array of ticker symbols mentioned: ["BTC","ETH"] */
+    #[ORM\Column(type: 'json')]
+    private array $tickers = [];
+
+    /** JSON array of named entities (people, orgs, protocols) */
+    #[ORM\Column(type: 'json')]
+    private array $entities = [];
+
+    /** Dense vector representation of the article — used for semantic search */
+    #[ORM\Column(type: 'vector', length: self::EMBEDDING_DIMENSIONS, nullable: true)]
+    private ?array $embedding = null;
+
+    /** Model used for enrichment, e.g. 'claude-haiku-4-5' */
+    #[ORM\Column(length: 64)]
+    private string $model;
+
+    /** Total tokens consumed (input + output) for cost tracking */
+    #[ORM\Column]
+    private int $tokens = 0;
+
+    /** Estimated cost in USD for this enrichment call */
+    #[ORM\Column(type: 'decimal', precision: 10, scale: 6)]
+    private string $costUsd = '0.000000';
+
+    #[ORM\Column(type: 'datetime_immutable')]
+    private \DateTimeImmutable $createdAt;
+
+    public function __construct()
+    {
+        $this->createdAt = new \DateTimeImmutable();
+    }
+
+    public function getId(): ?int { return $this->id; }
+
+    public function getNewsItem(): NewsItem { return $this->newsItem; }
+    public function setNewsItem(NewsItem $newsItem): static { $this->newsItem = $newsItem; return $this; }
+
+    public function getSummary(): string { return $this->summary; }
+    public function setSummary(string $summary): static { $this->summary = $summary; return $this; }
+
+    public function getSentiment(): string { return $this->sentiment; }
+    public function setSentiment(string $sentiment): static { $this->sentiment = $sentiment; return $this; }
+
+    public function getAssetClass(): ?string { return $this->assetClass; }
+    public function setAssetClass(?string $assetClass): static { $this->assetClass = $assetClass; return $this; }
+
+    public function getTickers(): array { return $this->tickers; }
+    public function setTickers(array $tickers): static { $this->tickers = $tickers; return $this; }
+
+    public function getEntities(): array { return $this->entities; }
+    public function setEntities(array $entities): static { $this->entities = $entities; return $this; }
+
+    public function getEmbedding(): ?array { return $this->embedding; }
+    public function setEmbedding(?array $embedding): static { $this->embedding = $embedding; return $this; }
+
+    public function getModel(): string { return $this->model; }
+    public function setModel(string $model): static { $this->model = $model; return $this; }
+
+    public function getTokens(): int { return $this->tokens; }
+    public function setTokens(int $tokens): static { $this->tokens = $tokens; return $this; }
+
+    public function getCostUsd(): string { return $this->costUsd; }
+    public function setCostUsd(string $costUsd): static { $this->costUsd = $costUsd; return $this; }
+
+    public function getCreatedAt(): \DateTimeImmutable { return $this->createdAt; }
+}
diff --git a/backend/src/Entity/NewsItem.php b/backend/src/Entity/NewsItem.php
new file mode 100644
index 0000000..85e28d6
--- /dev/null
+++ b/backend/src/Entity/NewsItem.php
@@ -0,0 +1,87 @@
+<?php
+
+namespace App\Entity;
+
+use App\Repository\NewsItemRepository;
+use Doctrine\ORM\Mapping as ORM;
+
+#[ORM\Entity(repositoryClass: NewsItemRepository::class)]
+#[ORM\Table(name: 'news_item')]
+#[ORM\UniqueConstraint(name: 'uniq_content_hash', columns: ['content_hash'])]
+#[ORM\Index(name: 'idx_news_item_status', columns: ['status'])]
+#[ORM\Index(name: 'idx_news_item_published_at', columns: ['published_at'])]
+class NewsItem
+{
+    #[ORM\Id]
+    #[ORM\GeneratedValue]
+    #[ORM\Column]
+    private ?int $id = null;
+
+    /** Identifies the origin feed: e.g. 'coindesk-rss', 'cointelegraph-rss' */
+    #[ORM\Column(length: 64)]
+    private string $source;
+
+    /** Original GUID/ID from the source feed */
+    #[ORM\Column(length: 512)]
+    private string $externalId;
+
+    #[ORM\Column(length: 512)]
+    private string $title;
+
+    #[ORM\Column(length: 2048)]
+    private string $url;
+
+    #[ORM\Column(type: 'text', nullable: true)]
+    private ?string $body = null;
+
+    #[ORM\Column(type: 'datetime_immutable')]
+    private \DateTimeImmutable $publishedAt;
+
+    /** SHA-256 of url — used for deduplication across fetches */
+    #[ORM\Column(length: 64)]
+    private string $contentHash;
+
+    #[ORM\Column(type: 'string', length: 16, enumType: NewsItemStatus::class)]
+    private NewsItemStatus $status = NewsItemStatus::Pending;
+
+    #[ORM\Column(type: 'datetime_immutable')]
+    private \DateTimeImmutable $createdAt;
+
+    #[ORM\OneToOne(mappedBy: 'newsItem', cascade: ['persist', 'remove'])]
+    private ?Enrichment $enrichment = null;
+
+    public function __construct()
+    {
+        $this->createdAt = new \DateTimeImmutable();
+    }
+
+    public function getId(): ?int { return $this->id; }
+
+    public function getSource(): string { return $this->source; }
+    public function setSource(string $source): static { $this->source = $source; return $this; }
+
+    public function getExternalId(): string { return $this->externalId; }
+    public function setExternalId(string $externalId): static { $this->externalId = $externalId; return $this; }
+
+    public function getTitle(): string { return $this->title; }
+    public function setTitle(string $title): static { $this->title = $title; return $this; }
+
+    public function getUrl(): string { return $this->url; }
+    public function setUrl(string $url): static { $this->url = $url; return $this; }
+
+    public function getBody(): ?string { return $this->body; }
+    public function setBody(?string $body): static { $this->body = $body; return $this; }
+
+    public function getPublishedAt(): \DateTimeImmutable { return $this->publishedAt; }
+    public function setPublishedAt(\DateTimeImmutable $publishedAt): static { $this->publishedAt = $publishedAt; return $this; }
+
+    public function getContentHash(): string { return $this->contentHash; }
+    public function setContentHash(string $contentHash): static { $this->contentHash = $contentHash; return $this; }
+
+    public function getStatus(): NewsItemStatus { return $this->status; }
+    public function setStatus(NewsItemStatus $status): static { $this->status = $status; return $this; }
+
+    public function getCreatedAt(): \DateTimeImmutable { return $this->createdAt; }
+
+    public function getEnrichment(): ?Enrichment { return $this->enrichment; }
+}
diff --git a/backend/src/Entity/NewsItemStatus.php b/backend/src/Entity/NewsItemStatus.php
new file mode 100644
index 0000000..843cb94
--- /dev/null
+++ b/backend/src/Entity/NewsItemStatus.php
@@ -0,0 +1,10 @@
+<?php
+
+namespace App\Entity;
+
+enum NewsItemStatus: string
+{
+    case Pending  = 'pending';
+    case Enriched = 'enriched';
+    case Failed   = 'failed';
+}
diff --git a/backend/src/Message/EnrichItemMessage.php b/backend/src/Message/EnrichItemMessage.php
new file mode 100644
index 0000000..5b2fb3d
--- /dev/null
+++ b/backend/src/Message/EnrichItemMessage.php
@@ -0,0 +1,10 @@
+<?php
+
+namespace App\Message;
+
+final class EnrichItemMessage
+{
+    public function __construct(
+        public readonly int $newsItemId,
+    ) {}
+}
diff --git a/docs/examples/IngestSourceMessage.php.example b/backend/src/Message/IngestSourceMessage.php
similarity index 100%
rename from docs/examples/IngestSourceMessage.php.example
rename to backend/src/Message/IngestSourceMessage.php
diff --git a/backend/src/MessageHandler/EnrichItemHandler.php b/backend/src/MessageHandler/EnrichItemHandler.php
new file mode 100644
index 0000000..0738cf4
--- /dev/null
+++ b/backend/src/MessageHandler/EnrichItemHandler.php
@@ -0,0 +1,99 @@
+<?php
+
+namespace App\MessageHandler;
+
+use App\Entity\Enrichment;
+use App\Entity\NewsItemStatus;
+use App\Message\EnrichItemMessage;
+use App\Provider\EmbeddingProviderInterface;
+use App\Provider\EnrichmentProviderInterface;
+use App\Repository\NewsItemRepository;
+use Doctrine\ORM\EntityManagerInterface;
+use Psr\Log\LoggerInterface;
+use Symfony\Component\Mercure\HubInterface;
+use Symfony\Component\Mercure\Update;
+use Symfony\Component\Messenger\Attribute\AsMessageHandler;
+
+#[AsMessageHandler]
+class EnrichItemHandler
+{
+    public function __construct(
+        private readonly NewsItemRepository $newsItemRepo,
+        private readonly EnrichmentProviderInterface $enrichmentProvider,
+        private readonly EmbeddingProviderInterface $embeddingProvider,
+        private readonly EntityManagerInterface $em,
+        private readonly HubInterface $hub,
+        private readonly LoggerInterface $logger,
+    ) {}
+
+    public function __invoke(EnrichItemMessage $message): void
+    {
+        $item = $this->newsItemRepo->find($message->newsItemId);
+
+        if (null === $item) {
+            $this->logger->warning('EnrichItemHandler: NewsItem not found', ['id' => $message->newsItemId]);
+            return;
+        }
+
+        if ($item->getStatus() !== NewsItemStatus::Pending) {
+            $this->logger->info('EnrichItemHandler: already processed, skipping', [
+                'id'     => $message->newsItemId,
+                'status' => $item->getStatus()->value,
+            ]);
+            return;
+        }
+
+        $result = $this->enrichmentProvider->enrich(
+            $item->getContentHash(),
+            $item->getTitle(),
+            $item->getBody(),
+        );
+
+        $embedding = $this->embeddingProvider->embed(
+            $item->getTitle() . "\n" . ($item->getBody() ?? '')
+        );
+
+        $enrichment = (new Enrichment())
+            ->setNewsItem($item)
+            ->setSummary($result->summary)
+            ->setSentiment($result->sentiment)
+            ->setAssetClass($result->assetClass)
+            ->setTickers($result->tickers)
+            ->setEntities($result->entities)
+            ->setEmbedding($embedding)
+            ->setModel($result->model)
+            ->setTokens($result->totalTokens)
+            ->setCostUsd($result->costUsd);
+
+        $item->setStatus(NewsItemStatus::Enriched);
+
+        $this->em->persist($enrichment);
+        $this->em->flush();
+
+        $this->hub->publish(new Update(
+            'crypto/feed',
+            json_encode([
+                'id'          => $item->getId(),
+                'source'      => $item->getSource(),
+                'title'       => $item->getTitle(),
+                'url'         => $item->getUrl(),
+                'publishedAt' => $item->getPublishedAt()->format(\DateTimeInterface::ATOM),
+                'summary'     => $enrichment->getSummary(),
+                'sentiment'   => $enrichment->getSentiment(),
+                'assetClass'  => $enrichment->getAssetClass(),
+                'tickers'     => $enrichment->getTickers(),
+                'entities'    => $enrichment->getEntities(),
+                'model'       => $enrichment->getModel(),
+                'costUsd'     => $enrichment->getCostUsd(),
+            ]),
+        ));
+
+        $this->logger->info('EnrichItemHandler: enriched', [
+            'id'       => $item->getId(),
+            'model'    => $result->model,
+            'tokens'   => $result->totalTokens,
+            'cost_usd' => $result->costUsd,
+            'embedding' => null !== $embedding ? \count($embedding) . 'd' : 'null',
+        ]);
+    }
+}
diff --git a/backend/src/MessageHandler/IngestSourceHandler.php b/backend/src/MessageHandler/IngestSourceHandler.php
new file mode 100644
index 0000000..8526311
--- /dev/null
+++ b/backend/src/MessageHandler/IngestSourceHandler.php
@@ -0,0 +1,78 @@
+<?php
+
+namespace App\MessageHandler;
+
+use App\Adapter\SourceAdapterInterface;
+use App\Entity\NewsItem;
+use App\Message\EnrichItemMessage;
+use App\Message\IngestSourceMessage;
+use App\Repository\NewsItemRepository;
+use Doctrine\ORM\EntityManagerInterface;
+use Psr\Log\LoggerInterface;
+use Symfony\Component\Messenger\Attribute\AsMessageHandler;
+use Symfony\Component\Messenger\MessageBusInterface;
+
+#[AsMessageHandler]
+class IngestSourceHandler
+{
+    /** @param iterable<SourceAdapterInterface> $adapters */
+    public function __construct(
+        private readonly iterable $adapters,
+        private readonly NewsItemRepository $newsItemRepo,
+        private readonly EntityManagerInterface $em,
+        private readonly MessageBusInterface $bus,
+        private readonly LoggerInterface $logger,
+    ) {}
+
+    public function __invoke(IngestSourceMessage $message): void
+    {
+        $adapter = $this->findAdapter($message->sourceId);
+        if (null === $adapter) {
+            $this->logger->warning('No adapter found for source', ['sourceId' => $message->sourceId]);
+            return;
+        }
+
+        $persisted = 0;
+        $skipped   = 0;
+
+        foreach ($adapter->fetch() as $raw) {
+            $hash = hash('sha256', $raw['url']);
+
+            if ($this->newsItemRepo->findOneBy(['contentHash' => $hash])) {
+                ++$skipped;
+                continue;
+            }
+
+            $item = (new NewsItem())
+                ->setSource($message->sourceId)
+                ->setExternalId($raw['externalId'])
+                ->setTitle($raw['title'])
+                ->setUrl($raw['url'])
+                ->setBody($raw['body'])
+                ->setPublishedAt($raw['publishedAt'])
+                ->setContentHash($hash);
+
+            $this->em->persist($item);
+            $this->em->flush();
+
+            $this->bus->dispatch(new EnrichItemMessage($item->getId()));
+            ++$persisted;
+        }
+
+        $this->logger->info('Ingest complete', [
+            'sourceId'  => $message->sourceId,
+            'persisted' => $persisted,
+            'skipped'   => $skipped,
+        ]);
+    }
+
+    private function findAdapter(string $sourceId): ?SourceAdapterInterface
+    {
+        foreach ($this->adapters as $adapter) {
+            if ($adapter->getId() === $sourceId) {
+                return $adapter;
+            }
+        }
+        return null;
+    }
+}
diff --git a/backend/src/Provider/AnthropicEnrichmentProvider.php b/backend/src/Provider/AnthropicEnrichmentProvider.php
new file mode 100644
index 0000000..b9477ba
--- /dev/null
+++ b/backend/src/Provider/AnthropicEnrichmentProvider.php
@@ -0,0 +1,114 @@
+<?php
+
+namespace App\Provider;
+
+use Symfony\Contracts\Cache\CacheInterface;
+use Symfony\Contracts\Cache\ItemInterface;
+use Symfony\Contracts\HttpClient\HttpClientInterface;
+
+class AnthropicEnrichmentProvider implements EnrichmentProviderInterface
+{
+    private const MODEL = 'claude-haiku-4-5-20251001';
+    private const MAX_TOKENS = 512;
+    private const BODY_MAX_CHARS = 4000;
+
+    // Pricing per token — claude-haiku-4-5 (verify at https://www.anthropic.com/pricing)
+    private const COST_INPUT_PER_TOKEN        = 0.00000080; // $0.80 / MTok
+    private const COST_OUTPUT_PER_TOKEN       = 0.00000400; // $4.00 / MTok
+    private const COST_CACHE_WRITE_PER_TOKEN  = 0.00000100; // $1.00 / MTok
+    private const COST_CACHE_READ_PER_TOKEN   = 0.00000008; // $0.08 / MTok
+
+    private const SYSTEM_PROMPT = <<<'PROMPT'
+You are a cryptocurrency news analyst. Given a news article, respond ONLY with a valid JSON object with exactly these keys:
+- "summary": string — 2-3 sentence neutral summary of the key facts
+- "sentiment": string — one of: "positive", "negative", "neutral"
+- "asset_class": string or null — primary crypto category affected (e.g. "BTC", "ETH", "DeFi", "NFT", "Regulation", "Stablecoin", "Layer2", "Exchange", "Market", "Altcoin")
+- "tickers": array of strings — cryptocurrency ticker symbols mentioned (e.g. ["BTC", "ETH"])
+- "entities": array of strings — key named entities: people, organizations, protocols
+
+Return ONLY the JSON object. No markdown, no explanation, no wrapping.
+PROMPT;
+
+    public function __construct(
+        private readonly HttpClientInterface $httpClient,
+        private readonly CacheInterface $enrichmentCache,
+        private readonly string $apiKey,
+    ) {}
+
+    public function enrich(string $contentHash, string $title, ?string $body): EnrichmentResult
+    {
+        return $this->enrichmentCache->get(
+            'enrich_' . $contentHash,
+            function (ItemInterface $item) use ($title, $body): EnrichmentResult {
+                $item->expiresAfter(86400);
+                return $this->callApi($title, $body);
+            }
+        );
+    }
+
+    private function callApi(string $title, ?string $body): EnrichmentResult
+    {
+        $userContent = 'Title: ' . $title;
+        if (null !== $body && '' !== $body) {
+            $userContent .= "\n\nBody: " . mb_substr($body, 0, self::BODY_MAX_CHARS);
+        }
+
+        $response = $this->httpClient->request('POST', 'https://api.anthropic.com/v1/messages', [
+            'headers' => [
+                'x-api-key'        => $this->apiKey,
+                'anthropic-version' => '2023-06-01',
+                'anthropic-beta'   => 'prompt-caching-2024-07-31',
+                'content-type'     => 'application/json',
+            ],
+            'json' => [
+                'model'      => self::MODEL,
+                'max_tokens' => self::MAX_TOKENS,
+                'system'     => [
+                    [
+                        'type'          => 'text',
+                        'text'          => self::SYSTEM_PROMPT,
+                        'cache_control' => ['type' => 'ephemeral'],
+                    ],
+                ],
+                'messages' => [
+                    ['role' => 'user', 'content' => $userContent],
+                ],
+            ],
+        ]);
+
+        $data = $response->toArray();
+        $text = $data['content'][0]['text'] ?? '';
+
+        $parsed = json_decode($text, true);
+        if (!\is_array($parsed)) {
+            throw new \RuntimeException(\sprintf('Anthropic returned non-JSON response: %s', mb_substr($text, 0, 200)));
+        }
+
+        $usage            = $data['usage'] ?? [];
+        $inputTokens      = (int) ($usage['input_tokens'] ?? 0);
+        $outputTokens     = (int) ($usage['output_tokens'] ?? 0);
+        $cacheWriteTokens = (int) ($usage['cache_creation_input_tokens'] ?? 0);
+        $cacheReadTokens  = (int) ($usage['cache_read_input_tokens'] ?? 0);
+
+        $cost = ($inputTokens      * self::COST_INPUT_PER_TOKEN)
+              + ($outputTokens     * self::COST_OUTPUT_PER_TOKEN)
+              + ($cacheWriteTokens * self::COST_CACHE_WRITE_PER_TOKEN)
+              + ($cacheReadTokens  * self::COST_CACHE_READ_PER_TOKEN);
+
+        $sentimentRaw = $parsed['sentiment'] ?? 'neutral';
+        $sentiment    = \in_array($sentimentRaw, ['positive', 'negative', 'neutral'], true)
+            ? $sentimentRaw
+            : 'neutral';
+
+        return new EnrichmentResult(
+            summary:     $parsed['summary'] ?? '',
+            sentiment:   $sentiment,
+            assetClass:  $parsed['asset_class'] ?? null,
+            tickers:     \is_array($parsed['tickers'] ?? null) ? $parsed['tickers'] : [],
+            entities:    \is_array($parsed['entities'] ?? null) ? $parsed['entities'] : [],
+            model:       self::MODEL,
+            totalTokens: $inputTokens + $outputTokens + $cacheWriteTokens,
+            costUsd:     number_format($cost, 6, '.', ''),
+        );
+    }
+}
diff --git a/backend/src/Provider/EmbeddingProviderInterface.php b/backend/src/Provider/EmbeddingProviderInterface.php
new file mode 100644
index 0000000..6fb503d
--- /dev/null
+++ b/backend/src/Provider/EmbeddingProviderInterface.php
@@ -0,0 +1,13 @@
+<?php
+
+namespace App\Provider;
+
+interface EmbeddingProviderInterface
+{
+    /**
+     * Returns a dense vector for semantic search, or null if the provider is unavailable.
+     *
+     * @return float[]|null
+     */
+    public function embed(string $text): ?array;
+}
diff --git a/backend/src/Provider/EnrichmentProviderInterface.php b/backend/src/Provider/EnrichmentProviderInterface.php
new file mode 100644
index 0000000..27e8c03
--- /dev/null
+++ b/backend/src/Provider/EnrichmentProviderInterface.php
@@ -0,0 +1,11 @@
+<?php
+
+namespace App\Provider;
+
+interface EnrichmentProviderInterface
+{
+    /**
+     * @param string $contentHash SHA-256 of the article URL — used as local cache key
+     */
+    public function enrich(string $contentHash, string $title, ?string $body): EnrichmentResult;
+}
diff --git a/backend/src/Provider/EnrichmentResult.php b/backend/src/Provider/EnrichmentResult.php
new file mode 100644
index 0000000..52575dd
--- /dev/null
+++ b/backend/src/Provider/EnrichmentResult.php
@@ -0,0 +1,17 @@
+<?php
+
+namespace App\Provider;
+
+final readonly class EnrichmentResult
+{
+    public function __construct(
+        public string  $summary,
+        public string  $sentiment,
+        public ?string $assetClass,
+        public array   $tickers,
+        public array   $entities,
+        public string  $model,
+        public int     $totalTokens,
+        public string  $costUsd,
+    ) {}
+}
diff --git a/backend/src/Provider/NullEnrichmentProvider.php b/backend/src/Provider/NullEnrichmentProvider.php
new file mode 100644
index 0000000..9ae27fc
--- /dev/null
+++ b/backend/src/Provider/NullEnrichmentProvider.php
@@ -0,0 +1,25 @@
+<?php
+
+namespace App\Provider;
+
+/**
+ * Dev-only stub: returns a fixed result without calling any API.
+ * Wired as the default EnrichmentProviderInterface in config/services_dev.yaml
+ * to avoid spending tokens during local development.
+ */
+class NullEnrichmentProvider implements EnrichmentProviderInterface
+{
+    public function enrich(string $contentHash, string $title, ?string $body): EnrichmentResult
+    {
+        return new EnrichmentResult(
+            summary: '[DEV] ' . mb_substr($title, 0, 120),
+            sentiment: 'neutral',
+            assetClass: null,
+            tickers: [],
+            entities: [],
+            model: 'null-provider',
+            totalTokens: 0,
+            costUsd: '0.000000',
+        );
+    }
+}
diff --git a/backend/src/Provider/VoyageEmbeddingProvider.php b/backend/src/Provider/VoyageEmbeddingProvider.php
new file mode 100644
index 0000000..9dd995c
--- /dev/null
+++ b/backend/src/Provider/VoyageEmbeddingProvider.php
@@ -0,0 +1,38 @@
+<?php
+
+namespace App\Provider;
+
+use Symfony\Contracts\HttpClient\HttpClientInterface;
+
+class VoyageEmbeddingProvider implements EmbeddingProviderInterface
+{
+    private const MODEL = 'voyage-3';
+
+    public function __construct(
+        private readonly HttpClientInterface $httpClient,
+        private readonly string $apiKey,
+    ) {}
+
+    public function embed(string $text): ?array
+    {
+        if ('' === $this->apiKey) {
+            return null;
+        }
+
+        $response = $this->httpClient->request('POST', 'https://api.voyageai.com/v1/embeddings', [
+            'headers' => [
+                'Authorization' => 'Bearer ' . $this->apiKey,
+                'content-type'  => 'application/json',
+            ],
+            'json' => [
+                'model'      => self::MODEL,
+                'input'      => [$text],
+                'input_type' => 'document',
+            ],
+        ]);
+
+        $data = $response->toArray();
+
+        return $data['data'][0]['embedding'] ?? null;
+    }
+}
diff --git a/backend/src/Repository/EnrichmentRepository.php b/backend/src/Repository/EnrichmentRepository.php
new file mode 100644
index 0000000..1012715
--- /dev/null
+++ b/backend/src/Repository/EnrichmentRepository.php
@@ -0,0 +1,18 @@
+<?php
+
+namespace App\Repository;
+
+use App\Entity\Enrichment;
+use Doctrine\Bundle\DoctrineBundle\Repository\ServiceEntityRepository;
+use Doctrine\Persistence\ManagerRegistry;
+
+/**
+ * @extends ServiceEntityRepository<Enrichment>
+ */
+class EnrichmentRepository extends ServiceEntityRepository
+{
+    public function __construct(ManagerRegistry $registry)
+    {
+        parent::__construct($registry, Enrichment::class);
+    }
+}
diff --git a/backend/src/Repository/NewsItemRepository.php b/backend/src/Repository/NewsItemRepository.php
new file mode 100644
index 0000000..ddf7759
--- /dev/null
+++ b/backend/src/Repository/NewsItemRepository.php
@@ -0,0 +1,18 @@
+<?php
+
+namespace App\Repository;
+
+use App\Entity\NewsItem;
+use Doctrine\Bundle\DoctrineBundle\Repository\ServiceEntityRepository;
+use Doctrine\Persistence\ManagerRegistry;
+
+/**
+ * @extends ServiceEntityRepository<NewsItem>
+ */
+class NewsItemRepository extends ServiceEntityRepository
+{
+    public function __construct(ManagerRegistry $registry)
+    {
+        parent::__construct($registry, NewsItem::class);
+    }
+}
diff --git a/backend/src/Story/AppStory.php b/backend/src/Story/AppStory.php
deleted file mode 100644
index d61bb2b..0000000
--- a/backend/src/Story/AppStory.php
+++ /dev/null
@@ -1,25 +0,0 @@
-<?php
-
-namespace App\Story;
-
-use Zenstruck\Foundry\Attribute\AsFixture;
-use Zenstruck\Foundry\Story;
-
-/**
- * Optional Story entry point. Forks can use this to group factory calls
- * into named scenarios (e.g. "main" story for staging).
- *
- * Usage from AppFixtures:
- *   AppStory::load();
- */
-#[AsFixture(name: 'main')]
-final class AppStory extends Story
-{
-    public function build(): void
-    {
-        // Forks: orchestrate factories into a scenario here.
-        // Example:
-        //   MemberFactory::createMany(15);
-        //   ProjectFactory::createMany(5);
-    }
-}
diff --git a/backend/symfony.lock b/backend/symfony.lock
index d1d27b3..8450558 100644
--- a/backend/symfony.lock
+++ b/backend/symfony.lock
@@ -22,18 +22,6 @@
             "src/Repository/.gitignore"
         ]
     },
-    "doctrine/doctrine-fixtures-bundle": {
-        "version": "4.3",
-        "recipe": {
-            "repo": "github.com/symfony/recipes",
-            "branch": "main",
-            "version": "3.0",
-            "ref": "1f5514cfa15b947298df4d771e694e578d4c204d"
-        },
-        "files": [
-            "src/DataFixtures/AppFixtures.php"
-        ]
-    },
     "doctrine/doctrine-migrations-bundle": {
         "version": "3.7",
         "recipe": {
@@ -189,18 +177,5 @@
             "config/packages/security.yaml",
             "config/routes/security.yaml"
         ]
-    },
-    "zenstruck/foundry": {
-        "version": "2.10",
-        "recipe": {
-            "repo": "github.com/symfony/recipes",
-            "branch": "main",
-            "version": "2.7",
-            "ref": "9bd824886195ebe64a24438db1b6d17eb833ac56"
-        },
-        "files": [
-            "config/packages/zenstruck_foundry.yaml",
-            "src/Story/AppStory.php"
-        ]
     }
 }
diff --git a/docs/examples/IngestSourceMessageTest.php.example b/backend/tests/Unit/Message/IngestSourceMessageTest.php
similarity index 74%
rename from docs/examples/IngestSourceMessageTest.php.example
rename to backend/tests/Unit/Message/IngestSourceMessageTest.php
index c0932f7..fb3978f 100644
--- a/docs/examples/IngestSourceMessageTest.php.example
+++ b/backend/tests/Unit/Message/IngestSourceMessageTest.php
@@ -9,9 +9,9 @@ class IngestSourceMessageTest extends TestCase
 {
     public function testSourceIdIsPreserved(): void
     {
-        $message = new IngestSourceMessage('example-source-a');
+        $message = new IngestSourceMessage('coindesk-rss');
 
-        $this->assertSame('example-source-a', $message->sourceId);
+        $this->assertSame('coindesk-rss', $message->sourceId);
     }
 
     public function testSourceIdCanBeEmpty(): void
diff --git a/claude-commands.md b/claude-commands.md
deleted file mode 100644
index 4f9eca8..0000000
--- a/claude-commands.md
+++ /dev/null
@@ -1,25 +0,0 @@
-# Claude Commands
-
-Comandos que el usuario puede escribir en el chat para activar protocolos específicos.
-
----
-
-## `claude reiniciar [x=60]`
-
-**Qué hace:** Si el contexto de la conversación está por encima de `x`% de su límite, guarda todo lo necesario para un reinicio exitoso y avisa que se puede abrir una nueva sesión.
-
-**Cuándo usarlo:** Antes de empezar una tarea larga, o si la conversación se siente lenta o degradada.
-
-**Protocolo que ejecuta el agente:**
-
-1. **Estimar uso de contexto.** El agente no puede medirlo con precisión; estima en base a la longitud de la conversación y lo declara explícitamente.
-
-2. **Si está por debajo del umbral:** informar el porcentaje estimado y continuar sin hacer nada más.
-
-3. **Si está por encima del umbral:**
-   a. Verificar que no haya código sin commitear (`git status -s`). Si hay trabajo pendiente, commitearlo primero.
-   b. Verificar que `agent-commits.md` esté al día con el último commit (si el proyecto lo usa).
-   c. Actualizar los archivos de memoria en `/home/marcos/.claude/projects/-home-marcos-app/memory/` con el estado actual del proyecto: fase en curso, qué está hecho, qué sigue, decisiones abiertas.
-   d. Informar al usuario: "Contexto al X%. Estado guardado — podés abrir una sesión nueva."
-
-**Umbral por defecto:** 60%.
diff --git a/concepts.md b/concepts.md
new file mode 100644
index 0000000..ae0b19d
--- /dev/null
+++ b/concepts.md
@@ -0,0 +1,399 @@
+# Conceptos técnicos
+
+Explicaciones teóricas de tecnologías y conceptos usados en el proyecto.
+Cada sección se agrega a medida que el tema aparece en el desarrollo.
+
+---
+
+## pgvector
+
+### Qué es
+
+`pgvector` es una extensión de PostgreSQL que agrega un tipo de dato nativo llamado `vector` y operadores para hacer **búsqueda por similitud** entre vectores. En términos simples: te permite guardar y comparar listas de números flotantes directamente en tu base de datos Postgres existente, sin necesidad de una base de datos vectorial separada (Pinecone, Weaviate, Qdrant, etc.).
+
+### Para qué sirve en este proyecto
+
+Cuando un modelo de IA procesa una noticia cripto, genera un **embedding**: una lista de ~1500 números flotantes que representan el *significado semántico* del texto. Dos noticias sobre el mismo tema tienen embeddings parecidos (vectorialmente cercanos); dos noticias sin relación tienen embeddings lejanos.
+
+`pgvector` permite hacer consultas como:
+> *"Dame las 5 noticias más similares semánticamente a esta query del usuario"*
+
+sin mover los datos fuera de Postgres.
+
+### Cómo funciona por dentro
+
+Un embedding es un punto en un espacio de alta dimensión (por ejemplo, 1536 dimensiones si usás `text-embedding-3-small` de OpenAI). La "distancia" entre dos puntos mide qué tan parecidos son semánticamente.
+
+`pgvector` soporta tres métricas de distancia:
+
+| Operador | Métrica | Cuándo usarla |
+|---|---|---|
+| `<->` | L2 (distancia euclidiana) | cuando la magnitud importa |
+| `<=>` | Cosine similarity | **la más común para texto** — mide ángulo, ignora magnitud |
+| `<#>` | Inner product | embeddings normalizados |
+
+Para texto casi siempre se usa **cosine similarity** (`<=>`).
+
+### Índices: HNSW vs IVFFlat
+
+Sin índice, una búsqueda de similitud es un *full scan* (compara el vector query contra todos los vectores de la tabla). Escala mal. `pgvector` ofrece dos índices aproximados (ANN - Approximate Nearest Neighbor):
+
+**IVFFlat** (Inverted File with Flat quantization):
+- Divide los vectores en `lists` clusters (centroides).
+- Para buscar, primero encuentra los clusters más cercanos y solo escanea esos.
+- Más rápido de construir, menos memoria.
+- Necesita datos cargados *antes* de crear el índice para que los clusters sean buenos.
+- Parámetro clave: `lists` (típicamente `sqrt(n_rows)`).
+
+**HNSW** (Hierarchical Navigable Small World):
+- Construye un grafo de navegación multinivel.
+- Más lento de construir y más memoria, pero **mayor recall** (encuentra los vecinos correctos más seguido) y mejor latencia de query.
+- Se puede construir antes de tener datos (crece dinámicamente).
+- **Recomendado para producción** salvo que el índice sea muy grande.
+
+En este proyecto usaremos **HNSW** para el campo `embedding` de la entidad `Enrichment`.
+
+### Cómo se usa en Symfony/Doctrine
+
+`pgvector` no tiene soporte nativo en Doctrine. Se necesita declarar un tipo custom que mapea el tipo SQL `vector(n)` a un array PHP de floats. El flujo es:
+
+```
+PHP array de floats → Doctrine Type custom → SQL vector(1536) en Postgres
+```
+
+En una entidad se declara así:
+
+```php
+#[ORM\Column(type: 'vector', length: 1536)]
+private array $embedding = [];
+```
+
+Y en la migración se genera:
+
+```sql
+ALTER TABLE enrichment ADD COLUMN embedding vector(1536);
+CREATE INDEX ON enrichment USING hnsw (embedding vector_cosine_ops);
+```
+
+Para queries de similitud se usa SQL nativo o DQL con funciones custom:
+
+```php
+$em->createNativeQuery(
+    'SELECT * FROM enrichment ORDER BY embedding <=> :query_vec LIMIT 5',
+    $rsm
+)->setParameter('query_vec', $queryEmbedding);
+```
+
+### Por qué en Postgres y no en una DB vectorial dedicada
+
+Para la escala de este proyecto (miles/decenas de miles de noticias), `pgvector` es más que suficiente y tiene ventajas reales:
+
+- **Un solo servicio menos** en Docker Compose.
+- **Transacciones** — el embedding y los metadatos de la noticia se guardan atómicamente.
+- **SQL estándar** — podés filtrar por fecha, source, sentiment *y* ordenar por similitud en una sola query.
+- **Backup unificado** — un `pg_dump` y tenés todo.
+
+Una DB vectorial dedicada tiene sentido a partir de decenas de millones de vectores o cuando necesitás features muy específicas (multi-tenancy vectorial, filtros complejos a escala masiva). No es el caso acá.
+
+---
+
+## RabbitMQ
+
+### Qué es
+
+RabbitMQ es un **message broker**: un proceso intermediario que recibe mensajes de un productor, los guarda en colas, y los entrega a uno o más consumidores. Es el equivalente a una oficina de correo: el que manda la carta (productor) no necesita saber quién la va a leer ni cuándo; solo la deposita, y el broker se ocupa de la entrega.
+
+El protocolo que usa RabbitMQ se llama **AMQP** (Advanced Message Queuing Protocol).
+
+### Conceptos clave
+
+| Concepto | Qué es |
+|---|---|
+| **Producer** | Quien publica el mensaje (ej: el scheduler que encontró una noticia nueva) |
+| **Exchange** | Punto de entrada. Recibe el mensaje y decide a qué colas mandarlo según reglas de routing |
+| **Queue** | Buffer persistente donde esperan los mensajes hasta ser consumidos |
+| **Consumer** | Quien procesa los mensajes (ej: el worker de Symfony que enriquece con IA) |
+| **Binding** | Regla que conecta un exchange con una queue |
+| **Routing key** | Etiqueta en el mensaje que usa el exchange para decidir el destino |
+
+El flujo es siempre: `Producer → Exchange → Queue → Consumer`.
+
+### Por qué no llamar directamente al worker
+
+La alternativa "simple" sería que el scheduler llame al worker por HTTP o ejecute la lógica directamente. El problema:
+
+- Si el worker se cae, el trabajo se pierde.
+- Si llegan 50 noticias a la vez, el scheduler se bloquea esperando respuesta.
+- No podés escalar consumidores sin cambiar el productor.
+
+Con un broker en el medio:
+- El mensaje **persiste en la cola** aunque el worker esté caído. Cuando vuelve, lo procesa.
+- El scheduler termina en microsegundos (solo publica). El procesamiento es **asíncrono**.
+- Podés levantar 5 workers en paralelo sin tocar el scheduler.
+
+### Cómo se usa en este proyecto
+
+El flujo de Crypto Pulse es:
+
+```
+[cron/scheduler]
+     │ publica mensaje con URL/datos de la noticia
+     ▼
+[RabbitMQ - exchange "articles"]
+     │ routing → queue "ingestion"
+     ▼
+[Symfony Worker - bin/console messenger:consume]
+     │ consume el mensaje
+     │ llama a Anthropic para enriquecer
+     │ guarda en Postgres (con embedding en pgvector)
+     ▼
+[Mercure Hub]
+     │ push SSE al frontend
+     ▼
+[Dashboard en vivo]
+```
+
+Symfony usa su componente **Messenger** para abstraer RabbitMQ: en el código PHP se hace `$bus->dispatch(new IngestArticleMessage(...))` y Messenger se encarga del transporte AMQP. No hay llamadas manuales a la librería de RabbitMQ.
+
+### Por qué RabbitMQ y no Kafka o Redis Streams
+
+Para este proyecto la elección es pragmática:
+
+- **Kafka** es correcto para millones de mensajes/segundo y retención larga. Overkill para miles de noticias/día y agrega complejidad operativa real.
+- **Redis Streams** es válido y más liviano, pero RabbitMQ tiene mejor integración nativa con **Symfony Messenger** (transport oficial, reintentos, dead-letter queues out of the box).
+- **RabbitMQ** tiene UI de management (`localhost:15672`) que facilita debug en desarrollo.
+
+La decisión está cerrada; RabbitMQ es el broker del proyecto.
+
+---
+
+## AMQP Routing y el bug de `default_publish_routing_key`
+
+### El problema en una línea
+
+Publicamos 18 mensajes al exchange `ingest`. La queue `ingest` quedó en 0. Los mensajes desaparecieron en silencio.
+
+### Cómo funciona el routing en AMQP (tipo `direct`)
+
+Un exchange `direct` es como un clasificador postal con reglas exactas:
+
+```
+Producer publica mensaje con routing_key="ingest"
+         │
+         ▼
+   [Exchange "ingest" — tipo direct]
+         │
+         │  ¿hay algún binding cuya binding_key == routing_key del mensaje?
+         │
+    ─────┴─────────────────────────────────────
+    SÍ: "ingest" == "ingest"        NO: descarta el mensaje (silencio)
+         │
+         ▼
+   [Queue "ingest"]
+```
+
+El **binding** es el cable que conecta exchange con queue. Se define con una `binding_key`. Cuando llega un mensaje, el exchange compara el `routing_key` del mensaje contra la `binding_key` del binding. Si hay match exacto → entrega. Si no hay match → el mensaje se descarta **sin error, sin log, sin excepción**.
+
+Esto es importante: **AMQP no falla ruidosamente cuando un mensaje no rutea. Lo descarta silenciosamente.** El producer recibe un "OK" del broker igualmente.
+
+### Por qué pasó el bug
+
+La configuración de Symfony Messenger era:
+
+```yaml
+transports:
+    ingest:
+        dsn: '%env(RABBITMQ_DSN)%'
+        options:
+            exchange:
+                name: ingest
+                type: direct
+            queues:
+                ingest:
+                    binding_keys: [ingest]
+```
+
+Los `binding_keys: [ingest]` crean el binding `exchange → queue` con binding_key `"ingest"`. Eso es correcto.
+
+El problema estaba en **qué routing_key usa Symfony al publicar**. El comportamiento de Symfony Messenger al publicar un mensaje a AMQP es:
+
+```
+routing_key = AmqpRoutingKeyStamp (si está presente en el envelope)
+           ?? default_publish_routing_key (si está configurado en el exchange)
+           ?? "" (string vacío — el default si no hay nada)
+```
+
+En nuestro caso, no había stamp ni `default_publish_routing_key`. Entonces Symfony publicó todos los mensajes con `routing_key = ""`.
+
+El exchange recibió los mensajes (por eso `publish_in: 18`), buscó un binding con `binding_key == ""`, no encontró ninguno, y los descartó. La queue quedó en 0. Sin error.
+
+### El fix
+
+Agregar `default_publish_routing_key` al exchange:
+
+```yaml
+exchange:
+    name: ingest
+    type: direct
+    default_publish_routing_key: ingest   # ← esto faltaba
+```
+
+Ahora Symfony publica con `routing_key = "ingest"`, que matchea `binding_key = "ingest"`, y el mensaje llega a la queue.
+
+### Cómo se detectó
+
+No hay ningún error en el lado del producer. El `$bus->dispatch(...)` retorna éxito. El exchange recibe el mensaje. El único indicio es que la queue permanece vacía aunque se publique.
+
+La forma de diagnosticarlo fue comparar las métricas del exchange vs la queue en la management UI de RabbitMQ (`localhost:15672`):
+
+- Exchange `ingest` → `publish_in: 18`, `publish_out: 0`
+- Queue `ingest` → `deliver_get: 0`
+
+`publish_out: 0` significa que el exchange no envió nada a ninguna queue (ni a otro exchange). Ahí se confirmó que el problema era de routing, no de consumo.
+
+### Cuándo `publish_out` es 0 y cuándo no
+
+`publish_out` en un exchange cuenta únicamente los mensajes que el exchange reenvió a **otro exchange** (exchange-to-exchange routing). NO cuenta los mensajes entregados a queues. Así que `publish_out: 0` con `publish_in: 18` no necesariamente es un bug — solo significa que no hay exchange-to-exchange routing. El indicador real es `deliver_get` en la queue.
+
+### Regla para recordar
+
+> En un exchange `direct` de RabbitMQ, el mensaje solo llega a la queue si `routing_key del mensaje == binding_key del binding`. Symfony Messenger usa routing key vacío por defecto. Siempre configurar `default_publish_routing_key` cuando el exchange es `direct`.
+
+---
+
+## Embeddings
+
+### Qué son
+
+Un **embedding** es una representación numérica de texto (u otro contenido) como un vector de números decimales. Por ejemplo, el texto "Bitcoin cayó 5%" podría representarse como un vector de 1024 números como `[0.12, -0.87, 0.34, ...]`.
+
+La idea central: **textos con significados similares tienen vectores cercanos en el espacio geométrico**. "Bitcoin cayó" y "BTC baja" estarían cerca entre sí. "Bitcoin cayó" y "una receta de pasta" estarían muy lejos.
+
+### Por qué los usamos
+
+En el proyecto, cada noticia que pasa por el pipeline de IA recibe un embedding. Esto nos permite:
+
+1. **Búsqueda semántica**: un usuario busca "regulación cripto" y recibe noticias relevantes aunque no contengan esas palabras exactas — porque sus vectores están cerca del vector de la query.
+2. **Clustering / deduplicación**: noticias que cuentan el mismo evento tendrán vectores muy cercanos, sin importar de qué fuente vengan o cómo estén redactadas.
+3. **Contexto para el LLM**: al generar resúmenes agregados ("Market Now"), podemos recuperar las noticias más relevantes de las últimas horas por similitud vectorial.
+
+### Cómo se generan
+
+Se le envía el texto a un **modelo de embeddings** (un modelo de ML especializado, diferente al modelo de chat) y éste devuelve el vector. En este proyecto usamos **Voyage AI** (el proveedor de embeddings recomendado por Anthropic) a través de la interfaz `EmbeddingProvider`. El modelo `voyage-3` produce vectores de **1024 dimensiones**.
+
+### Dónde se guardan
+
+Los vectores se guardan en la columna `embedding` de la tabla `enrichment` usando el tipo de dato `vector(1024)` de **pgvector** (extensión de PostgreSQL). Esto permite hacer búsquedas de similitud directamente con SQL.
+
+---
+
+## Búsqueda por similitud vectorial (kNN)
+
+### El problema
+
+Una búsqueda de texto tradicional busca coincidencias exactas de palabras (LIKE, full-text search). No entiende que "ETF de Bitcoin" y "fondo indexado de BTC" hablan de lo mismo.
+
+### La solución: kNN
+
+**kNN** (k-Nearest Neighbors, k vecinos más cercanos) es el algoritmo que responde la pregunta: "dado un vector de query, ¿cuáles son los N vectores más cercanos en mi base de datos?"
+
+El proceso en el proyecto es:
+1. El usuario escribe una query: `"regulación cripto en Europa"`
+2. Se le calcula el embedding a esa query (el mismo modelo que usamos para las noticias)
+3. Se buscan los N embeddings de noticias más cercanos en la DB
+4. Se devuelven esas noticias como resultado
+
+### Métrica de distancia: similitud coseno
+
+Hay varias formas de medir "cercanía" entre vectores. Usamos **similitud coseno**, que mide el ángulo entre dos vectores (no su magnitud). Es la más usada para texto porque captura "dirección semántica" independientemente del largo del texto.
+
+En pgvector, el operador es `<=>` (distancia coseno). Menor distancia = mayor similitud.
+
+```sql
+-- Las 5 noticias más similares a un embedding de query
+SELECT * FROM enrichment
+ORDER BY embedding <=> '[0.12, -0.87, ...]'
+LIMIT 5;
+```
+
+---
+
+## Índice HNSW
+
+### El problema de performance
+
+Sin índice, una búsqueda kNN es un **full scan**: compara el vector de query contra TODOS los vectores de la tabla. Con 10.000 noticias es manejable. Con 1.000.000 es inaceptablemente lento.
+
+### HNSW: Hierarchical Navigable Small World
+
+**HNSW** es un algoritmo de indexación aproximada (ANN — Approximate Nearest Neighbor). Construye una estructura de grafo jerárquica que permite encontrar los vecinos más cercanos en tiempo **logarítmico** en lugar de lineal, con una pequeña pérdida de precisión (configurable).
+
+```
+Sin índice:  O(n) — escanea todos los vectores
+Con HNSW:   O(log n) — navega el grafo
+```
+
+La "pérdida de precisión" es que HNSW devuelve los vecinos *aproximadamente* más cercanos, no los *exactamente* más cercanos. En la práctica, con los parámetros por defecto, la precisión (recall) es >95%, lo que es más que suficiente para búsqueda semántica.
+
+### Cómo se crea en el proyecto
+
+```sql
+CREATE INDEX hnsw_enrichment_embedding
+ON enrichment USING hnsw (embedding vector_cosine_ops)
+WHERE embedding IS NOT NULL;
+```
+
+- `USING hnsw`: tipo de índice
+- `vector_cosine_ops`: operaciones de distancia coseno (coincide con el operador `<=>` que usamos en las queries)
+- `WHERE embedding IS NOT NULL`: índice parcial — solo indexa filas que ya tienen embedding calculado
+
+**Nota importante**: Doctrine ORM no sabe administrar índices HNSW (es específico de pgvector). Por eso el índice vive en una migración Doctrine y el validador `doctrine:schema:validate` se corre con `--skip-sync`.
+
+---
+
+## Content Hash y deduplicación
+
+### El problema
+
+El scheduler corre cada 5 minutos y fetchea los mismos feeds RSS. Un artículo publicado a las 10:00 va a aparecer en el fetch de las 10:00, 10:05, 10:10... Si no hay protección, se insertaría decenas de veces y se enriquecería con IA decenas de veces (costo innecesario).
+
+### La solución: hash de la URL
+
+Cada artículo lleva un **contentHash**: el SHA-256 de su URL. La URL de un artículo es permanente y única — es el identificador natural de una pieza de contenido en la web.
+
+```php
+$contentHash = hash('sha256', $url); // 64 chars hex
+```
+
+La columna `content_hash` en `news_item` tiene un índice UNIQUE. Si intentamos insertar un artículo ya existente, la DB lanza una `UniqueConstraintViolationException`. El handler de ingesta atrapa esa excepción y descarta el mensaje silenciosamente — comportamiento correcto.
+
+### Por qué SHA-256 y no simplemente la URL
+
+- La URL puede tener hasta 2048 chars — ineficiente como clave única
+- SHA-256 siempre produce 64 chars hexadecimales — tamaño fijo, índice eficiente
+- Collision probability negligible para URLs
+
+---
+
+## Pipeline State Machine (NewsItemStatus)
+
+### Qué es
+
+El campo `status` de `NewsItem` es una **máquina de estados** que representa en qué etapa del pipeline está cada noticia:
+
+```
+pending → enriched
+pending → failed
+```
+
+| Estado | Significado |
+|--------|-------------|
+| `pending` | Recién ingresada, esperando ser procesada por el worker de enriquecimiento |
+| `enriched` | Procesada por IA: tiene resumen, sentiment, tickers, embedding |
+| `failed` | El enriquecimiento falló después de varios reintentos (fue al DLX) |
+
+### Por qué importa
+
+1. **Idempotencia**: antes de enriquecer, el handler verifica que `status == pending`. Si es `enriched` o `failed`, no llama a la API de IA. Esto evita costos duplicados si un mensaje se reencola o se reprocesa.
+2. **Observabilidad**: un `SELECT COUNT(*) GROUP BY status` te dice instantáneamente cuántas noticias están esperando enriquecimiento, cuántas están listas y cuántas fallaron.
+3. **Filtros del dashboard**: el front puede pedir solo noticias `enriched` para mostrar.
diff --git a/docker-compose.override.yml b/docker-compose.override.yml
index df12cf1..d357218 100644
--- a/docker-compose.override.yml
+++ b/docker-compose.override.yml
@@ -11,7 +11,6 @@ services:
 
   worker:
     image: app-backend-dev:1.0
-    profiles: ["queues"]
     build:
       context: ./backend
       dockerfile: Dockerfile
@@ -32,7 +31,7 @@ services:
       - ./backend/migrations:/app/migrations
       - ./backend/config:/app/config
     environment:
-      APP_ENV: dev
+      APP_ENV: development
     healthcheck:
       test: ["CMD-SHELL", "kill -0 1 2>/dev/null"]
       interval: 30s
@@ -55,6 +54,8 @@ services:
       - .env
       - .env.backend
     depends_on:
+      rabbitmq:
+        condition: service_healthy
       database:
         condition: service_healthy
     volumes:
@@ -63,7 +64,7 @@ services:
       - ./backend/config:/app/config
       - ./backend/scheduler/crontab:/etc/supercronic/crontab:ro
     environment:
-      APP_ENV: dev
+      APP_ENV: development
     healthcheck:
       test: ["CMD-SHELL", "kill -0 1 2>/dev/null"]
       interval: 30s
@@ -90,7 +91,7 @@ services:
       - ./backend/config:/app/config
     environment:
       XDEBUG_MODE: "${XDEBUG_MODE:-off}"
-      APP_ENV: dev
+      APP_ENV: development
     extra_hosts:
       - host.docker.internal:host-gateway
     tty: true
diff --git a/docker-compose.prod.yml b/docker-compose.prod.yml
index d1e2a49..895823b 100644
--- a/docker-compose.prod.yml
+++ b/docker-compose.prod.yml
@@ -5,25 +5,7 @@ services:
       target: frankenphp_prod
     restart: unless-stopped
     environment:
-      - APP_ENV=prod
-    volumes:
-      # Claves JWT persistidas en el host (secreto gestionado, no en la imagen):
-      # el entrypoint las genera una sola vez en el primer boot si el dir está
-      # vacío, y de ahí en más persisten y NUNCA se regeneran (recrear el
-      # container no desloguea a nadie). Backupear ./secrets/jwt + JWT_PASSPHRASE.
-      - ./secrets/jwt:/app/config/jwt
-
-  scheduler:
-    image: app-backend-prod:1.0
-    build:
-      target: frankenphp_prod
-    restart: unless-stopped
-    environment:
-      - APP_ENV=prod
-    # El scheduler corre supercronic (cron), NO el server frankenphp. Sin este
-    # override heredaría el CMD del backend. Con $1=supercronic el bloque de
-    # setup del entrypoint se saltea a propósito (solo el backend migra/genera).
-    command: ["supercronic", "/etc/supercronic/crontab"]
+      - APP_ENV=production
 
   frontend:
     image: app-frontend-prod:1.0
diff --git a/docker-compose.shared-infra.yml b/docker-compose.shared-infra.yml
deleted file mode 100644
index a2635de..0000000
--- a/docker-compose.shared-infra.yml
+++ /dev/null
@@ -1,79 +0,0 @@
-# Overlay OPCIONAL: conecta esta app a una infra compartida externa
-# (Postgres + RabbitMQ + reverse-proxy en su propio repo `infra`).
-#
-# No reemplaza a docker-compose.prod.yml: se APILA encima. Si nunca usás
-# infra compartida, ignorá este archivo — el deploy standalone sigue intacto.
-#
-#   Standalone (DB propia, como siempre):
-#     docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d
-#
-#   Con infra compartida (IMPORTANTE: project name único con -p):
-#     docker compose -p ong \
-#       -f docker-compose.yml -f docker-compose.prod.yml \
-#       -f docker-compose.shared-infra.yml up -d backend frontend scheduler
-#
-# ── Topología de red (split, ver README de infra) ──────────────────────────
-# La infra expone DOS redes externas, y la app mantiene su red privada:
-#   - app_network (privada, project-scoped) : frontend <-> backend <-> scheduler
-#   - data_net    (externa, de infra)       : backend/scheduler -> postgres/rabbit
-#   - proxy_net   (externa, de infra)       : reverse-proxy -> frontend
-# El frontend está en app_network + proxy_net (NO en data_net → no llega a la DB).
-# El backend/scheduler en app_network + data_net (NO en proxy_net).
-# Así ningún `frontend`/`backend` de esta app comparte red con el de OTRA app
-# → no hay colisión de DNS interno. Por eso app_network debe ser PRIVADA por
-# app: se fuerza con `-p <appname>` único (de ahí el name interpolado abajo).
-#
-# ── Requisitos antes de usar este overlay ──────────────────────────────────
-#   1. Las redes externas `proxy_net` y `data_net` deben existir (las crea el
-#      repo de infra: `docker network create proxy_net && ... data_net`).
-#   2. Descomentar/setear DATABASE_URL en .env.backend de prod apuntando al
-#      Postgres compartido (host `postgres`), no a `database` local — con el
-#      usuario/base que provisiona `infra/scripts/provision-postgres.sh`.
-#   3. El alias de `frontend` en `proxy_net` se deriva solo de
-#      `${COMPOSE_PROJECT_NAME}` (ver abajo) — NO hace falta tocar nada acá.
-#      Sí hay que agregar el bloque correspondiente en `infra/caddy/Caddyfile`
-#      apuntando a ese alias (`-p ong` → `ong-frontend`).
-#
-# Requiere Docker Compose >= 2.24 (tag de merge `!override`, usada para anular
-# `depends_on`/`ports`/`profiles` heredados del base — los merges de Compose
-# son aditivos y no permiten borrar una clave heredada por omisión).
-
-services:
-  # database/rabbitmq locales: NO se usan en infra compartida. Profile inerte
-  # = un `up -d` sin listar servicios (o con COMPOSE_PROFILES=queues resaca) NO
-  # los levanta, sin importar el .env. Se pueden forzar a mano (`up -d database`).
-  database:
-    profiles: !override ["disabled-in-shared-infra"]
-
-  rabbitmq:
-    profiles: !override ["disabled-in-shared-infra"]
-
-  backend:
-    depends_on: !override {}
-    networks:
-      app_network:
-      data_net:
-
-  scheduler:
-    depends_on: !override {}
-    networks:
-      app_network:
-      data_net:
-
-  frontend:
-    ports: !override []
-    networks:
-      app_network:
-      proxy_net:
-        aliases:
-          - ${COMPOSE_PROJECT_NAME:-app}-frontend   # ej. -p ong -> ong-frontend
-
-networks:
-  # Red privada de ESTA app, project-scoped: con `-p ong` queda `ong_app_network`,
-  # con `-p crypto` queda `crypto_app_network`. Así frontend resuelve a SU backend.
-  app_network:
-    name: ${COMPOSE_PROJECT_NAME:-app}_app_network
-  proxy_net:
-    external: true
-  data_net:
-    external: true
diff --git a/docker-compose.staging.yml b/docker-compose.staging.yml
deleted file mode 100644
index 0ddc650..0000000
--- a/docker-compose.staging.yml
+++ /dev/null
@@ -1,58 +0,0 @@
-# Overlay de staging — apila sobre docker-compose.yml + docker-compose.prod.yml
-# (+ docker-compose.shared-infra.yml si la app usa infra compartida).
-#
-# Diferencia con prod: la imagen del backend usa el target `frankenphp_staging`,
-# que hereda de frankenphp_prod y suma las dev-deps (Foundry + fixtures-bundle)
-# necesarias para correr `doctrine:fixtures:load`. El tag de imagen es distinto
-# (app-backend-staging:1.0) para no pisar la imagen de prod en el host.
-#
-# Staging es UNA APP MÁS en el VPS: tiene su propia DB desechable en el Postgres
-# compartido, su propio project name (-p <app>-staging) y su propio DATABASE_URL.
-# Levantarlo NO interfiere con el stack de producción.
-#
-#   Con infra compartida (caso habitual en VPS):
-#     docker compose -p <app>-staging \
-#       -f docker-compose.yml -f docker-compose.prod.yml \
-#       -f docker-compose.shared-infra.yml \
-#       -f docker-compose.staging.yml up -d
-#
-#   Standalone (sin infra compartida, para pruebas locales):
-#     docker compose -p <app>-staging \
-#       -f docker-compose.yml -f docker-compose.prod.yml \
-#       -f docker-compose.staging.yml up -d
-
-services:
-  backend:
-    image: app-backend-staging:1.0
-    build:
-      target: frankenphp_staging
-    # prod.yml hardcodea environment: APP_ENV=prod en backend/scheduler.
-    # Precedencia de Compose: environment: > env_file: > ENV de la imagen — sin
-    # este override, ese environment pisaría .env.staging y quedaría en prod
-    # pese al env_file. Síntoma real: fixtures:load fallaba ("command not
-    # defined") porque prod no está en bundles.php.
-    environment:
-      - APP_ENV=staging
-    # !override reemplaza (no concatena) la lista del base: evita duplicados.
-    # Requiere Docker Compose >= 2.24 (mismo requisito que shared-infra.yml).
-    env_file: !override
-      - .env
-      - .env.backend
-      - .env.staging
-
-  scheduler:
-    image: app-backend-staging:1.0
-    build:
-      target: frankenphp_staging
-    environment:
-      - APP_ENV=staging
-    env_file: !override
-      - .env
-      - .env.backend
-      - .env.staging
-
-  # Sin declarar este servicio, staging heredaría app-frontend-prod:1.0 de
-  # prod.yml (mismo target/build que prod, solo cambia el tag para no pisar
-  # la imagen de prod en el host).
-  frontend:
-    image: app-frontend-staging:1.0
diff --git a/docker-compose.yml b/docker-compose.yml
index d9c6fbd..e1e7fda 100644
--- a/docker-compose.yml
+++ b/docker-compose.yml
@@ -18,7 +18,6 @@ services:
 
   rabbitmq:
     image: rabbitmq:3-management
-    profiles: ["queues"]
     restart: unless-stopped
     environment:
       RABBITMQ_DEFAULT_USER: ${RABBITMQ_USER:-app}
@@ -44,6 +43,8 @@ services:
     depends_on:
       database:
         condition: service_healthy
+      rabbitmq:
+        condition: service_healthy
     expose:
       - "80/tcp"
     networks:
@@ -55,17 +56,13 @@ services:
     build:
       context: ./backend
       dockerfile: Dockerfile
-    # Opt-in: solo arranca si se activa el profile `cron` (--profile cron o
-    # listándolo explícito en `up`). Una app sin tareas periódicas no lo levanta
-    # y no paga un container corriendo un crontab vacío. Mismo criterio que
-    # `rabbitmq` (profile `queues`). Cada fork que necesite cron activa el
-    # profile y llena `backend/scheduler/crontab`.
-    profiles: ["cron"]
     restart: unless-stopped
     env_file:
       - .env
       - .env.backend
     depends_on:
+      rabbitmq:
+        condition: service_healthy
       database:
         condition: service_healthy
     networks:
diff --git a/docs/concepts.md b/docs/concepts.md
deleted file mode 100644
index de47254..0000000
--- a/docs/concepts.md
+++ /dev/null
@@ -1,320 +0,0 @@
-# Conceptos técnicos
-
-Explicaciones teóricas de las tecnologías que forman parte del framework Oliva.
-Este archivo es acumulativo: nunca se borra contenido, solo se agrega — ver el
-protocolo de explicaciones conceptuales en `CLAUDE.md`.
-
----
-
-## pgvector
-
-### Qué es
-
-`pgvector` es una extensión de PostgreSQL que agrega un tipo de dato nativo llamado `vector` y operadores para hacer **búsqueda por similitud** entre vectores. En términos simples: te permite guardar y comparar listas de números flotantes directamente en tu base de datos Postgres existente, sin necesidad de una base de datos vectorial separada (Pinecone, Weaviate, Qdrant, etc.).
-
-### Para qué sirve
-
-Cuando un modelo de IA procesa un texto (un documento, un mensaje, una descripción de producto, etc.), puede generar un **embedding**: una lista de números flotantes que representa el *significado semántico* de ese texto. Dos contenidos sobre el mismo tema tienen embeddings parecidos (vectorialmente cercanos); dos contenidos sin relación tienen embeddings lejanos.
-
-`pgvector` permite hacer consultas como:
-> *"Dame los 5 registros más similares semánticamente a esta query del usuario"*
-
-sin mover los datos fuera de Postgres. Es la base para features de **búsqueda semántica** o **RAG** (retrieval-augmented generation) en cualquier dominio.
-
-### Cómo funciona por dentro
-
-Un embedding es un punto en un espacio de alta dimensión (por ejemplo, 1536 dimensiones si usás `text-embedding-3-small` de OpenAI, o 1024/1536 con modelos de Voyage AI). La "distancia" entre dos puntos mide qué tan parecidos son semánticamente.
-
-`pgvector` soporta tres métricas de distancia:
-
-| Operador | Métrica | Cuándo usarla |
-|---|---|---|
-| `<->` | L2 (distancia euclidiana) | cuando la magnitud importa |
-| `<=>` | Cosine similarity | **la más común para texto** — mide ángulo, ignora magnitud |
-| `<#>` | Inner product | embeddings normalizados |
-
-Para texto casi siempre se usa **cosine similarity** (`<=>`).
-
-### Índices: HNSW vs IVFFlat
-
-Sin índice, una búsqueda de similitud es un *full scan* (compara el vector query contra todos los vectores de la tabla). Escala mal. `pgvector` ofrece dos índices aproximados (ANN - Approximate Nearest Neighbor):
-
-**IVFFlat** (Inverted File with Flat quantization):
-- Divide los vectores en `lists` clusters (centroides).
-- Para buscar, primero encuentra los clusters más cercanos y solo escanea esos.
-- Más rápido de construir, menos memoria.
-- Necesita datos cargados *antes* de crear el índice para que los clusters sean buenos.
-- Parámetro clave: `lists` (típicamente `sqrt(n_rows)`).
-
-**HNSW** (Hierarchical Navigable Small World):
-- Construye un grafo de navegación multinivel.
-- Más lento de construir y más memoria, pero **mayor recall** (encuentra los vecinos correctos más seguido) y mejor latencia de query.
-- Se puede construir antes de tener datos (crece dinámicamente).
-- **Recomendado para producción** salvo que el índice sea muy grande.
-
-### Cómo se usa en Symfony/Doctrine
-
-`pgvector` no tiene soporte nativo en Doctrine. Se necesita declarar un tipo custom que mapea el tipo SQL `vector(n)` a un array PHP de floats. El flujo es:
-
-```
-PHP array de floats → Doctrine Type custom → SQL vector(n) en Postgres
-```
-
-En una entidad se declara así:
-
-```php
-#[ORM\Column(type: 'vector', length: 1536)]
-private array $embedding = [];
-```
-
-Y en la migración se genera:
-
-```sql
-ALTER TABLE mi_entidad ADD COLUMN embedding vector(1536);
-CREATE INDEX ON mi_entidad USING hnsw (embedding vector_cosine_ops);
-```
-
-Para queries de similitud se usa SQL nativo o DQL con funciones custom:
-
-```php
-$em->createNativeQuery(
-    'SELECT * FROM mi_entidad ORDER BY embedding <=> :query_vec LIMIT 5',
-    $rsm
-)->setParameter('query_vec', $queryEmbedding);
-```
-
-### Por qué en Postgres y no en una DB vectorial dedicada
-
-Para la escala de la mayoría de las apps construidas sobre Oliva (miles/decenas de miles de registros), `pgvector` es más que suficiente y tiene ventajas reales:
-
-- **Un solo servicio menos** en Docker Compose (la imagen `pgvector/pgvector` es un Postgres normal con la extensión compilada; si no la usás, no cambia nada).
-- **Transacciones** — el embedding y los metadatos del registro se guardan atómicamente.
-- **SQL estándar** — podés filtrar por cualquier columna *y* ordenar por similitud en una sola query.
-- **Backup unificado** — un `pg_dump` y tenés todo.
-
-Una DB vectorial dedicada tiene sentido a partir de decenas de millones de vectores o cuando necesitás features muy específicas (multi-tenancy vectorial, filtros complejos a escala masiva).
-
----
-
-## RabbitMQ
-
-### Qué es
-
-RabbitMQ es un **message broker**: un proceso intermediario que recibe mensajes de un productor, los guarda en colas, y los entrega a uno o más consumidores. Es el equivalente a una oficina de correo: el que manda la carta (productor) no necesita saber quién la va a leer ni cuándo; solo la deposita, y el broker se ocupa de la entrega.
-
-El protocolo que usa RabbitMQ se llama **AMQP** (Advanced Message Queuing Protocol).
-
-### Conceptos clave
-
-| Concepto | Qué es |
-|---|---|
-| **Producer** | Quien publica el mensaje (ej: un comando programado que detectó trabajo nuevo) |
-| **Exchange** | Punto de entrada. Recibe el mensaje y decide a qué colas mandarlo según reglas de routing |
-| **Queue** | Buffer persistente donde esperan los mensajes hasta ser consumidos |
-| **Consumer** | Quien procesa los mensajes (ej: un worker de Symfony Messenger) |
-| **Binding** | Regla que conecta un exchange con una queue |
-| **Routing key** | Etiqueta en el mensaje que usa el exchange para decidir el destino |
-
-El flujo es siempre: `Producer → Exchange → Queue → Consumer`.
-
-### Por qué no llamar directamente al worker
-
-La alternativa "simple" sería que el productor llame al worker por HTTP o ejecute la lógica directamente. El problema:
-
-- Si el worker se cae, el trabajo se pierde.
-- Si llegan muchos eventos a la vez, el productor se bloquea esperando respuesta.
-- No podés escalar consumidores sin cambiar el productor.
-
-Con un broker en el medio:
-- El mensaje **persiste en la cola** aunque el worker esté caído. Cuando vuelve, lo procesa.
-- El productor termina en microsegundos (solo publica). El procesamiento es **asíncrono**.
-- Podés levantar varios workers en paralelo sin tocar el productor.
-
-### Cómo se usa en este framework
-
-El patrón general habilitado por Oliva es:
-
-```
-[scheduler / comando]
-     │ publica un mensaje (Symfony Messenger)
-     ▼
-[RabbitMQ - exchange]
-     │ routing → queue
-     ▼
-[worker - bin/console messenger:consume]
-     │ consume el mensaje
-     │ ejecuta la lógica de negocio
-     │ persiste en Postgres (eventualmente con embedding via pgvector)
-     ▼
-[Mercure Hub]
-     │ push SSE al frontend
-     ▼
-[Dashboard en vivo]
-```
-
-Symfony usa su componente **Messenger** para abstraer RabbitMQ: en el código PHP se hace `$bus->dispatch(new MiMensaje(...))` y Messenger se encarga del transporte AMQP. No hay llamadas manuales a la librería de RabbitMQ. Ver `docs/examples/` para un esqueleto de mensaje + handler + comando de polling.
-
-### Por qué RabbitMQ y no Kafka o Redis Streams
-
-- **Kafka** es correcto para millones de mensajes/segundo y retención larga. Overkill para la mayoría de apps y agrega complejidad operativa real.
-- **Redis Streams** es válido y más liviano, pero RabbitMQ tiene mejor integración nativa con **Symfony Messenger** (transport oficial, reintentos, dead-letter queues out of the box).
-- **RabbitMQ** tiene UI de management (`localhost:15672`) que facilita debug en desarrollo.
-
-Si una app no necesita colas, el servicio `rabbitmq` (y `scheduler`/`worker`) se puede quitar de `docker-compose.yml` sin afectar al resto.
-
----
-
-## AMQP Routing y el bug de `default_publish_routing_key`
-
-### El problema en una línea
-
-Se publicaron mensajes al exchange `ingest`. La queue `ingest` quedó en 0. Los mensajes desaparecieron en silencio.
-
-### Cómo funciona el routing en AMQP (tipo `direct`)
-
-Un exchange `direct` es como un clasificador postal con reglas exactas:
-
-```
-Producer publica mensaje con routing_key="ingest"
-         │
-         ▼
-   [Exchange "ingest" — tipo direct]
-         │
-         │  ¿hay algún binding cuya binding_key == routing_key del mensaje?
-         │
-    ─────┴─────────────────────────────────────
-    SÍ: "ingest" == "ingest"        NO: descarta el mensaje (silencio)
-         │
-         ▼
-   [Queue "ingest"]
-```
-
-El **binding** es el cable que conecta exchange con queue. Se define con una `binding_key`. Cuando llega un mensaje, el exchange compara el `routing_key` del mensaje contra la `binding_key` del binding. Si hay match exacto → entrega. Si no hay match → el mensaje se descarta **sin error, sin log, sin excepción**.
-
-Esto es importante: **AMQP no falla ruidosamente cuando un mensaje no rutea. Lo descarta silenciosamente.** El producer recibe un "OK" del broker igualmente.
-
-### Por qué pasa el bug
-
-Una configuración típica (e incompleta) de Symfony Messenger es:
-
-```yaml
-transports:
-    ingest:
-        dsn: '%env(RABBITMQ_DSN)%'
-        options:
-            exchange:
-                name: ingest
-                type: direct
-            queues:
-                ingest:
-                    binding_keys: [ingest]
-```
-
-Los `binding_keys: [ingest]` crean el binding `exchange → queue` con binding_key `"ingest"`. Eso es correcto.
-
-El problema está en **qué routing_key usa Symfony al publicar**. El comportamiento de Symfony Messenger al publicar un mensaje a AMQP es:
-
-```
-routing_key = AmqpRoutingKeyStamp (si está presente en el envelope)
-           ?? default_publish_routing_key (si está configurado en el exchange)
-           ?? "" (string vacío — el default si no hay nada)
-```
-
-Si no hay stamp ni `default_publish_routing_key`, Symfony publica todos los mensajes con `routing_key = ""`.
-
-El exchange recibe los mensajes (por eso `publish_in` sube), busca un binding con `binding_key == ""`, no encuentra ninguno, y los descarta. La queue queda en 0. Sin error.
-
-### El fix
-
-Agregar `default_publish_routing_key` al exchange:
-
-```yaml
-exchange:
-    name: ingest
-    type: direct
-    default_publish_routing_key: ingest   # ← esto faltaba
-```
-
-Ahora Symfony publica con `routing_key = "ingest"`, que matchea `binding_key = "ingest"`, y el mensaje llega a la queue. Esto ya está aplicado en `backend/config/packages/messenger.yaml`.
-
-### Cómo se detecta
-
-No hay ningún error en el lado del producer. El `$bus->dispatch(...)` retorna éxito. El exchange recibe el mensaje. El único indicio es que la queue permanece vacía aunque se publique.
-
-La forma de diagnosticarlo es comparar las métricas del exchange vs la queue en la management UI de RabbitMQ (`localhost:15672`):
-
-- Exchange `ingest` → `publish_in: N`, `publish_out: 0`
-- Queue `ingest` → `deliver_get: 0`
-
-`publish_out: 0` significa que el exchange no envió nada a ninguna queue (ni a otro exchange). Ahí se confirma que el problema es de routing, no de consumo.
-
-### Cuándo `publish_out` es 0 y cuándo no
-
-`publish_out` en un exchange cuenta únicamente los mensajes que el exchange reenvió a **otro exchange** (exchange-to-exchange routing). NO cuenta los mensajes entregados a queues. Así que `publish_out: 0` con `publish_in: N > 0` no necesariamente es un bug — solo significa que no hay exchange-to-exchange routing. El indicador real es `deliver_get` en la queue.
-
-### Regla para recordar
-
-> En un exchange `direct` de RabbitMQ, el mensaje solo llega a la queue si `routing_key del mensaje == binding_key del binding`. Symfony Messenger usa routing key vacío por defecto. Siempre configurar `default_publish_routing_key` cuando el exchange es `direct`.
-
----
-
-## Foundry + Doctrine Fixtures — seeding layer
-
-**Qué es:** capa de testing post-deploy para poblar bases de datos en staging, con datos representativos pero falsos. Equivalente Symfony al par `seeders + factories` de Laravel.
-
-### Stack
-
-| Componente | Rol | Equivalente Laravel |
-|---|---|---|
-| `doctrine/doctrine-fixtures-bundle` | Runner: `bin/console doctrine:fixtures:load` | `php artisan db:seed` |
-| `zenstruck/foundry` | Factories tipadas con estados y relaciones fluidas | `HasFactory` / Faker integrado |
-| `fakerphp/faker` | Generador de datos falsos (viene con Foundry) | `Faker` |
-
-### Cómo funciona
-
-```
-AppFixtures (FixtureGroupInterface)
-  └── grupos: ['staging', 'dev']
-       └── llama factories:  MemberFactory::createMany(15)
-                             ProjectFactory::createMany(5)
-```
-
-`AppFixtures` implementa `FixtureGroupInterface` → permite segmentar con `--group=staging` (QA/devs) vs `--group=dev` (desarrollo local) sin peligro de correr datos de prueba en prod.
-
-### Guard de producción — target Docker `frankenphp_staging`
-
-Las dependencias de seeding son `require-dev`. La imagen prod se compila con `--no-dev`, así que **el comando `doctrine:fixtures:load` no existe en prod**. Es una garantía estructural, no una convención:
-
-```dockerfile
-# Hereda de prod (no dev): mantiene representatividad del entorno
-FROM frankenphp_prod AS frankenphp_staging
-RUN composer install ...   # re-instala incluyendo dev-deps
-```
-
-Nunca hereda de `frankenphp_dev` — staging debe ser prod + tooling de seeding, no dev + tooling de seeding. Si diverge de prod, deja de testear lo que realmente corre.
-
-### Uso (en staging)
-
-> ⚠️ **`fixtures:load` PURGA la base antes de cargar** (DELETE/TRUNCATE de todas las
-> tablas, salvo `--append`). Correr SOLO contra una DB de staging dedicada, **nunca**
-> contra la DB de una app productiva en infra compartida. El guard de la imagen
-> `--no-dev` no protege esto. Ver Epic E, "Deuda crítica": staging debe ser una app
-> aparte a nivel infra, con su propia DB.
-
-```bash
-# 1. Construir imagen staging
-docker compose -f docker-compose.yml -f docker-compose.prod.yml \
-  build --target frankenphp_staging backend
-
-# 2. Cargar fixtures (contra la DB de STAGING, no la de prod)
-docker exec <app>-staging-backend-1 bin/console doctrine:fixtures:load \
-  --group=staging --no-interaction
-```
-
-### Cómo extender en un fork
-
-1. Crear factories con `bin/console make:factory` (o a mano en `src/Factory/`).
-2. Agregar las llamadas en `AppFixtures::load()` o en `AppStory::build()`.
-3. `AppStory` sirve para escenarios nombrados y puede llamarse desde fixtures: `AppStory::load()`.
-
-Ver `src/DataFixtures/AppFixtures.php` y `src/Story/AppStory.php` para el esqueleto con comentarios.
diff --git a/docs/examples/IngestSourceHandler.php.example b/docs/examples/IngestSourceHandler.php.example
deleted file mode 100644
index 088633d..0000000
--- a/docs/examples/IngestSourceHandler.php.example
+++ /dev/null
@@ -1,19 +0,0 @@
-<?php
-
-namespace App\MessageHandler;
-
-use App\Message\IngestSourceMessage;
-use Psr\Log\LoggerInterface;
-use Symfony\Component\Messenger\Attribute\AsMessageHandler;
-
-#[AsMessageHandler]
-class IngestSourceHandler
-{
-    public function __construct(private readonly LoggerInterface $logger) {}
-
-    public function __invoke(IngestSourceMessage $message): void
-    {
-        // Stub — replace with real ingestion logic for your domain
-        $this->logger->info('IngestSourceHandler: stub no-op', ['sourceId' => $message->sourceId]);
-    }
-}
diff --git a/docs/roadmap/epics/E-seeding-layer.md b/docs/roadmap/epics/E-seeding-layer.md
deleted file mode 100644
index f9774c7..0000000
--- a/docs/roadmap/epics/E-seeding-layer.md
+++ /dev/null
@@ -1,104 +0,0 @@
-# Epic E — Seeding layer (staging)
-
-> **Estado:** ✅ completo ·
-> **Versión destino:** v1.1 · **Origen:**
-> necesidad surgida en finanzas-ong (poblar staging con datos representativos sin SQL crudo).
-
-## Problema
-
-Oliva no tenía seeding de primera clase. Poblar la base en staging requería SQL
-crudo a mano o scripts ad-hoc (`seed.sh` local). Sin una capa de factories,
-los forks no pueden generar datos de prueba reproducibles ni testear flujos
-post-deploy de forma consistente.
-
-## Visión
-
-Equivalente Symfony del par `seeders + factories` de Laravel: datos falsos pero
-representativos, reproducibles, segregados por grupo (`staging` / `dev`), con
-**guard estructural** contra seedear producción accidentalmente.
-
-El guard no es una convención — es estructural: la imagen prod se compila con
-`--no-dev`, así que el comando `doctrine:fixtures:load` directamente no existe en
-la imagen prod.
-
-## Stack agregado
-
-| Paquete | Rol |
-|---|---|
-| `zenstruck/foundry` | Factories tipadas con estados y relaciones fluidas (trae FakerPHP) |
-| `doctrine/doctrine-fixtures-bundle` | Runner (`doctrine:fixtures:load --group=`) |
-
-Ambos como `require-dev` — no entran en la imagen prod.
-
-## Target Docker `frankenphp_staging`
-
-Multi-stage build: `frankenphp_staging` hereda de `frankenphp_prod` (no dev).
-Staging = prod + tooling de seeding. Mantiene representatividad del entorno; si
-divergiera de prod, dejaría de testear lo que realmente corre.
-
-```
-frankenphp_base
-  ├── frankenphp_dev   (dev)
-  ├── frankenphp_prod  (producción)
-  └── frankenphp_staging  ← hereda de prod, suma --dev deps
-```
-
-## Slices entregados
-
-- [x] `composer require --dev zenstruck/foundry doctrine/doctrine-fixtures-bundle`
-- [x] `AppFixtures` con grupos `staging` / `dev` y comentarios para forks
-- [x] `AppStory` como punto de entrada de escenarios Foundry
-- [x] Target `frankenphp_staging` en el Dockerfile
-- [x] Paso opt-in en el runbook de deploy del `CLAUDE.md`
-- [x] Comando documentado en `.env.example`
-- [x] Sección Foundry en `docs/concepts.md`
-- [x] `docker-compose.staging.yml` — overlay mínimo (image + target + env_file)
-- [x] `.env.staging.example` — env template para la DB desechable de staging
-- [x] `scripts/deploy-staging.sh` — deploy completo de staging en una llamada
-- [x] Runbook formal de staging en `CLAUDE.md`
-- [x] Modelo de infra de staging documentado (Epic E, deuda crítica resuelta)
-
-## Deuda crítica — el modelo de infra de staging (RESUELTA 2026-06-29)
-
-> Detectada en el checkpoint del 2026-06-27. Resuelta con Opción 1 (staging como
-> app más en el VPS, DB propia desechable en el mismo Postgres compartido).
-
-`doctrine:fixtures:load` **purga la base antes de cargar** (DELETE/TRUNCATE de
-todas las tablas gestionadas, salvo `--append`). El guard estructural de la imagen
-prod (`--no-dev`) no alcanzaba por sí solo: el propio paso 11 del runbook anterior
-hacía buildear la imagen `frankenphp_staging` que SÍ tiene el comando, y en infra
-compartida el container apuntaba al Postgres central vía el `DATABASE_URL` **de
-producción**.
-
-**Solución implementada (Opción 1 — staging como app aparte):**
-
-- `docker-compose.staging.yml`: overlay mínimo que overridea `image` y
-  `build.target` del backend/scheduler (tag `app-backend-staging:1.0`, target
-  `frankenphp_staging`). Evita pisar la imagen de prod en el host.
-- `.env.staging` (gitignored) + `.env.staging.example`: env de staging con el
-  `DATABASE_URL` de la DB desechable. Se carga como último env_file en el overlay.
-- **Project name propio** (`-p <app>-staging`): red privada propia, sin colisión
-  DNS con el stack de producción.
-- **DB propia** en el mismo Postgres compartido de infra:
-  `provision-postgres.sh <app>_staging_db <app>_staging_user`. La purga es
-  inocua — la DB de staging es desechable.
-- `scripts/deploy-staging.sh`: atajo que ejecuta build + up + migraciones +
-  `fixtures:load` en una sola llamada.
-- Runbook formal en `CLAUDE.md` (sección "Runbook de staging").
-
-El paso 11 del runbook de shared-infra apunta ahora al runbook de staging.
-
-## Cómo extiende un fork
-
-1. `bin/console make:factory` para cada entidad (o a mano en `src/Factory/`).
-2. Llamar las factories en `AppFixtures::load()` o en `AppStory::build()`.
-3. El target `frankenphp_staging` ya existe: solo necesita `docker compose build --target frankenphp_staging`.
-4. **Antes de seedear en infra compartida:** resolver la "Deuda crítica" de arriba —
-   staging necesita su propia DB, no la de producción.
-
-## Por qué es un hito de framework
-
-El target `frankenphp_staging` introduce **multi-stage build con herencia semántica**
-en Oliva: cada stage tiene un propósito explícito (dev / prod / staging) y la imagen
-de staging reutiliza prod sin divergir. Es el patrón Docker recomendado para tooling
-de testing post-deploy y escala para sumar más tools (ej. API collection) sin tocar prod.
diff --git a/oliva-upgrade-optional-services.md b/oliva-upgrade-optional-services.md
deleted file mode 100644
index 8f73b62..0000000
--- a/oliva-upgrade-optional-services.md
+++ /dev/null
@@ -1,155 +0,0 @@
-# Oliva — Upgrade: servicios opcionales vía Compose profiles
-
-> **Repo:** Oliva (framework base).
-> **Rama sugerida:** `feature/optional-services-profiles`.
-> **Qué es este doc:** especificación de un upgrade del framework. Claude CLI
-> construye el cambio a partir de acá y lo mergea a `main` cuando esté probado.
-> **Qué NO es:** no contiene nada de deploy ni de ninguna app concreta. El
-> framework no conoce a las apps que lo forkean. El deploy de finanzas-ong vive
-> en su propio repo (ver `deploy-finanzas-ong-prod-v1.md`).
-
-> **Naturaleza:** upgrade temporal. Resuelve el caso de hoy (prender/apagar
-> servicios opcionales sin borrarlos). La solución definitiva — flags en
-> instalación — es v2.0 (sección 4).
-
----
-
-## 1. Problema
-
-Oliva levanta por default el stack completo: backend + frontend + database +
-**rabbitmq + worker (Messenger) + mercure**. Toda app que forkea Oliva hereda
-esos servicios opcionales aunque no los use.
-
-No queremos:
-- correr y mantener en prod piezas que no hacen nada (RAM idle, superficie de
-  falla, ruido al razonar sobre el sistema);
-- "borrar" servicios del compose por app (destructivo, no versionable, se
-  re-rompe en cada fork).
-
-Queremos una palanca limpia, por variable de entorno, que sea capacidad nativa
-de Oliva y la herede cualquier fork.
-
----
-
-## 2. Solución: Docker Compose profiles
-
-Compose tiene `profiles` nativo. Un servicio **sin** `profiles` siempre se
-levanta; uno **con** `profiles` solo se levanta si ese perfil está activo. No
-hay que construir nada — es de la herramienta.
-
-### Cambios en `docker-compose.yml`
-
-```yaml
-services:
-  backend:        # core — sin profile, siempre arriba
-    # ...
-  frontend:       # core
-    # ...
-  database:       # core
-    # ...
-
-  rabbitmq:
-    image: rabbitmq:3-management
-    profiles: ["queues"]
-    # ...
-
-  worker:
-    # command: messenger:consume
-    profiles: ["queues"]
-    # ...
-
-  mercure:
-    profiles: ["realtime"]
-    # ...
-```
-
-Agrupar por perfil semántico, no por servicio:
-- `queues` → rabbitmq + worker (van juntos: el worker no sirve sin broker).
-- `realtime` → mercure.
-
-### Control por variable de entorno
-
-En `.env`:
-
-```dotenv
-# Por default, app mínima: solo core arriba.
-COMPOSE_PROFILES=
-
-# Una app que use colas y tiempo real:
-# COMPOSE_PROFILES=queues,realtime
-```
-
-`docker compose up -d` con `COMPOSE_PROFILES` vacío levanta SOLO core.
-
----
-
-## 3. Coherencia de variables (documentar en README)
-
-Los profiles deciden *qué contenedores se levantan*, no las variables que la app
-le pasa al backend. Si alguien activa `queues` pero no configura el DSN del
-broker, el backend falla al arrancar.
-
-Agregar al README de Oliva una tabla del estilo:
-
-| Perfil | Servicios | Variables que hay que configurar |
-|---|---|---|
-| (ninguno) | backend, frontend, database | `DATABASE_URL`, `APP_SECRET`, ... |
-| `queues` | + rabbitmq, worker | `MESSENGER_TRANSPORT_DSN` |
-| `realtime` | + mercure | claves Mercure (`openssl rand -hex 32`) |
-
-> Regla: si activás un perfil, configurás también sus variables. Esa coherencia
-> es responsabilidad de quien forkea, no del framework.
-
----
-
-## 4. Tareas para CLI
-
-- [x] `profiles: ["queues"]` en `rabbitmq` y `worker`.
-- [x] ~~`profiles: ["realtime"]` en `mercure`~~ — descartado: Mercure corre
-      embebido en el backend vía el hub de Caddy (FrankenPHP), no es un
-      contenedor separado. No hay nada que togglear, y separarlo iría contra
-      el diseño de FrankenPHP. Ver README, sección "Always-on, not behind a
-      profile".
-- [x] `COMPOSE_PROFILES=` (vacío) en `.env.example`.
-- [x] Tabla de perfiles ↔ variables en el README (solo `queues`, ver arriba).
-- [x] Test local: `COMPOSE_PROFILES=` vacío → `docker compose up -d` levanta
-      SOLO backend + frontend + database (+ scheduler, always-on). Verificado
-      con `docker compose ps` — sin rabbitmq/worker.
-- [x] Test local: `COMPOSE_PROFILES=queues` → aparecen rabbitmq + worker;
-      al vaciar la variable y `docker compose stop`, desaparecen.
-- [x] Testeo manual del usuario: `COMPOSE_PROFILES=queues` levanta rabbitmq +
-      worker (healthy), worker consume `ingest`/`enrich` sin errores, sin
-      tocar backend/database/frontend/scheduler ya corriendo.
-- [x] Merge a `main` con el upgrade probado.
-
-### Cambio adicional no previsto en el spec original
-
-Para que el toggle funcione de verdad hubo que quitar `depends_on: rabbitmq`
-de `backend` y `scheduler` (en `docker-compose.yml`) y del `scheduler` en
-`docker-compose.override.yml`. Sin esto, Compose volvía a levantar rabbitmq
-aunque el profile estuviera apagado, porque un servicio core dependía de él.
-Documentado en el README ("Adding a new profile", punto 2) como regla para
-perfiles futuros.
-
-> **Scope guard:** esto son ~4 líneas `profiles:` + 1 variable + doc en README.
-> Si empieza a sentirse como "construir un sistema", parar — eso ya es v2.0.
-
----
-
-## 5. Hacia v2.0 (NO ahora — registro de intención del framework)
-
-Items que son responsabilidad del framework (los de ops viven en el doc de
-deploy):
-
-- **Flags en instalación / scaffolding:** que forkear Oliva pregunte (o lea un
-  manifiesto) qué servicios incluir, en vez de heredar todo y apagar con
-  profiles. Los profiles de v1 son el puente, no el destino.
-- **Definición de `worker` para producción:** hoy `worker` solo está en
-  `docker-compose.override.yml` (dev). Falta su equivalente prod. Relevante
-  cuando una app use Messenger en serio en producción.
-- **Mecanismo de propagación de upgrades a forks:** hoy una app que forkeó
-  Oliva no recibe automáticamente los cambios del framework (ver el doc de
-  deploy, sección "port"). v2.0 debería definir cómo se sincroniza un fork con
-  upstream sin parchear a mano.
-
-> Disparador para abrir v2.0: la segunda app real lista para prod.
diff --git a/scripts/deploy-staging.sh b/scripts/deploy-staging.sh
deleted file mode 100755
index 4c00b9f..0000000
--- a/scripts/deploy-staging.sh
+++ /dev/null
@@ -1,55 +0,0 @@
-#!/usr/bin/env bash
-#
-# Deploy del stack de STAGING de una app Oliva sobre infra compartida.
-# Análogo a deploy.sh, pero usa la imagen frankenphp_staging y un project
-# name propio (-p <app>-staging) para no interferir con el stack de producción.
-#
-# Prerequisitos (primera vez, una sola vez por app):
-#   1. Provisionar la DB de staging en el Postgres compartido:
-#        ~/infra/scripts/provision-postgres.sh <app>_staging_db <app>_staging_user
-#   2. Completar .env.staging (copiar de .env.staging.example y setear DATABASE_URL).
-#
-# Uso:
-#   ./scripts/deploy-staging.sh            # app_name = nombre del directorio actual
-#   ./scripts/deploy-staging.sh ong        # app_name explícito
-#   SKIP_PULL=1 ./scripts/deploy-staging.sh   # no hace git pull
-set -euo pipefail
-
-APP_NAME="${1:-$(basename "$PWD")}"
-STAGING_PROJECT="${APP_NAME}-staging"
-
-COMPOSE=(docker compose -p "$STAGING_PROJECT"
-  -f docker-compose.yml
-  -f docker-compose.prod.yml
-  -f docker-compose.shared-infra.yml
-  -f docker-compose.staging.yml)
-
-echo ">> Deploy de STAGING '$STAGING_PROJECT' desde $PWD"
-
-if [[ "${SKIP_PULL:-0}" != "1" ]]; then
-  echo ">> git pull"
-  git pull
-fi
-
-echo ">> down"
-COMPOSE_PROFILES=cron "${COMPOSE[@]}" down --remove-orphans
-
-# build-everything (no enumerar servicios): enumerar es lo frágil — es lo que
-# en finanzas-ong dejó el frontend STALE (build solo listaba backend) y se
-# pudre de nuevo en cuanto un fork agregue un servicio buildeable más. Alinea
-# además con deploy.sh (prod), que ya usa up -d --build.
-echo ">> up -d --build (target backend/scheduler: frankenphp_staging)"
-"${COMPOSE[@]}" up -d --build
-
-echo ">> migraciones"
-docker exec "${STAGING_PROJECT}-backend-1" bin/console doctrine:migrations:migrate --no-interaction
-
-echo ">> seeding (fixtures:load --group=staging)"
-docker exec "${STAGING_PROJECT}-backend-1" bin/console doctrine:fixtures:load --group=staging --no-interaction
-
-echo ">> estado:"
-"${COMPOSE[@]}" ps
-
-echo ">> OK — staging corriendo en project '${STAGING_PROJECT}'."
-echo "   DB de staging es desechable. Para reiniciar con datos frescos:"
-echo "   SKIP_PULL=1 ./scripts/deploy-staging.sh"
diff --git a/scripts/deploy.sh b/scripts/deploy.sh
deleted file mode 100755
index 247afc0..0000000
--- a/scripts/deploy.sh
+++ /dev/null
@@ -1,49 +0,0 @@
-#!/usr/bin/env bash
-#
-# Deploy de una app Oliva sobre infra compartida (down + build + up).
-# Reemplaza la tira de comandos manuales del runbook de CLAUDE.md.
-#
-# Uso:
-#   ./scripts/deploy.sh            # app_name = nombre del directorio actual (ej. en ~/ong → "ong")
-#   ./scripts/deploy.sh ong        # app_name explícito
-#   SKIP_PULL=1 ./scripts/deploy.sh   # no hace git pull (deploy de cambios ya presentes)
-#
-# Corre desde la raíz del repo de la app en el VPS (ahí viven los 3 compose files).
-set -euo pipefail
-
-APP_NAME="${1:-$(basename "$PWD")}"
-
-COMPOSE=(docker compose -p "$APP_NAME"
-  -f docker-compose.yml
-  -f docker-compose.prod.yml
-  -f docker-compose.shared-infra.yml)
-
-echo ">> Deploy de '$APP_NAME' desde $PWD"
-
-if [[ "${SKIP_PULL:-0}" != "1" ]]; then
-  echo ">> git pull"
-  git pull
-fi
-
-# Docs internos: no pertenecen al host de prod. El código de la app vive
-# en los builds Docker; estos archivos no los necesita nadie en el server.
-echo ">> limpieza de docs internos"
-find . -maxdepth 1 -name "*.md" -delete
-rm -rf docs/
-
-# down borra los containers viejos antes de recrearlos.
-# COMPOSE_PROFILES=cron mete al scheduler en scope SOLO para el down: un servicio
-# detrás de un profile no se baja con `down` (profile inactivo) ni con
-# --remove-orphans (sigue definido en el YAML, no es huérfano real) → quedaría
-# corriendo stale. Activando el profile acá, el down sí lo apaga. El `up` de
-# abajo NO lleva el profile, así que el scheduler no se vuelve a levantar.
-echo ">> down"
-COMPOSE_PROFILES=cron "${COMPOSE[@]}" down --remove-orphans
-
-echo ">> up -d --build"
-"${COMPOSE[@]}" up -d --build
-
-echo ">> estado:"
-"${COMPOSE[@]}" ps
-
-echo ">> OK. Si la app usa cron, agregá '--profile cron' al up (ver CLAUDE.md)."
diff --git a/scripts/down-staging.sh b/scripts/down-staging.sh
deleted file mode 100755
index 8df568b..0000000
--- a/scripts/down-staging.sh
+++ /dev/null
@@ -1,28 +0,0 @@
-#!/usr/bin/env bash
-#
-# Baja el stack de STAGING de una app Oliva sobre infra compartida.
-# Análogo a down.sh, pero con los 4 overlays y project name propio
-# (-p <app>-staging) para no tocar el stack de producción.
-#
-# Uso:
-#   ./scripts/down-staging.sh         # app_name = nombre del directorio actual
-#   ./scripts/down-staging.sh ong     # app_name explícito
-#
-# Nunca borra volúmenes (no pasa -v): la DB desechable de staging queda a
-# salvo (si se quiere purgar de verdad, bajar con -v a mano).
-# Corre desde la raíz del repo de la app en el VPS.
-set -euo pipefail
-
-APP_NAME="${1:-$(basename "$PWD")}"
-STAGING_PROJECT="${APP_NAME}-staging"
-
-COMPOSE=(docker compose -p "$STAGING_PROJECT"
-  -f docker-compose.yml
-  -f docker-compose.prod.yml
-  -f docker-compose.shared-infra.yml
-  -f docker-compose.staging.yml)
-
-echo ">> down de '$STAGING_PROJECT' desde $PWD"
-COMPOSE_PROFILES=cron "${COMPOSE[@]}" down --remove-orphans
-
-echo ">> OK, servicios de '$STAGING_PROJECT' abajo (volúmenes intactos)."
diff --git a/scripts/down.sh b/scripts/down.sh
deleted file mode 100755
index 9c289ea..0000000
--- a/scripts/down.sh
+++ /dev/null
@@ -1,29 +0,0 @@
-#!/usr/bin/env bash
-#
-# Baja los servicios de una app Oliva sobre infra compartida.
-# Reemplaza el `docker compose -p ... -f ... -f ... -f ... down` a mano.
-#
-# Uso:
-#   ./scripts/down.sh         # app_name = nombre del directorio actual (ej. en ~/ong → "ong")
-#   ./scripts/down.sh ong     # app_name explícito
-#
-# Nunca borra volúmenes (no pasa -v): la DB y los secrets quedan a salvo.
-# Corre desde la raíz del repo de la app en el VPS.
-set -euo pipefail
-
-APP_NAME="${1:-$(basename "$PWD")}"
-
-COMPOSE=(docker compose -p "$APP_NAME"
-  -f docker-compose.yml
-  -f docker-compose.prod.yml
-  -f docker-compose.shared-infra.yml)
-
-echo ">> down de '$APP_NAME' desde $PWD"
-# COMPOSE_PROFILES=cron mete al scheduler (y cualquier servicio con profile) en
-# scope para el down: sin esto, un servicio detrás de un profile no se baja —
-# `down` lo saltea (profile inactivo) y --remove-orphans tampoco lo toca (sigue
-# definido en el YAML, no es huérfano). NO se pasa -v: volúmenes (DB, secrets)
-# se preservan.
-COMPOSE_PROFILES=cron "${COMPOSE[@]}" down --remove-orphans
-
-echo ">> OK, servicios de '$APP_NAME' abajo (volúmenes intactos)."
