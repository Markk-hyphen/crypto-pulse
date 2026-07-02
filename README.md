# Oliva

A reusable full-stack framework for building webapps — decoupled backend and frontend, real-time updates, async queues, scheduled tasks, all fully containerized and production-ready out of the box.

![PHP](https://img.shields.io/badge/PHP-8.3-black?style=flat-square&logo=php)
![Symfony](https://img.shields.io/badge/Backend-Symfony%207.4-000000?style=flat-square&logo=symfony)
![FrankenPHP](https://img.shields.io/badge/Runtime-FrankenPHP-5C2D91?style=flat-square)
![Vite](https://img.shields.io/badge/Frontend-Vite%206-646CFF?style=flat-square&logo=vite&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/Database-PostgreSQL%20%2B%20pgvector-336791?style=flat-square&logo=postgresql&logoColor=white)
![RabbitMQ](https://img.shields.io/badge/Queues-RabbitMQ-FF6600?style=flat-square&logo=rabbitmq&logoColor=white)
![Mercure](https://img.shields.io/badge/Realtime-Mercure-2EA3F2?style=flat-square)
![Docker](https://img.shields.io/badge/Infrastructure-Docker%20Compose-2496ED?style=flat-square&logo=docker&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)

---

## What this is

Oliva is the base every new project starts from: a backend, a frontend, a database, real-time messaging, async queues, and a cron-style scheduler — already wired together, already passing CI. New apps fork it and build features on top instead of re-solving infrastructure.

## Stack

| Layer | Technology |
|---|---|
| Backend | Symfony 7.4 (PHP 8.3+) · FrankenPHP (worker mode) · Caddy · JWT Auth (Lexik) |
| Frontend | Vite 6 · Vanilla JS · Bootstrap 5 · Swiper · SweetAlert2 |
| Database | PostgreSQL + [pgvector](https://github.com/pgvector/pgvector) (vector similarity search) |
| Real-time | [Mercure](https://mercure.rocks/) hub (built into Caddy) |
| Queues | RabbitMQ + Symfony Messenger |
| Scheduled tasks | `supercronic` running `backend/scheduler/crontab` |
| Staging / seeding | [Foundry](https://symfony.com/bundles/ZenstruckFoundryBundle/current/index.html) + Doctrine Fixtures · `frankenphp_staging` Docker stage |
| API testing | [Bruno](https://www.usebruno.com/) collection in `api/` (per-app, not shipped by Oliva — the requests are 100% domain-specific) |
| Infrastructure | Docker Compose · bridge network · multi-stage builds (dev / prod / staging) |

See `docs/concepts.md` for explanations of the less obvious pieces (pgvector, AMQP, Mercure, etc.) and `docs/examples/` for reference skeletons of a queue producer/consumer and a Mercure publisher.

---

## Getting started

### Prerequisites

- [Docker](https://docs.docker.com/get-docker/) with Compose v2.10+

### Development

```bash
git clone https://github.com/Markk-hyphen/oliva.git
cd oliva
cp .env.example .env
# fill in your values in .env, .env.backend, .env.frontend
docker compose up
```

| Service | URL |
|---|---|
| Frontend | http://localhost:3000 |
| Backend API | http://localhost:80/api |
| Mercure hub | http://localhost/.well-known/mercure |
| RabbitMQ management | http://localhost:15672 |
| Database | localhost:5432 |

Hot reload is enabled — changes to `backend/src` and `frontend/src` reflect instantly without rebuilding. In dev, a `worker` service also runs `messenger:consume` against the `ingest`/`enrich` queues (commented out by default, see `docs/examples/`).

### Production

```bash
# Build production images
docker compose -f docker-compose.yml -f docker-compose.prod.yml build

# Start
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```

The frontend is served by Caddy on **http://localhost**. The backend, database, RabbitMQ and scheduler are internal — never directly reachable from outside.

> **Known gap:** there's no production `worker` service yet. If your app uses Messenger queues for real, add one to `docker-compose.prod.yml` (image `app-backend-prod:1.0`, command `messenger:consume`, no exposed ports) before going live — `scheduler` is already covered in prod.

---

## Project structure

```
oliva/
├── backend/                # Symfony 7.4 app (FrankenPHP + Caddy)
│   ├── src/
│   ├── config/
│   ├── migrations/
│   ├── scheduler/          # crontab consumed by supercronic
│   └── frankenphp/         # Caddy and PHP runtime config
├── frontend/                # Vite app
│   ├── src/
│   │   └── js/live.js      # Mercure live-update demo
│   └── Caddyfile           # Production static file server config
├── docs/
│   ├── concepts.md         # cumulative glossary (pgvector, AMQP, Mercure...)
│   └── examples/           # *.php.example reference skeletons (not live code)
├── docker-compose.yml
├── docker-compose.override.yml   # Dev overrides (auto-applied): worker, exposed ports
├── docker-compose.prod.yml       # Production overrides
├── .env.example
├── .env.backend
└── .env.frontend
```

---

## Optional services (Compose profiles)

The core stack — `backend`, `frontend`, `database` — always comes up. Optional
services live behind **Docker Compose profiles**, so a fork only runs what it
needs. The lever is the `COMPOSE_PROFILES` variable (in `.env`): empty = core
only; otherwise a comma-separated list of profiles to enable.

| Profile | Services it brings up | Variables you must set |
|---|---|---|
| _(none)_ | `backend`, `frontend`, `database` | `DATABASE_URL`, `APP_SECRET`, JWT + Mercure keys |
| `queues` | `+ rabbitmq`, `+ worker` (dev) | `RABBITMQ_USER`, `RABBITMQ_PASSWORD`, `RABBITMQ_DSN` |

```bash
# Core only (default):
COMPOSE_PROFILES=        docker compose up -d

# With queues:
COMPOSE_PROFILES=queues  docker compose up -d
```

> **Rule:** if you enable a profile, configure its variables too. A service
> can come up via its profile and still crash at boot if its DSN/keys are
> missing — that coherence is the fork's responsibility, not the framework's.

> **Caveat:** Compose only stops what's *not requested anymore* on its own
> when the containers don't exist yet. If a profiled service is already
> running and you remove it from `COMPOSE_PROFILES`, `docker compose up -d`
> won't stop it for you — run `docker compose stop <service>` (or `down`)
> explicitly.

### Always-on, not behind a profile

- **`scheduler`** — `supercronic` against `backend/scheduler/crontab`. Cheap; if
  your app has no cron jobs, just leave `crontab` empty (or remove the block).
- **`database`** — image `pgvector/pgvector:pg${POSTGRES_VERSION}`, a normal
  Postgres with the `vector` extension compiled in. Costs nothing if you don't
  use `vector` columns.
- **Mercure** (`/.well-known/mercure`) — runs *inside* the backend via Caddy's
  built-in hub (`backend/frankenphp/Caddyfile`), not as a separate container, so
  there's nothing to toggle. The live canvas demo (`backend/public/live.php` +
  `frontend/src/js/live.js`) shows it working out of the box.

### Adding a new profile

When a future optional service appears (e.g. a search engine, a cache):

1. Add the service block to `docker-compose.yml` with `profiles: ["<name>"]`
   (and to `docker-compose.override.yml` if it has a dev-only variant).
2. **Do not** let core services (`backend`, `scheduler`, …) `depends_on` a
   profiled service — Compose would pull it back up even with the profile off,
   defeating the lever. Wire dependencies only between services in the same
   profile.
3. Add a row to the table above with the variables the profile requires.
4. Document the profile name in `.env.example` next to `COMPOSE_PROFILES`.

> This profile mechanism is the v1 bridge. The destination (v2.0) is
> install-time flags / scaffolding that builds each fork with only the services
> it asked for, instead of inheriting everything and switching it off here.

---

## Environment variables

Copy `.env.example` to `.env` and fill in your values. Grouped by service:

| Variable | Description |
|---|---|
| `POSTGRES_USER` / `POSTGRES_PASSWORD` / `POSTGRES_DB` / `POSTGRES_VERSION` | Database credentials and Postgres version |
| `DATABASE_URL` | Doctrine connection string. Standalone: lives in `.env`, credentials must match `POSTGRES_*`. Shared infra: uncomment/set the override in `.env.backend` |
| `APP_SECRET` | Symfony secret key |
| `JWT_PASSPHRASE` | JWT signing passphrase |
| `SERVER_NAME` | Domain name (default: `localhost`) |
| `APP_ENV` | `development` or `production` |
| `RABBITMQ_USER` / `RABBITMQ_PASSWORD` / `RABBITMQ_DSN` | RabbitMQ credentials and Messenger transport DSN |
| `MERCURE_URL` / `MERCURE_PUBLIC_URL` / `CADDY_MERCURE_URL` / `CADDY_MERCURE_PUBLIC_URL` | Mercure hub URLs (internal vs public) |
| `MERCURE_PUBLISHER_JWT_KEY` / `MERCURE_JWT_SECRET` | Mercure JWT signing keys |

---

## Architecture

```
Browser
  │  HTTP
  ▼
Frontend (Caddy · Vite)
  │  /api/*                 │  /.well-known/mercure
  ▼                         ▼
Backend (FrankenPHP · Symfony) ── Mercure hub (Caddy)
  │  SQL              │  AMQP
  ▼                    ▼
PostgreSQL          RabbitMQ ── worker / scheduler (Messenger consumers, cron)
  (+ pgvector)
```

The frontend proxies all `/api/*` requests to the backend over the internal Docker bridge network. The backend, database and RabbitMQ are never exposed on a public port in production; the scheduler runs cron-style jobs against the backend codebase.

---

## Health check and CI

- `GET /health` → `{"status": "ok"}` (`backend/src/Controller/HealthController.php`).
- `.github/workflows/ci.yml` builds the images, brings up the full stack, checks `/health` and `/.well-known/mercure`, runs migrations, validates the Doctrine schema, and runs PHPUnit. A separate job lints the backend `Dockerfile` with hadolint.

---

## License

MIT
