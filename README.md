# Crypto Pulse

**English** | [Español](README.es.md)

A **real-time crypto market intelligence** platform: ingest public sources → enrich with AI → live dashboard. The headline is **DevOps × AI** — crypto is the data domain, not the product. Built on the [Oliva](https://github.com/Markk-hyphen/oliva) framework.

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

## What this is

Crypto Pulse (CMP) is a **showcase project**: its goal is to demonstrate a complete, production-grade asynchronous data pipeline — queues, workers, scheduled tasks, LLM enrichment and live updates — all containerized and orchestrated with Docker Compose.

The domain chosen to have real data flowing through it is the crypto market, but the product isn't "yet another price app". What's interesting is the **machinery** behind it:

1. **Ingest** — a scheduler polls public sources (CoinDesk / Cointelegraph RSS, CoinGecko prices) every few minutes and enqueues each new item.
2. **AI enrichment** — a worker consumes the queue and, for each news item, calls Claude to extract sentiment, mentioned assets, asset class, a summary and a relevance signal (*salience*). From that comes an **impact score** combining that signal with deterministic heuristics over market data.
3. **Embeddings** — the enriched text is vectorized (pgvector + HNSW index) to make semantic search and clustering ready to go.
4. **Live publishing** — every event is published over [Mercure](https://mercure.rocks/) and lands on the dashboard without a page reload.

The emphasis is on the pipeline being **robust**, not just working: timeouts and retry on HTTP calls, a sanitized dead-letter setup on the queues, a recovery sweep for items orphaned by the DB↔broker dual-write, and an anti-zombie watchdog on the front-end SSE.

---

## The pipeline

```
 Public sources                        Scheduler (supercronic)
 ──────────────                        ───────────────────────
 RSS CoinDesk / Cointelegraph   ◀───   app:sources:poll   (every 5 min)
 CoinGecko (prices)             ◀───   app:market:poll    (every 2 min)
          │                                   │
          │  enqueues NewsItem (pending)      │  stores MarketSnapshot
          ▼                                   ▼
   RabbitMQ  ──queue `ingest`──▶  worker  ──queue `enrich`──▶  worker
                                   │                             │
                                   │  normalizes                 │  Claude Haiku:
                                   ▼                             ▼  sentiment, assets,
                               PostgreSQL  ◀───────────────  salience, summary
                               (+ pgvector)                      │
                                   │  embedding (Voyage)         │  ImpactScorer
                                   ▼                             ▼  (60% salience + 40% heuristics)
                                   └──────────▶  Mercure  ◀──────┘
                                                   │  topics: crypto/feed, crypto/market-now
                                                   ▼
                                            Live dashboard (pulse.html)

 Market aggregate:  app:market:now (every 10 min) → 1 Claude Sonnet call
                    over the latest enriched items → "Market Now" panel.
```

Out of band, two more jobs keep the pipeline healthy: `app:enrich:requeue-pending` (every 15 min) rescues items left in `pending` by a half-completed dual-write, and `app:failed:inspect` lets you review Symfony Messenger's `failed` queue.

---

## Stack

| Layer | Technology |
|---|---|
| Backend | Symfony 7.4 (PHP 8.3+) · FrankenPHP (worker mode) · Caddy · JWT Auth (Lexik) |
| Frontend | Vite 6 · Vanilla JS · live SSE dashboard (`pulse.html` / `pulse.js`) |
| Database | PostgreSQL + [pgvector](https://github.com/pgvector/pgvector) (partial HNSW index for cosine similarity) |
| AI | [Anthropic Claude](https://www.anthropic.com/) — Haiku for volume (per-item enrichment), Sonnet for the "Market Now" aggregate |
| Embeddings | [Voyage AI](https://www.voyageai.com/) (pluggable via `EmbeddingProviderInterface`) |
| Real-time | [Mercure](https://mercure.rocks/) hub (embedded in Caddy, no separate container) |
| Queues | RabbitMQ + Symfony Messenger (`ingest` / `enrich` transports) |
| Scheduled tasks | `supercronic` running `backend/scheduler/crontab` |
| Infrastructure | Docker Compose · multi-stage builds (dev / prod / staging) · shared-infra overlay |

---

## Getting started

### Prerequisites

- [Docker](https://docs.docker.com/get-docker/) with Compose **v2.24+** (the shared-infra and staging overlays use the `!override` merge tag).

### Development

```bash
git clone https://github.com/Markk-hyphen/crypto-pulse.git
cd crypto-pulse
cp .env.example .env
# fill in your values in .env, .env.backend, .env.frontend
docker compose up
```

> **Important:** CMP needs the full pipeline. Your `.env` must set
> `COMPOSE_PROFILES=queues,cron` — without it, `docker compose up` brings up only the core
> (backend + frontend + database) and the queues and scheduler stay off.

No AI key is needed in dev: `services_dev.yaml` aliases the providers to *null* implementations (`NullEnrichmentProvider`, `NullMarketNowProvider`), so the pipeline flows end-to-end at zero cost.

| Service | URL |
|---|---|
| Live dashboard | http://localhost:3000/pulse.html |
| Frontend | http://localhost:3000 |
| Backend API | http://localhost:80/api |
| Mercure hub | http://localhost/.well-known/mercure |
| RabbitMQ management | http://localhost:15672 |
| Database | localhost:5432 |

Hot reload is on: changes to `backend/src` and `frontend/src` reflect instantly without rebuilding.

### Production

```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml build
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```

The frontend is served by Caddy on **http://localhost**. The backend, database and RabbitMQ are internal — never exposed on a public port.

CMP's real deploy target is **shared infra** (`~/infra`: Postgres + RabbitMQ + reverse-proxy shared across several Oliva apps on one VPS), via the `docker-compose.shared-infra.yml` overlay. The full runbook lives in [`CLAUDE.md`](CLAUDE.md) → "Infra compartida" section.

---

## Project structure

```
crypto-pulse/
├── backend/                      # Symfony 7.4 (FrankenPHP + Caddy)
│   ├── src/
│   │   ├── Adapter/              # SourceAdapterInterface + RssAdapter (news sources)
│   │   ├── Provider/             # Claude (enrich / market-now), Voyage (embeddings), CoinGecko
│   │   │                         #   + Null providers for dev
│   │   ├── Message/ MessageHandler/   # messages and handlers for the ingest/enrich queues
│   │   ├── Service/              # ImpactScorer (salience signal + market heuristics)
│   │   ├── Command/              # app:sources:poll, app:market:poll, app:market:now,
│   │   │                         #   app:enrich:requeue-pending, app:failed:inspect
│   │   ├── Entity/               # NewsItem, Enrichment, MarketSnapshot, MarketNowSummary
│   │   └── Controller/Api/       # FeedController (REST feed + filters), MarketNowController
│   ├── migrations/               # includes the partial HNSW index (raw SQL)
│   ├── scheduler/crontab         # the pipeline's 4 scheduled tasks
│   └── frankenphp/               # Caddy + PHP runtime config (embedded Mercure hub)
├── frontend/                     # Vite app
│   ├── pulse.html                # live dashboard
│   └── src/js/pulse.js           # Mercure subscription + filters + anti-zombie SSE watchdog
├── docs/
│   ├── concepts.md               # cumulative technical glossary (on request)
│   ├── qa-y-staging.md           # what QA the framework offers and what it doesn't
│   └── oliva/                    # Oliva's OWN docs, shipped down to each fork (don't edit here)
├── scripts/oliva/                # Oliva's tooling: sync.sh, deps.sh, verify.sh
├── OLIVA_VERSION                 # the Oliva version CMP is on
├── PLAN-MARKET-PULSE.md          # full plan and executable runbook
├── docker-compose.yml
├── docker-compose.override.yml   # dev overrides (auto-applied)
├── docker-compose.prod.yml
└── docker-compose.shared-infra.yml   # opt-in shared-infra overlay
```

---

## Design decisions

- **RabbitMQ broker, cron-container scheduler (supercronic).** The two pieces that make the pipeline asynchronous, isolated as opt-in services behind Oliva's `queues` and `cron` profiles.
- **Anthropic LLM, tiered by the job.** Haiku for volume (one call per news item), Sonnet for the market aggregate (one call every 10 min over the batch). Symfony's cache layer keyed by `contentHash` avoids re-calling on the same content.
- **Cheap `impactScore`.** The *salience* signal is requested inside the same enrichment JSON (no extra LLM call) and combined 60/40 with a deterministic heuristic (sentiment, asset class, tickers, `MarketSnapshot` volatility).
- **Noise-free dead-letter.** Symfony's failure transport is the only path to the `failed` queue; the `x-dead-letter-exchange` was removed from the queues so every retry reject isn't tripled.
- **Sources as an abstraction.** `SourceAdapterInterface` leaves the slot ready to add more news sources (e.g. CryptoPanic) as just another source once there's an API key.

---

## Built on Oliva

CMP is a **fork of [Oliva](https://github.com/Markk-hyphen/oliva)**, the base framework all apps in this stack come from (backend + frontend + DB + Mercure + queues + scheduler already wired together). The sync is **one-way, Oliva → CMP**: framework files (`scripts/oliva/`, `docker-compose*.yml`, the Dockerfile, the CI workflow) aren't edited here — whatever CMP needs differently is added to Oliva as an option and ships down to every fork.

```bash
scripts/oliva/sync.sh check   # how far behind Oliva am I? + the upgrade notes I haven't applied
scripts/oliva/sync.sh start   # branch + merge Oliva, with conflicts classified
scripts/oliva/deps.sh due     # time for a deps cycle (~45d)? for a CVE audit (~7d)?
```

The full flow is documented in [`docs/oliva/actualizaciones.md`](docs/oliva/actualizaciones.md).

---

## Health check and CI

- `GET /health` → `{"status": "ok"}` (`backend/src/Controller/HealthController.php`).
- `.github/workflows/ci.yml` (inherited from Oliva): build with bake + GHA cache, `/health` and Mercure smoke test, migrations, schema validation, PHPUnit, and an `APP_ENV=prod` guard. Docs-only pushes are skipped via `paths-ignore`.
- Full local smoke test: `scripts/oliva/verify.sh`.

> The "Doctrine Schema Validator" step is turned off for CMP (`OLIVA_CI_SKIP=schema` in CI, `OLIVA_VERIFY_SKIP=schema` locally): pgvector introduces structural drift Doctrine can't model (the `vector` type doesn't round-trip its `length`, and the HNSW index is created in raw SQL). It's a known, documented red — not a failure.

---

## License

MIT
