# Roadmap

Direction, not a release schedule. Oliva is built by one developer (plus an
agent), so this is a statement of *where it's heading and why* — not a backlog
with dates. Items move when the work that justifies them appears, not before.

Honest scope up front: Oliva solves **its own problem well** — running a handful
of decoupled apps on shared infrastructure, maintained by one person. It is not
trying to be the next general-purpose framework, and nothing here assumes a
community or a market. If it ever becomes more than that, it'll be by accident,
on top of decisions that were already sound.

---

## Guiding principle: assumed → chosen, all the way down

The through-line of every item below is the same move Oliva has been making
since day one: **turn what is assumed into what is chosen.** Taken to its end,
that move has three steps:

1. **Some services optional, some infra external.** *(Today.)* `backend`,
   `frontend` and `database` always come up; `queues` and `cron` hang behind
   Compose profiles; shared-infra swaps the local Postgres/RabbitMQ for shared
   ones on the same host.
2. **No mandatory services.** An app composes only the pieces it needs, and
   nothing it didn't ask for is present to turn off.
3. **Every piece optional *and* replaceable.** Any role can be filled by
   something other than Oliva's implementation. Oliva keeps offering, and
   encouraging, the one it has made robust.

Steps 2 and 3 are the same idea. "Optional" means *replaced by nothing*;
shared-infra was already *replaced by something external*. So every role in an
Oliva app is a **slot**, and every slot is in one of three states:

| State | What it means | Who answers for it |
|---|---|---|
| **Default** | Oliva's own implementation | Oliva, with its full safety net |
| **Replaced** | Something else that honors the slot's contract | Whoever replaced it, and Oliva says so out loud |
| **Absent** | The app doesn't need the role | Nobody, at zero cost |

The destination is closer to opt-in services than to a monolith with switches.
It is still not a neutral menu, though: the default is the path Oliva stands
behind (item 2).

---

## Guiding principle: no silent failures — catch, don't scorn

Oliva is meant to be safe for whoever is at the keyboard, including people who
build by prompting an agent and don't yet have the mental model to suspect what
*doesn't* fail. Most of the industry answers that with contempt. Oliva's stance is
the opposite: the inattention is real and inevitable, and catching it serves
better than attacking it. Vibe coders are included here on purpose.

What that means in practice is a design rule, not a feature list:

- **A failure that makes no noise is a bug in Oliva**, not in whoever triggered
  it. A scheduler that never starts, a container that outlives its deploy, a
  dependency that silently jumps a major or silently stays behind: none of these
  raised an error before 1.4.2, and every one of them is now loud.
- **The warning has to reach the agent.** In practice the "vibe coder" at the
  keyboard *is* an agent reading `AGENTS.md` and script output. That is the
  reader that never scrolls past a line, so guards live where the agent acts:
  in the scripts it runs and in CI, with a message that names the fix.
- **Loud locally, blocking in CI where possible.** A warning protects only
  someone who reads it. A red CI protects everyone.
- **Zero cost when it doesn't apply.** Oliva still has to serve a simple app. A
  guard for a feature the app doesn't use (an empty crontab, no PHP extensions)
  must do nothing at all.

This doesn't replace care: the serious failures still get caught by someone
reading every line and asking for a hard recheck at the sensitive points. It is
the net underneath, for the times nobody is looking.

---

## 1. Friction-driven optimization

Stop guessing at weak points; find them by use. The method: **bootstrap a fresh
fork and record every friction** — each manual step, each `UPGRADING.md` note
applied by hand, each "just this once" edit to an `owned-path`, each service
brought up but never used. That log *is* the optimization backlog, prioritized
by real pain instead of intuition.

Axes to watch while doing it:

- **Temporal** — steps that take longer than they should; anything repeated on
  every fork.
- **Spatial** — services/images/code shipped and never used by a given fork.
- **Security** — not by eye: `scripts/oliva/deps.sh audit` (composer + yarn
  audit + Trivy) as the baseline; `/security-review` for what audit can't cover
  (authz, port exposure, JWT/secret handling).

> **Decision note — Snyk: no por ahora (low priority).** Evaluado 2026-10-24.
> El stack OSS actual (`composer audit` + `yarn audit` + Trivy sobre imágenes
> base + la capa php.net para el runtime) cubre deps + SO + runtime para la
> escala de hoy, así que Snyk no entra todavía. Dos razones de fondo:
> (1) el gap que motivó mirar — el runtime de PHP — es por el build estático de
> FrankenPHP, que Snyk Container probablemente *tampoco* detecte, así que no
> reemplaza la capa php.net; (2) Snyk es SaaS (manifests a su nube + token en
> CI), fricción nueva contraria al norte autocontenido de Oliva, y su free tier
> limita tests/mes.
> **Dónde rendiría SAST (código, no deps):** en los **forks**, que es donde vive
> la lógica de dominio escrita a mano — Oliva se queda flaco por diseño, así que
> auditar su propio código rinde poco. SCA (CVEs de deps) aplica a ambos pero ya
> está cubierto.
> **Cuándo reconsiderar:** (a) querer SAST real sobre los forks, o (b) tantos
> forks que un dashboard gestionado cross-repo ahorre tiempo. Antes que Snyk,
> mirar **Dependabot** (gratis, sin SaaS de terceros; alerting temprano de deps).
> **Cómo integrarlo si llega el día:** a Oliva (scripts/CI + `owned-paths.txt`),
> para que baje por `sync.sh` a cada fork — igual que `deps.sh audit`; lo único
> per-repo es la cuenta/token en el CI de cada uno.

