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
![Security](https://img.shields.io/badge/Security-CVE%20audit%20%2B%20Trivy-2E7D32?style=flat-square&logo=letsencrypt&logoColor=white)
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

## Staying patched

A framework built on PHP, FrankenPHP and a stack of base images lives or dies by how fast it reacts to a CVE. Oliva's answer isn't "trust us, it's patched" — it's a workflow that makes *falling behind something you have to actively ignore*. It does not patch you automatically; it makes staying patched the default and makes an unpatched state loud.

- **Security runs on its own clock, separate from freshness.** The routine dependency cycle (`deps.sh update`, ~45 days) is about staying current. A critical CVE doesn't wait for it. `deps.sh audit` runs **on demand**, and `deps.sh due` — a one-second offline check meant to run when you open a session — nags once it's been more than a week since the last audit. You don't go hunting for the news; the workflow surfaces it.
- **Three layers audited, including the one `composer audit` can't see.** `composer audit` (PHP packages) + `yarn audit` (JS packages) + **[Trivy](https://trivy.dev/)** scanning the OS packages and binaries *inside* the base images — which is exactly where a runtime-level PHP or libc CVE lives. One source per layer, never stacked. Trivy is version-pinned and run as a container (no trust in a floating action tag — a compromised tag is itself a documented supply-chain failure mode, so the version is pinned and audited like any other image).
- **`verify` proves the *running* PHP is the patched one.** Rebuilding with a fixed image isn't the same as serving it: a reused worker can keep running the old binary, and that gap is the classic way a PHP CVE "fix" quietly doesn't take effect. `verify.sh` fails if the PHP the backend actually serves doesn't match the exact version pinned in the Dockerfile — closing the loop that's easiest to skip under pressure and leaves no trace.
- **Every fork inherits all of it for free.** `deps.sh audit` runs identically in Oliva and in every app built on it, so when a CVE lands you audit the whole fleet with one command instead of per-repo archaeology. The CI runs the Trivy scan on every build (opt-out per fork).

The mechanics and the per-layer reasoning live under [Staying up to date](#staying-up-to-date-forks) and in [`docs/oliva/actualizaciones.md`](docs/oliva/actualizaciones.md).

## Built for agentic development

Oliva treats the AI agent (or a new human) as an executor that needs guardrails, and ships them with the code. The rules travel with every fork — they're not a local IDE setup.

- **`AGENTS.md` per repo** — operating rules, boundaries and conventions an agent reads before touching code.
- **File ownership** (`scripts/oliva/owned-paths.txt`) — which files are framework-owned and off-limits to forks. A convention, not a lock: git won't stop you, but `sync.sh` classifies every edit as a conflict and surfaces drift on the next sync.
- **Enforced gates** — `release.sh` refuses to cut a version without its `UPGRADING.md` section (the only channel Oliva has to its forks); the project guard (`scripts/lib/project-guard.sh`) aborts a deploy that would collide with another app on the same host.
- **Maintenance cadence** — `deps.sh due` tells an agent when a freshness cycle or a security audit is due, so patching isn't left to memory.

None of this lives in a personal config — it's in the repo, inspectable and versioned.

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

👉 **[`docs/qa-y-staging.md`](docs/qa-y-staging.md)** covers all of this in depth, plus the
**staging stack** (prod's build with a throwaway database and seeded data) and what this
framework deliberately does *not* verify.

> Deploying several Oliva apps onto one host with a shared Postgres / RabbitMQ /
> reverse-proxy is supported through the opt-in `docker-compose.shared-infra.yml` overlay.
> The per-app runbook lives in `AGENTS.md`.

---

## License

MIT
