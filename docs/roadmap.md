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

---

## Sequencing

The items are dependency-ordered, not priority-ordered:

```
1. Friction log  ──►  3. Scaffolding/flags  ──►  2. Full optionality
   (produces the        (the mechanism)           (the goal)
    signal)                   │
                              └──►  4. shared-infra becomes a flag
```

Item 1 is cheap and can start any time. Items 2–4 wait on it.
