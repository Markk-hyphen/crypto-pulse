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
![Security](https://img.shields.io/badge/Security-CVE%20audit%20%2B%20Trivy-2E7D32?style=flat-square&logo=letsencrypt&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)

---

## What this is

Oliva is the base every new project starts from: a backend, a frontend, a database, real-time messaging, async queues, and a cron-style scheduler — already wired together, already passing CI. New apps fork it and build features on top instead of re-solving infrastructure.

## Staying patched

A framework built on PHP, FrankenPHP and a stack of base images lives or dies by how fast it reacts to a CVE. Oliva's answer isn't "trust us, it's patched" — it's a workflow that makes *falling behind something you have to actively ignore*. It does not patch you automatically; it makes staying patched the default and makes an unpatched state loud.

- **Security runs on its own clock, separate from freshness.** The routine dependency cycle (`deps.sh update`, ~45 days) is about staying current. A critical CVE doesn't wait for it. `deps.sh audit` runs **on demand**, and `deps.sh due` — a one-second offline check meant to run when you open a session — nags once it's been more than a week since the last audit. You don't go hunting for the news; the workflow surfaces it.
- **Three layers audited, including the one `composer audit` can't see.** `composer audit` (PHP packages) + `yarn audit` (JS packages) + **[Trivy](https://trivy.dev/)** scanning the OS packages and binaries *inside* the base images — which is exactly where a runtime-level PHP or libc CVE lives. One source per layer, never stacked. Trivy is version-pinned and run as a container (no trust in a floating action tag — a compromised tag is itself a documented supply-chain failure mode, so the version is pinned and audited like any other image).
- **`verify` proves the *running* PHP is the patched one.** Rebuilding with a fixed image isn't the same as serving it: a reused worker can keep running the old binary, and that gap is the classic way a PHP CVE "fix" quietly doesn't take effect. `verify.sh` fails if the PHP the backend actually serves doesn't match the exact version pinned in the Dockerfile — closing the loop that's easiest to skip under pressure and leaves no trace.
- **Every fork inherits all of it for free.** `deps.sh audit` runs identically in Oliva and in every app built on it, so when a CVE lands you audit the whole fleet with one command instead of per-repo archaeology. The CI runs the Trivy scan on every build (opt-out per fork).

The mechanics and the per-layer reasoning live under [Staying up to date](#staying-up-to-date-forks) and in [`docs/oliva/actualizaciones.md`](docs/oliva/actualizaciones.md).

## Built for agentic development

Oliva treats the AI agent (or a new human) as an executor that needs guardrails, and ships them with the code. The rules travel with every fork — they're not a local IDE setup.

- **`CLAUDE.md` per repo** — operating rules, boundaries and conventions an agent reads before touching code.
- **File ownership** (`scripts/oliva/owned-paths.txt`) — which files are framework-owned and off-limits to forks. A convention, not a lock: git won't stop you, but `sync.sh` classifies every edit as a conflict and surfaces drift on the next sync.
- **Enforced gates** — `release.sh` refuses to cut a version without its `UPGRADING.md` section (the only channel Oliva has to its forks); the project guard (`scripts/lib/project-guard.sh`) aborts a deploy that would collide with another app on the same host.
- **Maintenance cadence** — `deps.sh due` tells an agent when a freshness cycle or a security audit is due, so patching isn't left to memory.

None of this lives in a personal config — it's in the repo, inspectable and versioned.

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

See [`docs/concepts.md`](docs/concepts.md) for explanations of the less obvious pieces
(pgvector, AMQP, Mercure, the fork sync model), [`docs/qa-y-staging.md`](docs/qa-y-staging.md)
for what QA the framework offers and how the staging stack works, and `docs/examples/` for
reference skeletons of a queue producer/consumer and a Mercure publisher.

---

## Getting started

### Prerequisites

- [Docker](https://docs.docker.com/get-docker/) with Compose **v2.24+**

  v2.10 is enough for the core dev stack, but the shared-infra and staging overlays use
  the `!override` merge tag, which needs 2.24. Check with `docker compose version`.

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

The frontend is served by Caddy on **http://localhost**. The backend and database are
internal — never directly reachable from outside. `rabbitmq` and `scheduler` are opt-in
behind profiles (see [Optional services](#optional-services-compose-profiles)); when
enabled they are internal too.

> **Known gap:** there's no production `worker` service yet. If your app uses Messenger queues for real, add one to `docker-compose.prod.yml` (image `${COMPOSE_PROJECT_NAME}-backend:prod`, command `messenger:consume`, no exposed ports) before going live — `scheduler` is already covered in prod.

---

## Project structure

```
oliva/
├── OLIVA_VERSION           # framework version this checkout is on (see Staying up to date)
├── backend/                # Symfony 7.4 app (FrankenPHP + Caddy)
│   ├── src/
│   │   └── DataFixtures/   # Foundry fixtures, grouped by env (staging / dev)
│   ├── config/
│   ├── migrations/
│   ├── php-extensions.txt  # the FORK's extra PHP extensions — Oliva ships it empty
│   ├── scheduler/          # crontab consumed by supercronic
│   └── frankenphp/         # Caddy and PHP runtime config
├── frontend/               # Vite app
│   ├── src/
│   │   └── js/live.js      # Mercure live-update demo
│   └── Caddyfile           # Production static file server config
├── docs/
│   ├── concepts.md         # cumulative glossary (pgvector, AMQP, Mercure...)
│   ├── qa-y-staging.md     # what QA the framework offers + the staging stack
│   ├── oliva/              # framework docs that ship down to every fork
│   │   ├── actualizaciones.md   # the update/sync system, in full
│   │   └── UPGRADING.md         # per-version notes a fork must act on
│   └── examples/           # *.php.example reference skeletons (not live code)
├── scripts/
│   ├── deploy.sh           # redeploy (pull + build + up), prod
│   ├── deploy-staging.sh   # redeploy staging (+ migrations + fixtures)
│   ├── down.sh / down-staging.sh
│   ├── lib/                # project-name collision guard, docker prune
│   └── oliva/              # framework maintenance: deps, sync, verify, release
├── docker-compose.yml
├── docker-compose.override.yml       # Dev overrides (auto-applied): worker, exposed ports
├── docker-compose.prod.yml           # Production overrides
├── docker-compose.staging.yml        # Staging overlay (see docs/qa-y-staging.md)
├── docker-compose.shared-infra.yml   # Opt-in: shared Postgres/RabbitMQ/proxy on one host
├── secrets/                # JWT keys, generated at first boot (gitignored)
├── .env.example
├── .env.staging.example
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
| `cron` | `+ scheduler` | none — but `backend/scheduler/crontab` must be filled, or it runs nothing |

```bash
# Core only (default):
COMPOSE_PROFILES=        docker compose up -d

# With queues:
COMPOSE_PROFILES=queues  docker compose up -d

# With queues and scheduled tasks:
COMPOSE_PROFILES=queues,cron  docker compose up -d
```

> **Rule:** if you enable a profile, configure its variables too. A service
> can come up via its profile and still crash at boot if its DSN/keys are
> missing — that coherence is the fork's responsibility, not the framework's.

> **Caveat:** Compose only stops what's *not requested anymore* on its own
> when the containers don't exist yet. If a profiled service is already
> running and you remove it from `COMPOSE_PROFILES`, `docker compose up -d`
> won't stop it for you — run `docker compose stop <service>` (or `down`)
> explicitly.

> **Careful — a profiled service you forget to enable fails silently.** If your app
> has cron jobs but you never set `COMPOSE_PROFILES=cron`, `scheduler` simply never
> comes up: no error, no warning, and your jobs never run. Same for `queues` and
> your Messenger consumers.

### Always-on, not behind a profile

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

## Staying up to date (forks)

Oliva is versioned (`OLIVA_VERSION`, tags `vX.Y.Z`) and apps built with it live in
**separate repos** — they are not Compose projects inside this one. The link back is a git
remote called `oliva-upstream`, configured **in the fork**.

The important thing to understand up front: **this is pull, not push.** Oliva does not
know its forks exist — there is no registry, no webhook, no listener. Git has no
push-to-downstream, and Oliva holds no credentials to write to anyone. Every sync is
started by the fork. (The mechanism is explained in full in
[`docs/concepts.md`](docs/concepts.md#el-sync-oliva--forks-por-qué-es-pull-no-push).)

### In a fork: stay current

```bash
scripts/oliva/sync.sh check   # how far behind am I? + the upgrade notes I haven't applied
scripts/oliva/sync.sh start   # branch + merge Oliva, with conflicts classified
scripts/oliva/sync.sh locks   # regenerate composer.lock / yarn.lock
scripts/oliva/sync.sh verify  # = scripts/oliva/verify.sh
```

`check` is cheap and offline-friendly — run it when you open a session, because **nothing
will tell you otherwise**: the upgrade notes travel in the same fetch as the code, so
there is no advance warning.

### In Oliva: ship a version

```bash
scripts/oliva/deps.sh due      # time for a maintenance cycle (~45d)? for a security audit (~7d)?
scripts/oliva/deps.sh report   # EOL, images, composer, yarn, actions, CVEs
scripts/oliva/deps.sh update   # bump within ranges + verify + commit
scripts/oliva/deps.sh audit    # CVE audit across all three layers (composer + yarn + container images)
scripts/oliva/release.sh X.Y.Z # tag a release
```

**Security runs on its own clock.** The 45-day cycle is about *freshness*; a critical CVE
isn't. `deps.sh audit` — runnable in Oliva *and in every fork* — checks the three dependency
layers for known CVEs with a published fix, and `deps.sh due` nags once it's been more than a
week. The point of it is the layer `composer audit` / `yarn audit` can't see: the OS packages
and binaries *inside* the base images (scanned with Trivy). It's not runtime protection — it
tells you when something you've pinned has a fix waiting. One source per layer, not stacked:
the why is in [`docs/oliva/actualizaciones.md`](docs/oliva/actualizaciones.md).

### File ownership

`scripts/oliva/owned-paths.txt` lists the files that belong to Oliva (`backend/Dockerfile`,
`docker-compose*.yml`, `scripts/`, the CI workflow, …). **A fork does not edit them** — if
it needs something different, that something gets added to Oliva as an option and ships
down to everyone. This is a convention, not a technical lock: git won't stop you, but
every file you edit becomes a conflict on every future sync.

The escape hatch for the most common case is `backend/php-extensions.txt` — see below.

> **If you change something a fork must act on** (a rename, a new variable, a manual step),
> write it into `docs/oliva/UPGRADING.md` in the same commit. That file is the *only*
> channel Oliva has to its forks, and `release.sh` refuses to publish a version without
> its section.

The whole system is documented in [`docs/oliva/actualizaciones.md`](docs/oliva/actualizaciones.md).

### Adding PHP extensions without touching Oliva's Dockerfile

`backend/php-extensions.txt` is the fork's extension point. Oliva ships it empty and never
changes it, so it never conflicts on a sync:

```
# one per line
bcmath
redis-6.2.0
```

Extensions bundled with PHP (`bcmath`, `gmp`, …) go without a version — the base image
pins those. PECL extensions get an exact version.

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
- `.github/workflows/ci.yml` runs three jobs on every push and PR: **Tests** (build the
  images, bring up the stack, check `/health` and `/.well-known/mercure`, run migrations,
  validate the Doctrine schema, run PHPUnit), **Prod config guard** (`APP_ENV` really
  resolves to `prod` in the production stack), and **Docker Lint** (hadolint).
- `scripts/oliva/verify.sh` is the same smoke test, locally and in one command — run it
  after a sync, after touching the `Dockerfile`, or before a release.
- A fork can skip a step that legitimately doesn't apply to it: `OLIVA_VERIFY_SKIP` locally,
  the `OLIVA_CI_SKIP` repo variable in CI.

👉 **[`docs/qa-y-staging.md`](docs/qa-y-staging.md)** covers all of this in depth, plus the
**staging stack** (prod's build with a throwaway database and seeded data) and what this
framework deliberately does *not* verify.

> Deploying several Oliva apps onto one host with a shared Postgres / RabbitMQ /
> reverse-proxy is supported through the opt-in `docker-compose.shared-infra.yml` overlay.
> The per-app runbook lives in `CLAUDE.md`.

---

## License

MIT
