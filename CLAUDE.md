# Crypto Market Pulse (sobre Oliva)

Rama `release/plan-market-pulse`: proyecto-vidriera **"Crypto Pulse"** — plataforma de inteligencia de mercado cripto en tiempo real (ingesta de fuentes públicas → enriquecimiento con IA → dashboard en vivo vía Mercure). El headline es **DevOps × IA**; cripto es el dominio de datos, no el producto.

Construido sobre **Oliva** (framework base propio, rama `main` de este mismo repo): backend Symfony (FrankenPHP), frontend Vite, PostgreSQL con pgvector, tiempo real vía Mercure, colas vía RabbitMQ + Symfony Messenger, y contenedor scheduler (supercronic) para tareas programadas. Todo orquestado con Docker Compose.

## Sync con Oliva (`main`)

Esta rama se sincroniza con **merges one-way `main` → rama** (nunca al revés: el dominio cripto no vuelve al framework; **no tocar `main`**). Último sync: **2026-07-02** — merge de los 40 commits de main (profiles, shared-infra, staging, APP_ENV corto, CI nuevo, seeding layer); análisis y política de resolución en `SYNC-NOTES.md`. No dejar divergir: tras ~mes y medio de divergencia el merge costó 19 conflictos `add/add`.

## Comandos principales

### Desarrollo
```bash
docker compose up
```
El `docker-compose.override.yml` se aplica automáticamente: monta el código fuente con hot-reload, expone el backend en `:80` y el frontend en `:3000`.

**CMP necesita el pipeline completo:** `rabbitmq`/`worker` viven tras el profile `queues` y `scheduler` tras `cron` (modelo de servicios opcionales de Oliva). El `.env` de CMP debe tener `COMPOSE_PROFILES=queues,cron` — sin eso, `docker compose up` levanta solo core (backend + frontend + database) y el pipeline queda a medias. Mercure no tiene profile: va siempre embebido en el backend (hub de Caddy).

### Producción
```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```
Usa imágenes compiladas (`app-backend-prod:1.0`, `app-frontend-prod:1.0`). El frontend queda expuesto en `:80`.

### Build de producción
```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml build
```

### Deploy real (VPS): infra compartida
El target de deploy de CMP es la **infra compartida** (`~/infra`: Postgres + RabbitMQ + reverse-proxy compartidos entre apps; finanzas-ong ya corre ahí). Standalone queda para dev/pruebas locales. Ver "Infra compartida" abajo. CMP es el **primer fork que enciende el RabbitMQ compartido** → smoke-test obligatorio en el primer deploy (colas aisladas en su vhost `crypto`).

## Estructura
- `backend/` — Symfony con FrankenPHP (Doctrine ORM/Migrations, pgvector, Mercure, Messenger)
- `frontend/` — Vite (Node)
- `docs/concepts.md` — glosario técnico acumulativo (explicaciones agregadas a pedido)
- `docs/examples/` — esqueletos de referencia no registrados como código de la app
- `.env`, `.env.backend`, `.env.frontend` — variables por entorno
- `.env.prod` — variables de producción
- `PLAN-MARKET-PULSE.md` — plan completo y runbook ejecutable (leer §11 "convenciones de ejecución" antes de implementar)
- `SYNC-NOTES.md` — análisis del sync main→CMP de 2026-07-02
- `agent-commits.md` — log de commits del agente

## Estado del proyecto

- **Hecho:** Fase 0 completa (0.1–0.8) + 1.1–1.6 (modelo de dominio + HNSW, ingesta RSS, poll programado, enriquecimiento IA, Mercure publish + null provider dev). Sync con main ejecutado 2026-07-02.
- **Próximo paso:** 1.7 — Dashboard en vivo (carga inicial vía REST + suscripción Mercure a `crypto/feed`, patrón `live.js`).
- **Decisiones cerradas:** broker **RabbitMQ**, scheduler **contenedor cron (supercronic)**, LLM **Anthropic** (Haiku volumen / Sonnet agregados), vector **pgvector**, dominio **cripto** (RSS CoinDesk/Cointelegraph + CoinGecko; CryptoPanic en Fase 2).
- **Pendiente de estudio (NO avanzar sin Marcos):** pgvector / índice HNSW — bloqueante para Fase 2 (2.2 búsqueda semántica). La migración 1.1 crea un índice HNSW parcial, pero el diseño (parámetros `m`/`ef_construction`, operador de distancia, re-embedding) queda sin definir hasta que Marcos lo estudie.

## Deuda técnica conocida (revisión 2026-06-01, actualizada en el sync 2026-07-02)

