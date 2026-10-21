# Crypto Pulse (fork de Oliva)

Proyecto-vidriera **"Crypto Pulse"** (Crypto Market Pulse, CMP): plataforma de inteligencia de mercado cripto en tiempo real (ingesta de fuentes públicas → enriquecimiento con IA → dashboard en vivo vía Mercure). El headline es **DevOps × IA**; cripto es el dominio de datos, no el producto.

Repo propio `Markk-hyphen/crypto-pulse` (público), **fork de Oliva** como finanzas-ong: backend Symfony (FrankenPHP), frontend Vite, PostgreSQL con pgvector, tiempo real vía Mercure, colas vía RabbitMQ + Symfony Messenger, y contenedor scheduler (supercronic) para tareas programadas. Todo orquestado con Docker Compose.

## Sync con Oliva (upstream)

Remote `oliva-upstream` → `https://github.com/Markk-hyphen/oliva.git`. El sync es **one-way Oliva → crypto-pulse** con merge (nunca al revés: el dominio cripto no vuelve al framework; un fix genérico nacido acá se *backportea* a Oliva por su cuenta, ver `docs/oliva/actualizaciones.md`). Herramientas y flujo completo en `docs/oliva/actualizaciones.md`; comando de chat: `claude oliva sync`.

- **Versión de Oliva:** `OLIVA_VERSION` (último sync: **1.1.0**, 2026-10-21).
- **Al inicio de cada sesión:** `scripts/oliva/sync.sh check` (y `scripts/oliva/deps.sh due`). Si avisan, mencionarlo a Marcos; no syncear sin que lo pida.
- **Archivos del framework** (`scripts/oliva/owned-paths.txt`): no editarlos acá. Lo que CMP necesite distinto va como opción en Oliva.
- **Historia:** hasta 2026-10 CMP vivía como rama del repo de Oliva (decisión temprana, no repetible). El sync de 2026-07-02 costó 19 conflictos `add/add` (análisis en `SYNC-NOTES.md`); desde entonces CMP y Oliva comparten ancestro y los merges son 3-way normales.

## Comandos principales

### Desarrollo
```bash
docker compose up
```
El `docker-compose.override.yml` se aplica automáticamente: monta el código fuente con hot-reload, expone el backend en `:80` y el frontend en `:3000`.

El project name de dev es el directorio (`crypto-pulse`) → imágenes `crypto-pulse-backend:dev`/`crypto-pulse-frontend:dev`, volúmenes `crypto-pulse_db_data`/`crypto-pulse_rabbitmq_data`, red `crypto-pulse_app_network`. En el VPS el project es `-p crypto` (`crypto-backend:prod`). Convención de Oliva: nada con nombre fijo (ver "Aislamiento por app" en el `CLAUDE.md` de Oliva).

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
- `docs/oliva/` — docs **de Oliva** (no editar acá): `actualizaciones.md` (updates/sync) y `UPGRADING.md`
- `scripts/oliva/` — herramientas de Oliva: `sync.sh`, `deps.sh`, `verify.sh` (no editar acá)
- `OLIVA_VERSION` — versión de Oliva sobre la que está CMP
- `.env`, `.env.backend`, `.env.frontend` — variables por entorno
- `.env.prod` — variables de producción
- `PLAN-MARKET-PULSE.md` — plan completo y runbook ejecutable (leer §11 "convenciones de ejecución" antes de implementar)
- `SYNC-NOTES.md` — análisis histórico del sync Oliva→CMP de 2026-07-02 (cuando CMP era una rama)
- `agent-commits.md` — log de commits del agente

## Estado del proyecto

