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

## Guiding principle: decoupling → full optionality

The through-line of every item below is the same move Oliva has been making
since day one: **turn what is assumed into what is chosen.**

- **Today:** three mandatory services (`backend`, `frontend`, `database`) always
  come up; optional services (`queues`, `cron`) hang behind Compose profiles.
- **Destination:** *no* mandatory services. Oliva becomes a set of coherently
  connected, individually optional pieces — closer to opt-in microservices than
  to a monolith with switches. An app composes only the pieces it needs; nothing
  it didn't ask for is present to turn off.

Profiles were the first step of this (making optional what used to be
mandatory). The rest of the roadmap is the same line, taken further.

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

The output feeds everything below — especially the scaffolding work, which
should not be designed until this signal exists.

## 2. Zero mandatory services / full optionality

The destination described in the guiding principle. Blocked on a prerequisite:
Compose profiles can only toggle *services*, not *code*. A fork with no queues
still ships the `rabbitmq` block, the `worker`, the example migrations. True
optionality can't be reached by adding more profiles — it needs item 3.

## 3. Install-time scaffolding (the "flags" system)

The lever that makes item 2 possible. The distinction is categorical:

- **Profiles = runtime.** All code ships to every fork and is switched off with a
  flag. There is always something present to turn off.
- **Scaffolding = install-time.** The fork is *born* with only what it asked for.
  Nothing to turn off because it was never there.

This is the v2.0 destination the README already names. It resolves the profiles
frustration *and* subsumes shared-infra (see item 4) as just another install
flag.

> **Do not build this yet.** An installer is expensive and will be designed
> wrong if built before item 1 reveals what actually varies between forks.
> Earn the signal first.

## 4. `oliva-shared-infra` as an install option, not a separate repo

Today the shared-infra layer lives in its own repo (`~/infra`): a shared
Postgres + RabbitMQ + reverse-proxy for running several Oliva apps on one host,
with its own IaC lifecycle. That separation is fine for now, but the long-term
shape is **not** a standalone `shared-infra` project, nor a separately
maintained installable module (which would need manual sync). It's a flag of the
installer from item 3: `--shared-infra`. The installer is what unifies it into
Oliva coherently, instead of a module kept in step by hand.

## 5. Agent layer: one entry point, vendor-neutral spec

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

**Not blocked on item 1.** Unlike items 2–4, this needs no friction signal: it
changes the entry point and the naming, not what Oliva ships. It is also the
socket item 3 plugs into — an installer is `oliva new --queues --shared-infra`,
which needs the dispatcher to exist first.

**Deliberately out of scope:** flags on `oliva deploy`. Those *are* item 3, and
they wait on item 1 like everything else. The operational commands ship as thin
pass-throughs with no new flags.

Plan and decisions: [`docs/roadmap/epics/E-capa-agentica.md`](roadmap/epics/E-capa-agentica.md)
(target v1.4.0).

## 6. Replaceable backend: one first-class backend, the rest by contract

The same "assumed → chosen" move, applied to the backend itself. Oliva's backend
is Symfony on FrankenPHP and **stays that way**: it is the one backend Oliva
makes robust. What changes is that it becomes *replaceable*. A fork can plug
in a backend built on another stack (one API, several services, whatever it
needs) without forking Oliva's tooling to do it.

**Why only one first-class backend.** Most of Oliva's robustness is PHP-specific.
The safety net from the guiding principle (`deps.sh`, `sync.sh locks`, the
unbound-constraints guard, `verify.sh`'s php-version/schema/phpunit steps, the CI
jobs, `php-extensions.txt`) assumes composer, PHP and Doctrine. Giving another
stack the same net means duplicating every guard and keeping them all alive
through every deps cycle, CVE audit and sync rehearsal. One maintainer can't do
that honestly, and a guard written without real command of the stack it guards
is worse than none: it suggests a protection that isn't there.

**The split:**

- **First-class backend (Symfony/FrankenPHP).** The full net, as today.
- **Replacement backend.** Oliva guarantees only a **written contract** and
  everything outside the backend: routing, infra, deploy, shared-infra.
  Whatever happens inside the backend (deps, tests, schema, seeding safety) is
  the responsibility of whoever replaces it. That includes the cost/risk
  trade-off of leaving the first-class path.

**The replacement must be loud, not silent.** Swapping the backend can't look
like being covered. `doctor`, `verify` and CI have to say explicitly that the
backend is outside Oliva's net and which checks don't run. That is the
no-silent-failures principle applied to Oliva's own limits.

**The door for contributors.** If Oliva ever opens up, someone who knows another
stack well can contribute its guards and become its maintainer. A replacement
backend becomes first-class when someone owns its net, not before.

**What the contract has to cover.** These are coupling points that today are
implicit, all assumed to be PHP:

- **Network:** HTTP on `:80` (no TLS), routes under `/api`, a real `GET /health`
  (the dev healthcheck is `kill -0 1`), respects `X-Forwarded-For` from the
  frontend's trusted proxy (login throttling depends on it).
- **Realtime: Mercure lives inside FrankenPHP** (a directive in
  `backend/frankenphp/Caddyfile`). Replacing the backend silently loses
  realtime. Extracting the hub into its own service (`realtime` profile)
  belongs to this item and reverses the decision recorded in
  `oliva-upgrade-optional-services.md`. After that, publishing is just an HTTP
  POST with a JWT, which works from any stack. *Not now:* it happens when this
  item is worked on.
- **DB lifecycle:** wait-for-db, migrations on boot and JWT key generation all
  live in the PHP entrypoint (`bin/console`). The contract needs a `migrate`
  hook, and a `DATABASE_URL` without Doctrine-only params (`serverVersion=…`,
  as printed by `provision-postgres.sh`).
- **Staging seeding:** `deploy-staging.sh` calls `doctrine:fixtures:load`, and
  the "can't seed prod" guard is structural (`--no-dev` removes the command).
  A replacement needs a `seed` hook *and* an equally structural guard.
- **`scheduler` / `worker`:** both build from `./backend` and assume
  `bin/console` / Messenger. In the contract they become "your image, your
  command", or they don't exist.
- **Sync:** `owned-paths.txt` owns `backend/Dockerfile` and `backend/frankenphp/`.
  A fork with another backend would keep receiving FrankenPHP changes it can't
  use. `sync.sh` has to know the fork's backend kind.
- **Demo leftovers:** `/live.php` is hardwired into the frontend Caddyfile and
  the Vite proxy.

**Dependencies.** The clean version needs item 3: a fork *born* with
`--backend=<kind>` has no PHP files to sync and no PHP guards to skip. The
contract itself can be written earlier, and the first probe is item 1's method
applied here: bootstrap a throwaway fork with a minimal non-PHP backend and log
every place that breaks, or worse, doesn't.

---

## Sequencing

The items are dependency-ordered, not priority-ordered:

```
1. Friction log  ──►  3. Scaffolding/flags  ──►  2. Full optionality
   (produces the        (the mechanism)           (the goal)
    signal)                ▲   │
                           │   ├──►  4. shared-infra becomes a flag
                           │   │
5. Agent layer  ───────────┘   └──►  6. Replaceable backend
   (CLI + AGENTS.md)                 (--backend=<kind>; contract + Mercure
                                      extraction can start earlier)
```

Item 1 is cheap and can start any time. Items 2–4 wait on it. Item 5 doesn't —
it's independent of the friction signal, and it builds the entry point that
item 3 later extends. Item 6 needs item 3 for its clean form, but its contract
and its first probe (a throwaway fork with a non-PHP backend) are item-1 work.