- ✅ **Mock de `EnrichmentProvider` en dev — RESUELTO en 1.5.** `NullEnrichmentProvider` + `services_dev.yaml` (renombrado de `services_development.yaml` en el sync: Symfony carga `services_{APP_ENV}.yaml` y APP_ENV ahora es `dev`).
- ✅ **`MERCURE_URL` worker — RESUELTO en 1.5.** Cambiado a `http://backend/...` (nombre de servicio Docker).
- 🟡 **El prompt caching de Anthropic es un no-op.** El system prompt (~250 tokens) está por debajo del mínimo cacheable de Haiku (2048 tokens) → `cache_control: ephemeral` se ignora; no hay ahorro. El header beta `prompt-caching-2024-07-31` ya es innecesario (GA). El ahorro real lo da la capa Symfony Cache por `contentHash`.
- 🟢 **Dual-write DB↔broker → items huérfanos en `pending`.** Si el broker falla tras el `flush()` de ingesta, queda un `NewsItem(pending)` sin mensaje de enrich. Mitigado por `app:enrich:requeue-pending`. Para 1.8: correrlo periódico o documentarlo como recovery path.
- 🟢 **`contentHash` es un hash de la URL**, no del contenido. Dedup por URL es razonable; ediciones de título/cuerpo no re-ingestan.
- 🟢 **`RssAdapter` asume RSS 2.0** (`channel->item`): feed Atom → vacío silencioso; sin header `User-Agent`. Para 1.8.
- 🟢 **Gap de re-embedding:** items enriquecidos sin key de Voyage quedan con `embedding=null` permanente. La búsqueda semántica (2.2) los ignora. Necesitará comando de re-embed antes de Fase 2.
- 🟢 **`worker` sin definición de producción** (deuda heredada de Oliva): existe solo en `docker-compose.override.yml` (dev). Antes del deploy real de CMP hay que agregar un `worker` prod (imagen `app-backend-prod:1.0`, comando `messenger:consume`, sin puertos). `scheduler` sí está cubierto en prod.

## Infra compartida (deploy target): `docker-compose.shared-infra.yml`

Overlay **opt-in** para cuando varias apps Oliva comparten un VPS con Postgres/RabbitMQ/reverse-proxy en un repo de infra separado (`~/infra`). Se apila encima de `docker-compose.prod.yml`, no lo reemplaza:

```bash
# Standalone (DB propia, de siempre):
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d

# Con infra compartida (project name ÚNICO con -p, sin DB/Rabbit locales):
docker compose -p crypto \
  -f docker-compose.yml -f docker-compose.prod.yml \
  -f docker-compose.shared-infra.yml up -d
```

Qué hace (requiere Docker Compose ≥ 2.24, por la tag de merge `!override`):
- Anula `depends_on: database` de `backend`/`scheduler` con `!override {}`.
- Anula los `ports` de `frontend` (el único que publica puertos es el reverse-proxy de infra).
- Desactiva `database`/`rabbitmq` locales con un profile inerte (`disabled-in-shared-infra`).
- **Topología de red (split):** `frontend` → red privada de la app + `proxy_net` (alias único derivado de `-p`); `backend`/`scheduler` → red privada + `data_net`. El frontend no toca `data_net`. Las redes son externas (las crea el repo de infra).

> **Gotcha — colisión de alias en `proxy_net`:** el alias del frontend se deriva de `${COMPOSE_PROJECT_NAME:-app}` (con `-p crypto` da `crypto-frontend`) — dos apps con el mismo alias fijo harían round-robin de DNS y el proxy rutearía tráfico cruzado.

**Identidad de CMP en infra:** db/user de Postgres propios (`crypto_db`/`crypto_user`) + vhost de RabbitMQ propio (`crypto`) + project name `-p crypto`. Los templates de `DATABASE_URL`/`RABBITMQ_DSN` shared-infra están comentados en `.env.backend`, listos para descomentar en el VPS.

### Runbook de deploy con infra compartida (resumen; canónico en el CLAUDE.md de `main`)

> **Atajo para redeploys:** `./scripts/deploy.sh` (pull + build + down + up). El setup inicial (pasos 2-4) se hace una sola vez.

1. En el VPS: `cd ~/<app> && git pull`.
2. Crear el `.env` (gitignored): `cp .env.example .env` — para CMP dejar `COMPOSE_PROFILES=queues,cron`.
3. Provisionar en `~/infra`: `./scripts/provision-postgres.sh crypto_db crypto_user` y `./scripts/provision-rabbitmq.sh crypto crypto_user` (el Rabbit compartido corre bajo profile `queues` en infra: primera vez, prenderlo con `COMPOSE_PROFILES=queues` + `RABBITMQ_ADMIN_PASSWORD` en el `.env` de infra).
4. Descomentar/setear `DATABASE_URL` y `RABBITMQ_DSN` en `.env.backend` con las URLs provisionadas.
5. Build + up con `-p crypto` y los 3 overlays (+ `--profile cron` para el scheduler).
6. Migraciones: automáticas en el entrypoint; verificar con `doctrine:migrations:status`.
7. Claves JWT: se generan en `./secrets/jwt` (bind-mount, gitignored) en el primer boot — **backupear** los `.pem` + `JWT_PASSPHRASE`.
8. Health: `docker exec crypto-backend-1 curl -s http://localhost/health` → `{"status":"ok"}`.
9. Smoke del broker compartido: colas de CMP visibles solo en el vhost `crypto` (primer uso real del Rabbit compartido).