- **Hecho:** Fase 0 completa (0.1–0.8) + **Fase 1 completa (1.1–1.8, GATE cumplido)**: modelo de dominio + HNSW, ingesta RSS, poll programado, enriquecimiento IA, Mercure publish + null provider dev, API REST, dashboard en vivo `pulse.html`, robustez del pipeline (timeouts/retry http, DLX saneado + `app:failed:inspect`, sweep de recovery en cron, watchdog anti-zombie-SSE en el front). Syncs con Oliva: 2026-07-02 y 2026-10-21 (1.1.0).
- **Próximo paso (sesión 2026-10-07 en adelante): SESIÓN DE ESTUDIO, no de construcción.** Tras ~3 meses de pausa se corrió una auditoría de reanudación (anexo al final de `docs/estudio-y-auditoria-1.5-2.6.md`): el stack revive intacto, el pipeline fluye end-to-end y hay **20 de 31 hitos** hechos. El plan acordado con Marcos es **A → C** (la etapa B de fixes menores se descartó: no aporta al estudio). **A = repaso activo de 1.5→2.6**: por cada hito, correr su checkpoint contra el stack vivo y **después** leer juntos el código que produjo ese comportamiento (método pedido por Marcos: comportamiento primero como ancla, lectura de código después; él es observador desde 1.6 y nunca escribió ese código, así que no pedirle predicciones en frío hasta que esté caliente en el hito). **1.5 EN CURSO (2026-10-17):** su checkpoint ya se corrió contra el stack vivo (54 eventos SSE en `crypto/feed`, `null-provider`, costo 0) y se armó `docs/estudio-1.5-guia-de-lectura.md` — mapa de lectura en 8 estaciones para que Marcos recorra el código en el IDE él mismo, que es como pidió estudiar. **Estación 1 (`IngestSourceHandler`) cerrada 2026-10-19; la próxima sesión retoma en la Estación 2** (`backend/config/packages/messenger.yaml`: transportes `ingest`/`enrich`, el `delay` del retry y el comentario sobre no-DLX). No re-explicar lo cerrado ni re-correr el checkpoint salvo que él lo pida. Después, 1.6. Un hito por intercambio. **C = el estudio de pgvector/HNSW**, que es el cuello de botella real: bloquea 2.2 + 2.3 + 3.4 + 3.5 + la deuda del diff espurio. Ojo: el índice HNSW ya existe y es parcial (`vector_cosine_ops WHERE embedding IS NOT NULL`) y el gap de embeddings es del **100%** (`VOYAGE_API_KEY` vacía, 0 vectores en la tabla) → hace falta decidir proveedor de embeddings + comando de re-embed antes de 2.2.
- **Estado de los hitos de Fase 2:** 2.4 (Market Now), 2.5 (impact score) y **2.6 (filtros del dashboard) cerrados.** **2.4:** comando `app:market:now` cada 10 min, una sola llamada Sonnet (`claude-sonnet-5`, thinking disabled) por corrida sobre ≤15 items enriquecidos + snapshots, con skip por `sourceHash` si no hubo novedades; topic Mercure propio `crypto/market-now` + panel nuevo en `pulse.html`/`pulse.js` (`agent-commits.md` [PASO 2.4]). **2.5:** columna `impactScore` en `Enrichment` = 60% señal `salience` (pedida dentro del mismo JSON de Haiku, sin llamada LLM nueva) + 40% heurística determinística (sentiment, asset class, tickers, volatilidad vía `MarketSnapshot`); servicio `ImpactScorer`, expuesto en el feed REST/Mercure (`agent-commits.md` [PASO 2.5]). **2.6:** `findFeedPage`/`FeedController` suman `minImpact` y `ticker` (ya tenían `source`/`sentiment`/`assetClass`); barra de filtros en `pulse.html`, `feedUrl()`/`matchesFilters()` en `pulse.js` aplican los mismos filtros a la carga REST y a los eventos Mercure en vivo (`agent-commits.md` [PASO 2.6]). Búsqueda (2.2) queda fuera — no existe todavía. **Sigue 2.7** (opcional: alertas por reglas del usuario) o cerrar el GATE de Fase 2 tal como está. **CryptoPanic en espera indefinida** — Marcos no paga el tier (~USD 50/mes); no se retoma hasta que decida lo contrario. La abstracción `SourceAdapter` ya deja el hueco listo (entra como una fuente de noticias más cuando haya key). **Qué está bloqueado:** 2.2 (búsqueda semántica) y 2.3 (clustering) por el estudio pgvector/HNSW de Marcos.
- **Decisiones cerradas:** broker **RabbitMQ**, scheduler **contenedor cron (supercronic)**, LLM **Anthropic** (Haiku volumen / Sonnet agregados), vector **pgvector**, dominio **cripto** (RSS CoinDesk/Cointelegraph + CoinGecko; CryptoPanic en Fase 2). **Dead-letter (1.8):** el failure transport de Symfony es el ÚNICO camino a la cola `failed` — se quitó el `x-dead-letter-exchange` de `ingest`/`enrich` porque duplicaba cada reject de retry (3 copias-ruido por fallo); inspección con `app:failed:inspect`, reproceso con `messenger:failed:retry`; el porqué completo en `agent-commits.md` [PASO 1.8].
- **Pendiente de estudio (NO avanzar sin Marcos):** pgvector / índice HNSW — bloqueante para Fase 2 (2.2 búsqueda semántica). La migración 1.1 crea un índice HNSW parcial, pero el diseño (parámetros `m`/`ef_construction`, operador de distancia, re-embedding) queda sin definir hasta que Marcos lo estudie.