The output feeds everything below — especially the scaffolding work, which
should not be designed until this signal exists.

## 2. Composable services: every role optional and replaceable

The destination from the first guiding principle, made concrete.

### One robust default per role, the rest by contract

Oliva makes **one** implementation of each role robust and stands behind it. It
does not try to make every alternative robust. Most of the safety net is
specific to the default stack. `deps.sh`, `sync.sh locks`, the
unbound-constraints guard, `verify.sh`'s php-version/schema/phpunit steps, the
CI jobs and `php-extensions.txt` all assume composer, PHP and Doctrine. Giving
another stack the same net means duplicating every guard and keeping them alive
through every deps cycle, CVE audit and sync rehearsal. One maintainer can't do
that honestly. A guard written without real command of the stack it guards is
worse than none, because it suggests a protection that isn't there.

So for a **replaced** slot, Oliva guarantees the slot's contract and everything
*around* it: routing, infra, deploy. What happens *inside* the replacement
(deps, tests, schema, seeding safety), and the cost/risk trade-off of leaving
the default, belong to whoever replaced it.

**Encouraged structurally, not rhetorically.** The default asks for nothing: no
flag, no config. A replacement has to be declared. The easy path is always the
robust one, and leaving it is a deliberate act.

**Replaced must be loud. Absent must be silent.** A replaced slot can't look
covered: `doctor`, `verify` and CI say which slot is outside the net and which
checks don't run for it. That is the no-silent-failures principle applied to
Oliva's own limits. An absent slot costs nothing and prints nothing.

**The door for contributors.** If Oliva ever opens up, someone who knows another
stack well can contribute its guards and maintain them. An alternative becomes a
second default when someone owns its net, not before.

### The slots

| Role | Default | Contract | Kind | Today |
|---|---|---|---|---|
| Edge / gateway | Caddy, inside `frontend` | routes `/api`, `/health` and realtime to their slots; security headers, CSP | independent | bundled into `frontend`; duplicated by the Vite proxy in dev |
| Frontend | Vite build, served by Caddy | static assets behind the gateway, same-origin API | independent | bundled with the gateway |
| Backend / API | Symfony on FrankenPHP | HTTP `:80`, `/api`, a real `GET /health`, `migrate` and `seed` hooks | anchor | carries the realtime hub and the DB lifecycle |
| Realtime | Mercure hub | HTTP publish with a JWT, SSE subscribe | independent | embedded in the backend |
| Database | Postgres + pgvector | `DATABASE_URL`, Postgres ≥ 15 with `vector` | backend-tied | always on locally; external via shared-infra |
| Queue | RabbitMQ (`queues`) | AMQP DSN | backend-tied | optional; external via shared-infra |
| Worker | Messenger consumer | an image and a long-running command | backend-tied | dev only, no prod definition |
| Scheduler | supercronic (`cron`) | runs commands on a schedule | backend-tied | optional; built from the backend image |

**Two kinds of replacement.** An *independent* slot can be swapped and no other
slot notices, as long as the contract holds over HTTP or SSE. A *backend-tied*
slot is spoken to by the backend's own code (Doctrine, Messenger), so its
contract is written in terms of what the default backend speaks. A managed
Postgres is a clean swap; shared-infra already does it. MySQL, or Redis instead
of RabbitMQ, also means changing the backend, and that is part of the cost the
replacer takes on.

### Shared-infra: the first replacement, already shipped

The shared-infra layer (`~/infra`: shared Postgres + RabbitMQ + reverse proxy
for several Oliva apps on one host) is this item already working. It replaces
two backend-tied slots with external ones that honor the same contract. Its
long-term shape is **not** a standalone project, nor a separately maintained
module (which would need manual sync). It's an install flag, `--shared-infra`
(item 3).

### First: unbundle the roles

A role that lives inside another container can't be replaced on its own, and
today three containers carry more than one role:

- **`frontend` is also the gateway.** Replacing the frontend (say, with Next.js)
  silently drops the routing to the backend and the security headers.
- **`backend` is also the realtime hub** (a `mercure` directive in
  `backend/frankenphp/Caddyfile`), and it runs the DB lifecycle (wait-for-db,
  migrations on boot, JWT key generation) from a PHP entrypoint.
  Replacing the backend silently drops realtime. Extracting the hub (`realtime`
  profile) reverses the decision recorded in
  `oliva-upgrade-optional-services.md`. Publishing then becomes an HTTP POST
  with a JWT, which works from any stack. *Not now:* it happens as part of this
  item.