> **Gotcha pgvector / shared-infra:** en shared-infra la app conecta como `crypto_user` (no-superuser) → la migración `CREATE EXTENSION vector` fallaría; `provision-postgres.sh` ya crea la extensión como superuser y la migración hace no-op por el `IF NOT EXISTS`.

### Staging

Staging es **una app más** en el VPS: misma infra compartida, DB propia desechable, project name `-p <app>-staging`, imagen `frankenphp_staging` (incluye Foundry + `doctrine:fixtures:load`). Atajo: `./scripts/deploy-staging.sh`; bajar con `./scripts/down-staging.sh`. Runbook completo y gotchas de precedencia de `APP_ENV` en el CLAUDE.md de `main` (sección "Runbook de staging").

## Variables de entorno

Ver `.env.example` como referencia. Claves específicas de CMP: `ANTHROPIC_API_KEY` (enrichment; en dev no hace falta — `services_dev.yaml` alias a `NullEnrichmentProvider`), `VOYAGE_API_KEY` (embeddings; vacía = `embedding=null` hasta tener key), `COMPOSE_PROFILES=queues,cron`, `MERCURE_URL=http://backend/.well-known/mercure` (interna, para backend/worker) vs `MERCURE_PUBLIC_URL` (browsers).

- **DB standalone (en `.env`)**: `POSTGRES_*` + `DATABASE_URL` (credenciales deben coincidir — es el mismo Postgres local).
- **DB/broker infra compartida (override en `.env.backend`)**: `DATABASE_URL`/`RABBITMQ_DSN` comentados por default; se descomentan solo en el VPS y pisan a los standalone.

## Health check y CI

- `GET /health` → `{"status": "ok"}` (`backend/src/Controller/HealthController.php`).
- `.github/workflows/ci.yml` (heredado de main en el sync): triggers `push:main` + `workflow_dispatch`, build con bake + caché GHA, smoke de `/health` y Mercure, migraciones, validación de schema, PHPUnit, guard de `APP_ENV=prod` en el stack prod.

## Chequeos de sanidad (inicio y cierre de sesión)

Correr al **inicio** de cada sesión antes de tocar código:

```bash
git branch --show-current          # debe ser release/plan-market-pulse
git status -s                      # debe estar limpio (o saber qué hay pendiente)
git log --oneline -3               # orientarse en dónde quedó la sesión anterior
docker compose ps                  # todos los servicios healthy (incl. rabbitmq/worker/scheduler por profiles)
docker compose exec backend bin/console doctrine:migrations:status  # sin migraciones pendientes
```

Verificar al **cierre** de sesión antes de cortar:

```bash
git status -s                      # sin archivos sin commitear (salvo intencional)
git log --oneline -3               # el último commit tiene hash real en agent-commits.md
```

Y en `CLAUDE.md` asegurarse de que **"Próximo paso"** apunte al paso correcto para la sesión siguiente.

## Protocolo de explicaciones conceptuales

Cuando el usuario pide que se le explique un concepto (`"explicame X"`, `"enseñame X"`), el agente debe:
1. Agregar la explicación al **final** de `docs/concepts.md` como una nueva sección `## NombreDelConcepto`.
2. Commitear `docs/concepts.md` junto con el trabajo del paso en curso (o en un commit separado si el usuario lo pide).
3. No repetir explicaciones ya presentes en el archivo — si el concepto ya está, referenciarlo.

`docs/concepts.md` es acumulativo: nunca se borra contenido, solo se agrega.

---

## Protocolo de commits del agente

**Cada commit que realice el agente debe registrarse en `agent-commits.md`** antes o junto con el commit de git. El registro es parte del entregable, no opcional.

### Formato obligatorio

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
- `agent-commits.md` se agrega al staging junto con los demás archivos del paso.

> Nota: Oliva/`main` migró a un protocolo más laxo (registrar solo lo interesante, preguntando). CMP conserva el registro **obligatorio por paso del runbook** mientras dure la construcción del plan — es parte del entregable-vidriera.

## Comandos del agente

Ver `claude-commands.md` en la raíz del proyecto para los comandos que el usuario puede invocar en el chat (protocolos de reinicio de sesión, etc.).