## Deuda técnica conocida (revisión 2026-06-01, actualizada en el sync 2026-07-02)

- ✅ **Mock de `EnrichmentProvider` en dev — RESUELTO en 1.5.** `NullEnrichmentProvider` + `services_dev.yaml` (renombrado de `services_development.yaml` en el sync: Symfony carga `services_{APP_ENV}.yaml` y APP_ENV ahora es `dev`).
- ✅ **`MERCURE_URL` worker — RESUELTO en 1.5.** Cambiado a `http://backend/...` (nombre de servicio Docker).
- 🟡 **El prompt caching de Anthropic es un no-op.** El system prompt (~250 tokens) está por debajo del mínimo cacheable de Haiku (2048 tokens) → `cache_control: ephemeral` se ignora; no hay ahorro. El header beta `prompt-caching-2024-07-31` ya es innecesario (GA). El ahorro real lo da la capa Symfony Cache por `contentHash`.
- ✅ **Dual-write DB↔broker → items huérfanos en `pending` — RESUELTO en 1.8.** `app:enrich:requeue-pending` corre cada 15 min en el crontab del scheduler, con `--min-age` (default 10 min) para no re-despachar items cuyo mensaje sigue legítimamente en cola.
- ✅ **`RssAdapter` — RESUELTO en 1.8.** Header `User-Agent` agregado; feed no-RSS 2.0 (Atom, HTML) ahora **falla ruidoso** (RuntimeException → retry/DLX) en vez de vacío silencioso. Soporte Atom real no se agregó (ambas fuentes son RSS 2.0).
- 🟢 **`contentHash` es un hash de la URL**, no del contenido. Dedup por URL es razonable; ediciones de título/cuerpo no re-ingestan.
- 🟢 **Gap de re-embedding:** items enriquecidos sin key de Voyage quedan con `embedding=null` permanente. La búsqueda semántica (2.2) los ignora. Necesitará comando de re-embed antes de Fase 2.
- 🟢 **Deuda de Oliva sin resolver, documentada en el `CLAUDE.md` de Oliva** (no se copia acá): los environments de Bruno commiteados se ensucian solos al testear (CMP no tiene colección Bruno todavía). El guard de colisión de nombres de los scripts de deploy se resolvió en Oliva 1.1.0.
- 🟢 **`worker` sin definición de producción** (deuda heredada de Oliva): existe solo en `docker-compose.override.yml` (dev). Antes del deploy real de CMP hay que agregar un `worker` prod (imagen `${COMPOSE_PROJECT_NAME}-backend:prod`, comando `messenger:consume`, sin puertos). `scheduler` sí está cubierto en prod.
- 🔴 **`doctrine:schema:validate` está en rojo por pgvector — romperá el paso "Doctrine Schema Validator" del CI cuando el schema de CMP llegue a CI (apagado con la variable de repo `OLIVA_CI_SKIP=schema` en GitHub; `verify.sh` local: `OLIVA_VERIFY_SKIP=schema`).** Dos fuentes de drift estructural que Doctrine no sabe modelar: (a) el tipo `vector` no round-trippea el `length` (el comparator siempre quiere `ALTER embedding TYPE vector(1024)`); (b) el índice **HNSW** se crea en SQL crudo en la migración 1.1 (`Version20260601054114.php`) y no es expresable en el mapping ORM → Doctrine siempre lo quiere dropear. Por eso `doctrine:migrations:diff` regenera esa migración espuria (se descartó a mano en 2.1) y `schema:validate` sale con exit 2. **No arreglar hasta cerrar el estudio pgvector/HNSW** (ligado al bloqueante de arriba): la solución probable es un tipo Doctrine custom que reporte bien el `length` + declarar el índice como no gestionado por el schema-tool (`schema_filter` o mapping del índice), pero eso es parte del diseño que Marcos tiene que definir.

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