- **`scheduler` and `worker`** build from `./backend` and assume `bin/console`
  and Messenger.

Separating these is a precondition, and it's worth doing even for forks that
never replace anything: each piece becomes individually optional too.

### The backend: the hardest slot

Beyond the unbundling, these coupling points are implicit today and the
contract has to make them explicit:

- **Network:** HTTP on `:80` (no TLS), and a real health check (the dev
  healthcheck is `kill -0 1`). It has to respect `X-Forwarded-For` from the
  gateway's trusted proxy, because login throttling depends on it.
- **`DATABASE_URL`** without Doctrine-only params (`serverVersion=…`, as printed
  by `provision-postgres.sh`).
- **Staging seeding:** `deploy-staging.sh` calls `doctrine:fixtures:load`, and
  the "can't seed prod" guard is structural (`--no-dev` removes the command). A
  replacement needs a `seed` hook *and* an equally structural guard.
- **Sync:** `owned-paths.txt` owns `backend/Dockerfile` and `backend/frankenphp/`.
  A fork with another backend would keep receiving FrankenPHP changes it can't
  use, so `sync.sh` has to know which slots a fork replaced.
- **Demo leftovers:** `/live.php` is wired into the frontend Caddyfile and the
  Vite proxy.

### Why it waits on item 3

Compose profiles can only toggle *services*, not *code*. A fork with no queues
still ships the `rabbitmq` block, the `worker` and the example migrations. A
fork with its own backend still ships, and syncs, FrankenPHP. Absent and
replaced slots only become clean when a fork is *born* with what it chose
(`--queues`, `--backend=<kind>`, `--shared-infra`), so there's no default code
left to sync or guards to skip.

What can start earlier, as item-1 work: writing the contracts down, and probing
them. Bootstrap a throwaway fork that replaces a slot (a minimal non-PHP
backend, a different frontend) and log every place that breaks, or worse,
doesn't.

## 3. Install-time scaffolding (the "flags" system)

The lever that makes item 2 possible. The distinction is categorical:

- **Profiles = runtime.** All code ships to every fork and is switched off with a
  flag. There is always something present to turn off.
- **Scaffolding = install-time.** The fork is *born* with only what it asked for.
  Nothing to turn off because it was never there.

This is the v2.0 destination the README already names. Every slot state from
item 2 becomes a choice made here: default by omission, absent or replaced by
flag. Shared-infra is just one more flag.

> **Do not build this yet.** An installer is expensive and will be designed
> wrong if built before item 1 reveals what actually varies between forks.
> Earn the signal first.

## 4. Agent layer: one entry point, vendor-neutral spec

Two changes to how Oliva presents itself to whoever operates it — human or agent.

**An executable CLI (`./oliva`).** Today the interface *is* script paths:
`scripts/oliva/deps.sh due`, `scripts/deploy.sh`. The cost isn't typing, it's
structural. The agent doc is a SHARED file, so every doc reference to a path
means that moving, splitting or renaming a script becomes a diff in a file every
fork also edits — conflict surface in all of them. A stable `oliva <verb>` is an
indirection layer: the internals can move without touching a line of the shared
docs. Same reasoning that already justifies `owned-paths.txt`.

**`AGENTS.md` instead of `CLAUDE.md`.** The content is vendor-agnostic —
runbooks, conventions, protocols — and only the filename names a vendor.
`AGENTS.md` is the open format for exactly this, stewarded by the Agentic AI
Foundation, and read natively by Codex, Cursor, Gemini CLI, Copilot, Aider, Zed
and others, Claude Code included. Whoever forks Oliva should be able to bring
their own tool without renaming anything.

**Not blocked on item 1.** Unlike items 2–3, this needs no friction signal: it
changes the entry point and the naming, not what Oliva ships. It is also the
socket item 3 plugs into — an installer is `oliva new --queues --shared-infra`,
which needs the dispatcher to exist first.

**Deliberately out of scope:** flags on `oliva deploy`. Those *are* item 3, and
they wait on item 1 like everything else. The operational commands ship as thin
pass-throughs with no new flags.

Plan and decisions: [`docs/roadmap/epics/E-capa-agentica.md`](roadmap/epics/E-capa-agentica.md)
(shipped in v1.4.0).

---

## Sequencing

The items are dependency-ordered, not priority-ordered:

```
1. Friction log  ──►  3. Scaffolding/flags  ──►  2. Composable services
   (produces the        (the mechanism)           (the goal: every slot
    signal)                ▲                       default, replaced or absent)
                           │
4. Agent layer  ───────────┘
   (CLI + AGENTS.md)
```

Item 1 is cheap and can start any time, and so can item 2's groundwork:
unbundling roles, writing the contracts, probing them with a throwaway fork.
Item 2's clean form waits on item 3, which waits on item 1's signal. Item 4 is
already shipped: it built the entry point that item 3 later extends.
