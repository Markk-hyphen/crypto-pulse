# Oliva

**A webapp starter that keeps improving the apps built on it, and that an agent can operate without anything failing silently.**

Most starter kits are a snapshot: you copy them on day one and they stop helping you on day two. Oliva is versioned like a library. Every app built on it can pull each new release with one guided command, so a security fix or a deploy fix made once in Oliva reaches every app. The whole thing is designed for whoever is actually at the keyboard today, which is often an AI agent, so every mistake that used to be silent now produces a message that names the fix.

It ships with a default stack that is already wired together, passing CI and patched: Symfony on FrankenPHP, Vite, PostgreSQL with pgvector, Mercure, RabbitMQ and a scheduler. The direction is for every one of those pieces to become optional and replaceable (see [Where it's heading](#where-its-heading)).

> **Honest scope.** Oliva is built and maintained by one developer (plus an agent) to run a handful of real apps on shared infrastructure. It solves *that* problem well. It assumes no community and makes no promises beyond what's written here. Some operational docs are in Spanish, the maintainer's language; this README and the roadmap are in English.

---

## What makes it different

### 1. Apps stay current after day one

Each app is its own repo, with a git remote called `oliva-upstream` pointing here. When Oliva ships a version, the app pulls it:

```bash
./oliva sync check    # how far behind am I, plus the upgrade notes I haven't applied
./oliva sync start    # branch + merge Oliva, every conflict classified
./oliva sync locks    # regenerate composer.lock / yarn.lock without dragging the app's own deps
./oliva sync verify   # the full smoke test before merging to main
```

Three things make this hold up over time instead of rotting into a 19-conflict merge:

- **File ownership.** [`scripts/oliva/owned-paths.txt`](scripts/oliva/owned-paths.txt) says which files belong to Oliva (Dockerfiles, compose files, scripts, CI). An app doesn't edit them. If it needs something different, that becomes an option in Oliva and ships to every app. `sync start` tags each conflict `[OLIVA]`, `[LOCK]` or `[MANUAL]`, and reports *drift*: Oliva files the app edited anyway.
- **One channel to every app.** [`docs/oliva/UPGRADING.md`](docs/oliva/UPGRADING.md) holds the per-version notes an app must act on, and `sync check` shows them. `./oliva release` refuses to cut a version without its section.
- **Extension points instead of edits.** The most common reason to touch an owned file (an extra PHP extension) has its own fork-owned file, `backend/php-extensions.txt`, which Oliva never changes.

It's pull, not push: Oliva doesn't know its apps exist and holds no credentials to them. The full system is in [`docs/oliva/actualizaciones.md`](docs/oliva/actualizaciones.md).

### 2. No silent failures, for humans and agents

A failure that makes no noise is treated as a bug in Oliva, not in whoever triggered it. People who build by prompting an agent are included on purpose: the inattention is real and inevitable, and catching it works better than scorning it. In practice the reader is often the agent itself, so the guards live where it acts, in the scripts it runs and in CI, and each message names the fix.

Some of what is loud today:

| Silent before | Loud now |
|---|---|
| A cron job that never runs because the `cron` profile isn't active | the deploy scripts warn when the crontab has jobs and the profile is off |
| A deploy that takes over another app's containers on the same host | the project guard aborts before `down`/`up` |
| Containers of the old stack surviving a deploy | `down` covers every profile (`--profile '*'`) |
| `composer update` silently jumping a major | every constraint must have a ceiling, enforced before each update and in CI |
| A transitive dependency jumping a major | flagged `⇑ MAJOR` in the update summary |
| Rebuilding with a patched PHP while the old binary keeps serving | `verify` fails if the running PHP isn't the pinned one |
| The prod stack not actually running `APP_ENV=prod` | a CI job checks the resolved config |
| A release with nothing telling the apps what changed | `release` refuses without an `UPGRADING.md` section |
| Forgetting that a dependency or security cycle is due | `./oliva doctor` says so every session |

Guards cost nothing when they don't apply: an empty crontab or no PHP extensions means no output at all.

The operating rules travel with the code. [`AGENTS.md`](AGENTS.md) is the open format that Claude Code, Codex, Cursor, Gemini CLI, Copilot, Aider, Zed and others read natively. A one-line `CLAUDE.md` stub imports it. `./oliva` is the single entry point, so docs never depend on script paths, and `./oliva doctor` is the read-only status check an agent runs before touching code.

### 3. Staying patched is the default

Freshness and security run on separate clocks. The dependency cycle (`./oliva deps report` → `deps update`) comes due every ~45 days. A CVE doesn't wait for it: `./oliva deps audit` checks three layers, and `doctor` reminds you once a week has passed.

- **PHP packages:** `composer audit`.
- **JS packages:** `yarn audit`.
- **Inside the base images:** [Trivy](https://trivy.dev/) scans OS packages and binaries, which is where a PHP-runtime or libc CVE lives and the one layer the package audits can't see.

There's one source per layer, never stacked. Trivy is version-pinned and run as a container, not through a floating action tag. Every app runs the same audit, so a CVE means one command per app instead of per-repo archaeology. This tells you a fix is waiting for something you pinned; it's not runtime protection.

### 4. Several apps on one small server

Everything Compose creates is derived from the project name (images, networks, volumes, network aliases), so apps never collide on the same Docker host. Staging is just one more app on the same host, with its own throwaway database and seeded data.

Going further, several apps can share one Postgres, RabbitMQ and reverse proxy instead of each running its own. That's the opt-in `docker-compose.shared-infra.yml` overlay. Today it's built around the maintainer's own server layout (the shared services live in a separate infra repo) and isn't packaged for general use. Making it a self-contained option is on the roadmap. The runbooks are in [`AGENTS.md`](AGENTS.md).

---

## Getting started

### Prerequisites

- [Docker](https://docs.docker.com/get-docker/) with Compose **v2.24+**. v2.10 is enough for the core dev stack, but the shared-infra and staging overlays use the `!override` merge tag. Check with `docker compose version`.

### Start an app on Oliva

```bash
git clone https://github.com/Markk-hyphen/oliva.git my-app
cd my-app
git remote rename origin oliva-upstream     # this is how `oliva sync` finds Oliva
git remote add origin <your-app-repo-url>
cp .env.example .env                        # then fill .env, .env.backend, .env.frontend
docker compose up
./oliva doctor
```

| Service | URL (dev) |
|---|---|
| Frontend | http://localhost:3000 |
| Backend API | http://localhost:80/api |
| Mercure hub | http://localhost/.well-known/mercure |
| RabbitMQ management (`queues` profile) | http://localhost:15672 |
| Database | localhost:5432 |

Hot reload is on: changes to `backend/src` and `frontend/src` show up without rebuilding. The live canvas demo (`backend/public/live.php` + `frontend/src/js/live.js`) shows Mercure working out of the box.

> A one-command `oliva new` with only the pieces you ask for is on the roadmap (item 3). It waits until real use shows what actually varies between apps.

### Production

```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml build
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```

The frontend is served by Caddy on **http://localhost**. Backend, database and RabbitMQ are internal and never reachable from outside. On a server, redeploys are `./oliva deploy` (pull + build + down + up) and `./oliva deploy-staging`.

> **Known gap:** there's no production `worker` service yet. If your app uses Messenger queues for real, add one to `docker-compose.prod.yml` (image `${COMPOSE_PROJECT_NAME}-backend:prod`, command `messenger:consume`, no exposed ports) before going live.

---

## The default stack

These are the pieces Oliva makes robust, and the ones its guards, CI and update cycle know about.

| Layer | Technology |
|---|---|
| Backend | Symfony 7.4 (PHP 8.3) · FrankenPHP · Caddy · JWT auth (Lexik) |
| Frontend | Vite 6 · vanilla JS · Bootstrap 5, served by Caddy |
| Database | PostgreSQL + [pgvector](https://github.com/pgvector/pgvector) |
| Real-time | [Mercure](https://mercure.rocks/) hub, built into the backend's Caddy |
| Queues | RabbitMQ + Symfony Messenger |
| Scheduled tasks | `supercronic` running `backend/scheduler/crontab` |
| Staging / seeding | [Foundry](https://symfony.com/bundles/ZenstruckFoundryBundle/current/index.html) + Doctrine Fixtures · `frankenphp_staging` image stage (the fixtures command doesn't exist in the prod image) |
| API testing | a [Bruno](https://www.usebruno.com/) collection in `api/`, per app (not shipped by Oliva: the requests are 100% domain) |
| Infrastructure | Docker Compose · multi-stage builds (dev / prod / staging) |

```
Browser
  │  HTTP
  ▼
Frontend (Caddy · Vite build)
  │  /api/*                 │  /.well-known/mercure
  ▼                         ▼
Backend (FrankenPHP · Symfony) ── Mercure hub (Caddy)
  │  SQL              │  AMQP
  ▼                    ▼
PostgreSQL          RabbitMQ ── worker / scheduler
  (+ pgvector)
```

The frontend proxies `/api/*` to the backend over the app's private network. In production nothing behind the frontend has a public port.

[`docs/concepts.md`](docs/concepts.md) explains the less obvious pieces (pgvector, AMQP, Mercure, the sync model). `docs/examples/` has reference skeletons of a queue producer/consumer and a Mercure publisher.

### Optional services (Compose profiles)

`backend`, `frontend` and `database` always come up. The rest is behind profiles, switched with `COMPOSE_PROFILES` in `.env` (empty = core only):

| Profile | Adds | You must also set |
|---|---|---|
| _(none)_ | `backend`, `frontend`, `database` | `DATABASE_URL`, `APP_SECRET`, JWT + Mercure keys |
| `queues` | `rabbitmq`, `worker` (dev) | `RABBITMQ_USER`, `RABBITMQ_PASSWORD`, `RABBITMQ_DSN` |
| `cron` | `scheduler` | nothing, but `backend/scheduler/crontab` must have jobs |

```bash
COMPOSE_PROFILES=queues,cron docker compose up -d
```

- **Enabling a profile doesn't configure it.** A missing DSN or key crashes the service at boot, which at least is loud.
- **Forgetting a profile:** the deploy scripts catch it for `cron`. There's no equivalent guard for `queues` yet.
- **Removing a profile from `COMPOSE_PROFILES` doesn't stop a container that's already running.** Use `docker compose stop <service>` or `down`.
- **Adding a new optional service:** give it `profiles: ["<name>"]`, and never let a core service `depends_on` it, or Compose pulls it back up with the profile off. Then add a row above and a line in `.env.example`.

---

## Where it's heading

The through-line of Oliva is one move: **turn what is assumed into what is chosen.** Taken to its end, it has three steps:

1. **A fixed core with optional extras.** This is where Oliva is today. Backend, frontend and database always come up. Queues and the scheduler are opt-in. The database and the broker can already live outside the app (a managed Postgres, say) as long as the connection matches. But every app still ships every piece, even the ones it switched off.
2. **No mandatory services.** An app has only the pieces it asked for.
3. **Every piece optional *and* replaceable.** Every role (gateway, frontend, backend, realtime, database, queue, worker, scheduler) becomes a slot that is either the **default** (what Oliva makes robust), **replaced** (anything that honors the slot's contract) or **absent**.

Oliva will stand behind one robust default per role and won't pretend to make every alternative robust. A replacement is the replacer's responsibility, and Oliva says so out loud: `doctor`, `verify` and CI will name the slot that's outside the net. Profiles can't get there, because they switch off services but still ship their code. The mechanism is install-time scaffolding, and it waits on what real use shows actually varies between apps.

The full reasoning, the slot contracts and the sequencing are in [`docs/roadmap.md`](docs/roadmap.md).

---

## Reference

### `./oliva`

| Command | What it does |
|---|---|
| `doctor` | read-only status: branch, git, containers, migrations, deps/audit due, sync status (in an app) |
| `deps <due\|report\|update\|audit\|scan-images>` | Oliva's maintenance cycle and CVE audit |
| `sync <check\|start\|locks\|verify>` | pull Oliva into an app |
| `verify` | full local smoke test (migrations, schema, PHPUnit, prod build, running PHP version) |
| `release X.Y.Z` | cut an Oliva version (refuses without its `UPGRADING.md` section) |
| `deploy`, `deploy-staging`, `down`, `down-staging` | operate an app on a server |
| `version` | print `OLIVA_VERSION` |

### CI

`.github/workflows/ci.yml` runs on every push and PR, skipping docs-only changes. It has five jobs:

- **Tests:** build the images, bring up the stack, check `/health` and Mercure, run migrations, validate the Doctrine schema, run PHPUnit.
- **Prod config guard:** `APP_ENV` really resolves to `prod`.
- **Composer constraints guard.**
- **Docker lint:** hadolint.
- **Image scan:** Trivy, report-only.

An app can skip a step that legitimately doesn't apply to it, with `OLIVA_VERIFY_SKIP` locally or the `OLIVA_CI_SKIP` repo variable in CI. [`docs/qa-y-staging.md`](docs/qa-y-staging.md) covers what this verifies, the staging stack, and what Oliva deliberately does *not* check.

### Adding PHP extensions

`backend/php-extensions.txt` belongs to the app, one per line. Extensions bundled with PHP go without a version (the base image pins them). PECL extensions get an exact version:

```
bcmath
redis-6.2.0
```

### Environment variables

Copy `.env.example` to `.env`. Per service:

| Variable | Description |
|---|---|
| `COMPOSE_PROFILES` | optional services to bring up (see above) |
| `POSTGRES_USER` / `POSTGRES_PASSWORD` / `POSTGRES_DB` / `POSTGRES_VERSION` | local database |
| `DATABASE_URL` | Doctrine connection. Standalone: in `.env`, matching `POSTGRES_*`. Shared infra: the override in `.env.backend` |
| `APP_ENV` / `APP_SECRET` | Symfony environment (`dev`; prod/staging are set by their overlays) and secret |
| `JWT_PASSPHRASE` | JWT key passphrase (keys are generated on first boot into `secrets/`) |
| `SERVER_NAME` | domain (default `localhost`) |
| `RABBITMQ_USER` / `RABBITMQ_PASSWORD` / `RABBITMQ_DSN` | broker credentials and Messenger DSN |
| `MERCURE_URL` / `MERCURE_PUBLIC_URL` / `CADDY_MERCURE_URL` / `CADDY_MERCURE_PUBLIC_URL` | Mercure hub URLs (internal vs public) |
| `MERCURE_PUBLISHER_JWT_KEY` / `MERCURE_JWT_SECRET` | Mercure JWT keys |

### Project structure

```
oliva/
├── oliva                   # the CLI: ./oliva <command>
├── OLIVA_VERSION
├── AGENTS.md / CLAUDE.md   # operating guide for agents (+ one-line stub)
├── agent-commands.md       # chat commands for the agent
├── backend/                # Symfony app (FrankenPHP + Caddy)
│   ├── src/DataFixtures/   # Foundry fixtures, grouped by env
│   ├── php-extensions.txt  # the app's extra PHP extensions (Oliva ships it empty)
│   ├── scheduler/crontab   # consumed by supercronic
│   └── frankenphp/         # Caddy and PHP runtime config
├── frontend/               # Vite app + production Caddyfile
├── docs/
│   ├── roadmap.md          # where Oliva is heading and why
│   ├── concepts.md         # cumulative glossary
│   ├── qa-y-staging.md     # QA guarantees + staging stack
│   ├── oliva/              # framework docs that ship to every app (sync system, UPGRADING)
│   └── examples/           # reference skeletons (not live code)
├── scripts/
│   ├── oliva/              # deps, sync, verify, release, owned-paths.txt
│   ├── lib/                # project guard, cron guard, docker prune
│   └── deploy*.sh / down*.sh
├── docker-compose.yml               # base
├── docker-compose.override.yml      # dev (auto-applied)
├── docker-compose.prod.yml
├── docker-compose.staging.yml
├── docker-compose.shared-infra.yml  # opt-in: shared Postgres/RabbitMQ/proxy
└── secrets/                # JWT keys, generated at first boot (gitignored)
```

---

## License

MIT