### Runbook de deploy con infra compartida (resumen; canónico en el CLAUDE.md de Oliva)

> **Atajo para redeploys:** `./scripts/deploy.sh` (pull + build + down + up). El setup inicial (pasos 2-4) se hace una sola vez.

1. En el VPS (primera vez): `git clone https://github.com/Markk-hyphen/crypto-pulse.git ~/crypto` — el directorio `crypto` es el que `deploy.sh` usa como `-p`. Después: `cd ~/crypto && git pull`.
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

Staging es **una app más** en el VPS: misma infra compartida, DB propia desechable, project name `-p <app>-staging`, imagen `frankenphp_staging` (incluye Foundry + `doctrine:fixtures:load`). Atajo: `./scripts/deploy-staging.sh`; bajar con `./scripts/down-staging.sh`. Runbook completo y gotchas de precedencia de `APP_ENV` en el CLAUDE.md de Oliva (sección "Runbook de staging").

## Variables de entorno

Ver `.env.example` como referencia. Claves específicas de CMP: `ANTHROPIC_API_KEY` (enrichment; en dev no hace falta — `services_dev.yaml` alias a `NullEnrichmentProvider`), `VOYAGE_API_KEY` (embeddings; vacía = `embedding=null` hasta tener key), `COMPOSE_PROFILES=queues,cron`, `MERCURE_URL=http://backend/.well-known/mercure` (interna, para backend/worker) vs `MERCURE_PUBLIC_URL` (browsers).

- **DB standalone (en `.env`)**: `POSTGRES_*` + `DATABASE_URL` (credenciales deben coincidir — es el mismo Postgres local).
- **DB/broker infra compartida (override en `.env.backend`)**: `DATABASE_URL`/`RABBITMQ_DSN` comentados por default; se descomentan solo en el VPS y pisan a los standalone.

## Health check y CI

- `GET /health` → `{"status": "ok"}` (`backend/src/Controller/HealthController.php`).
- `.github/workflows/ci.yml` (de Oliva; `schema` apagado vía `OLIVA_CI_SKIP`): triggers `push:main` + `workflow_dispatch`, build con bake + caché GHA, smoke de `/health` y Mercure, migraciones, validación de schema, PHPUnit, guard de `APP_ENV=prod` en el stack prod.

## Chequeos de sanidad (inicio y cierre de sesión)

Correr al **inicio** de cada sesión antes de tocar código:

```bash
git branch --show-current          # debe ser main
git status -s                      # debe estar limpio (o saber qué hay pendiente)
git log --oneline -3               # orientarse en dónde quedó la sesión anterior
docker compose ps                  # todos los servicios healthy (incl. rabbitmq/worker/scheduler por profiles)
docker compose exec backend bin/console doctrine:migrations:status  # sin migraciones pendientes
scripts/oliva/sync.sh check        # ¿Oliva avanzó? (avisar a Marcos, no syncear solo)
scripts/oliva/deps.sh due          # ¿toca revisar dependencias propias de CMP?
```

Smoke completo del stack (tras un sync o un cambio de dependencias): `OLIVA_VERIFY_SKIP=schema scripts/oliva/verify.sh` (`schema` en rojo conocido por pgvector, ver deuda 🔴).

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

> Nota: Oliva migró a un protocolo más laxo (registrar solo lo interesante, preguntando). CMP conserva el registro **obligatorio por paso del runbook** mientras dure la construcción del plan — es parte del entregable-vidriera.

## Comandos del agente

Ver `claude-commands.md` en la raíz del proyecto para los comandos que el usuario puede invocar en el chat (protocolos de reinicio de sesión, etc.).
