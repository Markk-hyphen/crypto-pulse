# Crypto Pulse

[English](README.md) | **Español**

Plataforma de **inteligencia de mercado cripto en tiempo real**: ingesta de fuentes públicas → enriquecimiento con IA → dashboard en vivo. El titular es **DevOps × IA** — cripto es el dominio de datos, no el producto. Construida sobre el framework [Oliva](https://github.com/Markk-hyphen/oliva).

![PHP](https://img.shields.io/badge/PHP-8.3-black?style=flat-square&logo=php)
![Symfony](https://img.shields.io/badge/Backend-Symfony%207.4-000000?style=flat-square&logo=symfony)
![FrankenPHP](https://img.shields.io/badge/Runtime-FrankenPHP-5C2D91?style=flat-square)
![Vite](https://img.shields.io/badge/Frontend-Vite%206-646CFF?style=flat-square&logo=vite&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/Database-PostgreSQL%20%2B%20pgvector-336791?style=flat-square&logo=postgresql&logoColor=white)
![RabbitMQ](https://img.shields.io/badge/Queues-RabbitMQ-FF6600?style=flat-square&logo=rabbitmq&logoColor=white)
![Mercure](https://img.shields.io/badge/Realtime-Mercure-2EA3F2?style=flat-square)
![Anthropic](https://img.shields.io/badge/AI-Anthropic%20Claude-D97757?style=flat-square)
![Docker](https://img.shields.io/badge/Infrastructure-Docker%20Compose-2496ED?style=flat-square&logo=docker&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)

---

## Qué es esto

Crypto Pulse (CMP) es un **proyecto-vidriera**: su objetivo es mostrar un pipeline de datos asíncrono completo y productivo — colas, workers, tareas programadas, enriquecimiento con LLMs y actualizaciones en vivo — todo contenerizado y orquestado con Docker Compose.

El dominio elegido para tener datos reales que fluyan es el mercado cripto, pero el producto no es "otra app de precios". Lo interesante es la **máquina** que hay detrás:

1. **Ingesta** — un scheduler poll-ea fuentes públicas (RSS de CoinDesk / Cointelegraph, precios de CoinGecko) cada pocos minutos y encola cada novedad.
2. **Enriquecimiento con IA** — un worker consume la cola y, por cada noticia, llama a Claude para extraer sentiment, activos mencionados, clase de activo, resumen y una señal de relevancia (*salience*). De ahí sale un **impact score** combinando esa señal con heurística determinística sobre los datos de mercado.
3. **Embeddings** — el texto enriquecido se vectoriza (pgvector + índice HNSW) para dejar lista la búsqueda semántica y el clustering.
4. **Publicación en vivo** — cada evento se publica por [Mercure](https://mercure.rocks/) y aterriza en el dashboard sin recargar la página.

El énfasis está en que el pipeline sea **robusto**, no solo que funcione: timeouts y retry en las llamadas HTTP, dead-letter saneado en las colas, un sweep de recovery para los ítems huérfanos del dual-write DB↔broker, y un watchdog anti-zombie en el SSE del front.

---

## El pipeline

```
 Fuentes públicas                      Scheduler (supercronic)
 ────────────────                      ───────────────────────
 RSS CoinDesk / Cointelegraph   ◀───   app:sources:poll   (cada 5 min)
 CoinGecko (precios)            ◀───   app:market:poll    (cada 2 min)
          │                                   │
          │  encola NewsItem (pending)        │  guarda MarketSnapshot
          ▼                                   ▼
   RabbitMQ  ──cola `ingest`──▶  worker  ──cola `enrich`──▶  worker
                                   │                            │
                                   │  normaliza                 │  Claude Haiku:
                                   ▼                            ▼  sentiment, assets,
                               PostgreSQL  ◀───────────────  salience, resumen
                               (+ pgvector)                      │
                                   │  embedding (Voyage)         │  ImpactScorer
                                   ▼                             ▼  (60% salience + 40% heurística)
                                   └──────────▶  Mercure  ◀──────┘
                                                   │  topics: crypto/feed, crypto/market-now
                                                   ▼
                                            Dashboard en vivo (pulse.html)

 Agregado de mercado:  app:market:now (cada 10 min) → 1 llamada a Claude Sonnet
                       sobre los últimos ítems enriquecidos → panel "Market Now".
```

Fuera de banda, otros dos jobs cuidan la salud del pipeline: `app:enrich:requeue-pending` (cada 15 min) rescata ítems que quedaron en `pending` por un dual-write a medias, y `app:failed:inspect` permite revisar la cola `failed` de Symfony Messenger.

---

## Stack

| Capa | Tecnología |
|---|---|
| Backend | Symfony 7.4 (PHP 8.3+) · FrankenPHP (worker mode) · Caddy · JWT Auth (Lexik) |
| Frontend | Vite 6 · Vanilla JS · dashboard SSE en vivo (`pulse.html` / `pulse.js`) |
| Base de datos | PostgreSQL + [pgvector](https://github.com/pgvector/pgvector) (índice HNSW parcial para similitud coseno) |
| IA | [Anthropic Claude](https://www.anthropic.com/) — Haiku por volumen (enriquecimiento ítem a ítem), Sonnet para el agregado "Market Now" |
| Embeddings | [Voyage AI](https://www.voyageai.com/) (pluggable vía `EmbeddingProviderInterface`) |
| Tiempo real | [Mercure](https://mercure.rocks/) hub (embebido en Caddy, sin contenedor aparte) |
| Colas | RabbitMQ + Symfony Messenger (transportes `ingest` / `enrich`) |
| Tareas programadas | `supercronic` corriendo `backend/scheduler/crontab` |
| Infraestructura | Docker Compose · multi-stage builds (dev / prod / staging) · overlay de infra compartida |

---

## Levantar el proyecto

### Prerequisitos

- [Docker](https://docs.docker.com/get-docker/) con Compose **v2.24+** (los overlays de infra compartida y staging usan la tag de merge `!override`).

### Desarrollo

```bash
git clone https://github.com/Markk-hyphen/crypto-pulse.git
cd crypto-pulse
cp .env.example .env
# completar .env, .env.backend, .env.frontend
docker compose up
```

> **Importante:** CMP necesita el pipeline completo. El `.env` debe tener
> `COMPOSE_PROFILES=queues,cron` — sin eso, `docker compose up` levanta solo el core
> (backend + frontend + database) y las colas y el scheduler quedan apagados.

En dev no hace falta clave de IA: `services_dev.yaml` alias-ea los providers a implementaciones *null* (`NullEnrichmentProvider`, `NullMarketNowProvider`), así que el pipeline fluye end-to-end a costo cero.

| Servicio | URL |
|---|---|
| Dashboard en vivo | http://localhost:3000/pulse.html |
| Frontend | http://localhost:3000 |
| Backend API | http://localhost:80/api |
| Mercure hub | http://localhost/.well-known/mercure |
| RabbitMQ management | http://localhost:15672 |
| Base de datos | localhost:5432 |

Hot reload activo: los cambios en `backend/src` y `frontend/src` se reflejan al instante sin rebuild.

### Producción

```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml build
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```

El frontend lo sirve Caddy en **http://localhost**. El backend, la base de datos y RabbitMQ son internos — nunca expuestos a un puerto público.

El target de deploy real de CMP es **infra compartida** (`~/infra`: Postgres + RabbitMQ + reverse-proxy compartidos entre varias apps Oliva en un mismo VPS), vía el overlay `docker-compose.shared-infra.yml`. El runbook completo vive en [`CLAUDE.md`](CLAUDE.md) → sección "Infra compartida".

---

## Estructura

```
crypto-pulse/
├── backend/                      # Symfony 7.4 (FrankenPHP + Caddy)
│   ├── src/
│   │   ├── Adapter/              # SourceAdapterInterface + RssAdapter (fuentes de noticias)
│   │   ├── Provider/             # Claude (enrich / market-now), Voyage (embeddings), CoinGecko
│   │   │                         #   + providers Null para dev
│   │   ├── Message/ MessageHandler/   # mensajes y handlers de las colas ingest/enrich
│   │   ├── Service/              # ImpactScorer (señal salience + heurística de mercado)
│   │   ├── Command/              # app:sources:poll, app:market:poll, app:market:now,
│   │   │                         #   app:enrich:requeue-pending, app:failed:inspect
│   │   ├── Entity/               # NewsItem, Enrichment, MarketSnapshot, MarketNowSummary
│   │   └── Controller/Api/       # FeedController (feed REST + filtros), MarketNowController
│   ├── migrations/               # incluye el índice HNSW parcial (SQL crudo)
│   ├── scheduler/crontab         # las 4 tareas programadas del pipeline
│   └── frankenphp/               # config de Caddy + runtime PHP (hub Mercure embebido)
├── frontend/                     # Vite app
│   ├── pulse.html                # dashboard en vivo
│   └── src/js/pulse.js           # suscripción Mercure + filtros + watchdog anti-zombie SSE
├── docs/
│   ├── concepts.md               # glosario técnico acumulativo (a pedido)
│   ├── qa-y-staging.md           # qué QA ofrece el framework y qué no
│   └── oliva/                    # docs DE Oliva que bajan a cada fork (no editar acá)
├── scripts/oliva/                # herramientas de Oliva: sync.sh, deps.sh, verify.sh
├── OLIVA_VERSION                 # versión de Oliva sobre la que está CMP
├── PLAN-MARKET-PULSE.md          # plan completo y runbook ejecutable
├── docker-compose.yml
├── docker-compose.override.yml   # overrides de dev (auto-aplicados)
├── docker-compose.prod.yml
└── docker-compose.shared-infra.yml   # overlay opt-in de infra compartida
```

---

## Decisiones de diseño

- **Broker RabbitMQ, scheduler contenedor cron (supercronic).** Las dos piezas que hacen al pipeline asíncrono, aisladas como servicios opt-in detrás de los profiles `queues` y `cron` de Oliva.
- **LLM Anthropic, por tier según el trabajo.** Haiku para el volumen (una llamada por noticia), Sonnet para el agregado de mercado (una llamada cada 10 min sobre el batch). La capa de caché de Symfony por `contentHash` evita re-llamar sobre lo mismo.
- **`impactScore` barato.** La señal *salience* se pide dentro del mismo JSON del enriquecimiento (sin llamada LLM extra) y se combina 60/40 con una heurística determinística (sentiment, clase de activo, tickers, volatilidad del `MarketSnapshot`).
- **Dead-letter sin ruido.** El failure transport de Symfony es el único camino a la cola `failed`; se quitó el `x-dead-letter-exchange` de las colas para no triplicar cada reject de retry.
- **Fuentes como abstracción.** `SourceAdapterInterface` deja el hueco listo para sumar más fuentes de noticias (p. ej. CryptoPanic) como una fuente más cuando haya API key.

---

## Construido sobre Oliva

CMP es un **fork de [Oliva](https://github.com/Markk-hyphen/oliva)**, el framework base del que salen todas las apps de este stack (backend + frontend + DB + Mercure + colas + scheduler ya cableados). El sync es **one-way, Oliva → CMP**: los archivos del framework (`scripts/oliva/`, `docker-compose*.yml`, el Dockerfile, el workflow de CI) no se editan acá — lo que CMP necesite distinto se agrega como opción en Oliva y baja a todos los forks.

```bash
scripts/oliva/sync.sh check   # ¿cuánto estoy atrás de Oliva? + las notas de upgrade pendientes
scripts/oliva/sync.sh start   # branch + merge de Oliva, con conflictos clasificados
scripts/oliva/deps.sh due     # ¿toca ciclo de deps (~45d)? ¿toca audit de CVEs (~7d)?
```

El flujo completo está en [`docs/oliva/actualizaciones.md`](docs/oliva/actualizaciones.md).

---

## Health check y CI

- `GET /health` → `{"status": "ok"}` (`backend/src/Controller/HealthController.php`).
- `.github/workflows/ci.yml` (heredado de Oliva): build con bake + caché GHA, smoke de `/health` y Mercure, migraciones, validación de schema, PHPUnit y guard de `APP_ENV=prod`.
- Smoke completo local: `scripts/oliva/verify.sh`.

> El paso "Doctrine Schema Validator" está apagado para CMP (`OLIVA_CI_SKIP=schema` en CI, `OLIVA_VERIFY_SKIP=schema` local): pgvector introduce drift estructural que Doctrine no sabe modelar (el tipo `vector` no round-trippea el `length` y el índice HNSW se crea en SQL crudo). Es un rojo conocido y documentado, no una falla.

---

## License

MIT
