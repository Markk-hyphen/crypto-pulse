# Runbook — separar Crypto Pulse de Oliva (y cerrar Oliva 1.1.0)

> **Para quién:** un agente (Sonnet alcanza) que ejecuta pasos mecánicos. El análisis y las
> decisiones ya están tomados (sesión Opus del 2026-10-21). **No rediseñar:** si algo no coincide
> con lo que dice este doc, PARAR y avisarle a Marcos con el comando y la salida exacta.
>
> **Desde dónde:** abrir la sesión en **`/home/marcos`** (no en `~/app`: la fase 7 lo renombra).
> Todos los comandos usan rutas absolutas.
>
> **Gates 🛑:** los pasos marcados 🛑 piden el OK explícito de Marcos antes de ejecutarse
> (publican algo o borran algo). Pedirlos todos juntos al empezar está bien; ejecutarlos sin OK, no.

## Decisiones ya tomadas (no preguntar de nuevo)

| Tema | Decisión |
|---|---|
| Repo nuevo | `Markk-hyphen/crypto-pulse`, **público**, con la historia completa de la rama (sin reescribir) |
| Directorio local | `~/crypto-pulse` (en el VPS, cuando se deploye: `~/crypto`, que da `-p crypto`) |
| Oliva | `~/app` pasa a **`~/oliva`**; su memoria a `-home-marcos-oliva` |
| Datos de dev de CMP | se **copian** (`app_db_data` → `crypto-pulse_db_data`). RabbitMQ NO: su nodo depende del hostname del container, los datos no se reusan; los items `pending` los re-encola `app:enrich:requeue-pending` |
| Syncs con Oliva | merge, nunca rebase. No se registran en `agent-commits.md` |

## Estado de partida (verificado al escribir esto)

- `~/app` en rama `release/plan-market-pulse`; su historia incluye `c076e57` (merge del sync con Oliva 1.1.0) y este runbook (`150e23b`). Untracked: `PROMPT-STUDY-GUIDE-AND-LOOKING-FOR-WEAKPOINTS.md` (de Marcos, va a crypto-pulse).
- `main` local = Oliva 1.1.0 (`fdcb360`, tag `v1.1.0`), **sin pushear** (origin/main está en `372515c`).
- Puede existir un worktree de `main` en `/tmp/claude-1000/...scratchpad/oliva` (la sesión Opus lo usó): se limpia en la fase 7.
- Stack dev de finanzas-ong **corriendo** (ocupa `:80`). Containers `app-*` de CMP **parados**.
- Imágenes de plan B ya taggeadas: `crypto-pulse-backend:dev` (imagen vieja de CMP, mismo `composer.lock`) y `finanzas-ong-backend:dev` (= `app-backend-dev:1.0` actual, con bcmath).
- Memoria de crypto-pulse ya escrita en `/home/marcos/.claude/projects/-home-marcos-crypto-pulse/memory/`.

---

## Fase 0 — Chequeos (solo lectura)

```bash
git -C /home/marcos/app branch --show-current        # release/plan-market-pulse
git -C /home/marcos/app status -s                    # solo: ?? PROMPT-STUDY-GUIDE-AND-LOOKING-FOR-WEAKPOINTS.md
git -C /home/marcos/app merge-base --is-ancestor 150e23b HEAD && echo OK   # OK (incluye el runbook)
git -C /home/marcos/app rev-parse --short main v1.1.0^{}   # fdcb360 fdcb360
git -C /home/marcos/finanzas-ong status -s           # vacío
gh auth status                                       # logueado como Markk-hyphen, scope repo
docker images --format '{{.Repository}}:{{.Tag}}' | grep -E 'crypto-pulse-backend:dev|finanzas-ong-backend:dev'   # las 2
for p in apcu-5.1.28 amqp-2.2.0 xdebug-3.5.3; do curl -s -o /dev/null -w "$p %{http_code}\n" https://pecl.php.net/get/$p.tgz; done
```

El último comando dice si **pecl.php.net** responde (200). Si da 5xx, los builds de backend van a
fallar y se usa el plan B de cada fase. No es un error del runbook.

Pedir a Marcos los OK de los gates 🛑 1.1, 2.1, 4.1, 6.4, 7.5 y 9.2 (se pueden pedir juntos).

## Fase 1 — Publicar Oliva 1.1.0

1.1 🛑 Push de `main` y el tag:
```bash
git -C /home/marcos/app push origin main v1.1.0
git -C /home/marcos/app ls-remote origin refs/heads/main refs/tags/v1.1.0   # main → fdcb360…
```
El CI de Oliva corre con este push. Si falla en `install-php-extensions` con 5xx de pecl, es
externo: `gh run rerun --failed -R Markk-hyphen/oliva <id>` más tarde. Cualquier otro fallo: PARAR.

## Fase 2 — Crear `crypto-pulse`

2.1 🛑 Crear el repo público y apagar el paso de schema en su CI **antes** del primer push
(`schema:validate` está en rojo a propósito por el drift de pgvector):
```bash
gh repo create Markk-hyphen/crypto-pulse --public \
  --description "Crypto market intelligence in real time — ingest, AI enrichment, live dashboard. Built on Oliva."
gh variable set OLIVA_CI_SKIP --body schema -R Markk-hyphen/crypto-pulse
```

2.2 Clonar la rama con su historia y dejar los remotes como finanzas-ong:
```bash
git clone --branch release/plan-market-pulse --single-branch /home/marcos/app /home/marcos/crypto-pulse
cd /home/marcos/crypto-pulse
git branch -m release/plan-market-pulse main
git remote remove origin
git remote add origin https://github.com/Markk-hyphen/crypto-pulse.git
git remote add oliva-upstream https://github.com/Markk-hyphen/oliva.git
git fetch -q oliva-upstream
git remote -v                                   # origin = crypto-pulse, oliva-upstream = oliva; SIN tokens en la URL
```

2.3 Push (credenciales de `gh` solo para este comando; no toca la config global):
```bash
git -C /home/marcos/crypto-pulse -c credential.helper= -c 'credential.helper=!gh auth git-credential' push -u origin main
git -C /home/marcos/crypto-pulse ls-remote origin main      # mismo hash que: git -C /home/marcos/crypto-pulse rev-parse main
```
No pushear tags (`v1.0`/`v1.1.0` son de Oliva).

2.4 Chequear el CI del primer push: `gh run list -R Markk-hyphen/crypto-pulse --limit 1`. Esperado:
verde, con "Doctrine Schema Validator" *skipped*. Si falla por pecl 5xx: rerun más tarde, seguir.

## Fase 3 — Archivos locales que git no lleva

```bash
cd /home/marcos/app
cp -a .env rules-claude.md /home/marcos/crypto-pulse/
cp -a frontend/.env /home/marcos/crypto-pulse/frontend/
mkdir -p /home/marcos/crypto-pulse/.claude /home/marcos/crypto-pulse/backend/config/jwt
cp -a .claude/settings.local.json /home/marcos/crypto-pulse/.claude/
cp -a backend/config/jwt/. /home/marcos/crypto-pulse/backend/config/jwt/
mv PROMPT-STUDY-GUIDE-AND-LOOKING-FOR-WEAKPOINTS.md /home/marcos/crypto-pulse/
grep COMPOSE_PROFILES /home/marcos/crypto-pulse/.env      # COMPOSE_PROFILES=queues,cron
git -C /home/marcos/crypto-pulse status -s               # vacío (todo eso está gitignoreado), salvo el PROMPT-… untracked
```
`secrets/` de `~/app` es de root y está vacío de claves de dev: no se copia. `.idea/` no se copia
(Marcos abre `~/crypto-pulse` como proyecto nuevo en el IDE).

## Fase 4 — Datos de dev

4.1 🛑 Bajar el stack dev de finanzas-ong para liberar `:80` (solo `stop`: no borra nada):
```bash
cd /home/marcos/finanzas-ong && docker compose ps --format '{{.Service}}' && docker compose --profile cron stop
```
(Anotar los servicios que estaban arriba: se vuelven a levantar en la fase 8.4.)

4.2 Sacar los containers viejos de CMP (estaban parados) y crear el volumen nuevo vacío:
```bash
docker rm app-frontend-1 app-backend-1 app-worker-1 app-scheduler-1 app-database-1 app-rabbitmq-1
cd /home/marcos/crypto-pulse && docker compose up --no-start database
docker volume inspect crypto-pulse_db_data --format '{{.Name}}'          # existe
docker run --rm -v crypto-pulse_db_data:/v alpine sh -c 'ls -A /v | wc -l'   # 0 (vacío)
```
Si no está vacío: PARAR (algo ya escribió ahí).

4.3 Copiar (mismo Postgres 15 en los dos lados, `cp -a` conserva el dueño uid 999):
```bash
docker run --rm -v app_db_data:/from:ro -v crypto-pulse_db_data:/to alpine sh -c 'cp -a /from/. /to/'
docker run --rm -v app_db_data:/a:ro -v crypto-pulse_db_data:/b:ro alpine sh -c 'du -s /a /b'   # mismos tamaños
```

## Fase 5 — Levantar CMP desde `~/crypto-pulse`

5.1 Build. El frontend no depende de pecl; el backend sí:
```bash
cd /home/marcos/crypto-pulse
docker compose build frontend
docker compose build backend || echo "BACKEND BUILD FALLÓ"
```
Si el backend falló con `pecl.php.net … 500/504` → **plan B**: seguir; `crypto-pulse-backend:dev`
ya existe (imagen vieja de CMP con el mismo `composer.lock`). Si falló por cualquier otra cosa: PARAR.

5.2 Arriba y chequeos:
```bash
docker compose up -d --wait
docker compose ps                                     # backend, frontend, database, rabbitmq, worker, scheduler: healthy/running
docker compose exec -T backend bin/console doctrine:migrations:status | grep -E "New|Executed"   # New: 0
docker compose exec -T database psql -U app -d app -tAc "select count(*) from news_item; select count(*) from enrichment;"
```
Esperado: `news_item` ≥ 276 y `enrichment` ≥ 169 (los datos copiados; pueden ser más si el
pipeline ya corrió). Si da 0: la copia de la fase 4 no tomó → PARAR.
Si el usuario/DB de `psql` no es `app`, leerlos de `POSTGRES_USER`/`POSTGRES_DB` en `.env`.

5.3 Smoke completo y dashboard:
```bash
OLIVA_VERIFY_SKIP="up schema prod-build" scripts/oliva/verify.sh     # health, mercure, migrations, phpunit: PASS
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:3000/pulse.html   # 200
scripts/oliva/sync.sh check                                           # "oliva: al día (Oliva 1.1.0)."
```
(`prod-build` se saltea porque depende de pecl; si pecl responde, correrlo sin saltearlo.)

## Fase 6 — Oliva queda limpia

6.1 Volver `~/app` a `main` y darle un `.env` propio de Oliva (el que tenía era el de CMP, ya copiado):
```bash
cd /home/marcos/app
git switch main
git status -s                                         # vacío
cp .env.example .env
sed -i 's/your_db_password/app/g; s/your_rabbitmq_password/app/g' .env
```
(`rules-claude.md` y `.claude/settings.local.json` quedan en `~/app`: son gitignoreados, sobreviven al
cambio de rama y Oliva usa la misma regla estándar.)

6.2 Borrar la rama local (su contenido ya está en crypto-pulse; comprobarlo primero):
```bash
test "$(git -C /home/marcos/app rev-parse release/plan-market-pulse)" = "$(git -C /home/marcos/crypto-pulse rev-parse origin/main)" && echo IGUALES
git -C /home/marcos/app branch -D release/plan-market-pulse      # solo si dijo IGUALES
```

6.3 Limpiar el worktree que dejó la sesión Opus (si existe):
```bash
git -C /home/marcos/app worktree list
git -C /home/marcos/app worktree prune
git -C /home/marcos/app worktree list      # solo /home/marcos/app [main]; si sigue otro: git worktree remove --force <path>
```

6.4 🛑 Borrar la rama remota del repo de Oliva (el código queda en crypto-pulse con toda su historia):
```bash
git -C /home/marcos/app push origin --delete release/plan-market-pulse
```

## Fase 7 — Renombrar `~/app` → `~/oliva`

7.1 Precondición: ningún proceso usando `~/app` (IDE cerrado en ese proyecto, ninguna otra sesión de Claude ahí).
```bash
lsof +D /home/marcos/app 2>/dev/null | head     # vacío (si lsof no existe, preguntar a Marcos)
```
7.2 Containers del proyecto `app` (no debería haber; si hay, bajarlos desde `~/app` con `docker compose down` antes de mover):
```bash
docker ps -a --filter label=com.docker.compose.project=app --format '{{.Names}}'   # vacío
```
7.3 Mover repo y memoria:
```bash
mv /home/marcos/app /home/marcos/oliva
mv /home/marcos/.claude/projects/-home-marcos-app /home/marcos/.claude/projects/-home-marcos-oliva
git -C /home/marcos/oliva status -s && git -C /home/marcos/oliva log --oneline -1   # limpio, fdcb360
```
7.4 Actualizar la memoria de Oliva (`/home/marcos/.claude/projects/-home-marcos-oliva/memory/`):
- `oliva_state.md`: reemplazar la sección "⭐ RETOMAR ACÁ" por una línea "Separación de CMP y
  Oliva 1.1.0: DONE <fecha>" y dejar como próximo paso **el primer ciclo `claude oliva deps`**
  (la sección "Después de la separación" ya lo describe). Cambiar `~/app` por `~/oliva` donde diga
  "pasa a".
- `MEMORY.md`: actualizar la línea de Oliva state (sin "EN VUELO") y la de finanzas si la fase 8 se hizo.
- `crypto_pulse_pointer.md`: borrar la frase sobre "mientras la separación no se haya ejecutado".

7.5 🛑 Volúmenes viejos del proyecto `app` (el de DB tiene la copia de origen de los datos de CMP;
recomendado borrarlos recién cuando Marcos haya usado crypto-pulse un par de días):
```bash
docker volume rm app_db_data app_rabbitmq_data app_frontend_caddy_data app_frontend_caddy_config
```

## Fase 8 — Sync de finanzas-ong a Oliva 1.1.0

finanzas-ong tiene commits locales sin pushear **a propósito**: no pushear nada en esta fase.
Probado en un clon descartable el 2026-10-21: salen exactamente estos 6 conflictos.

8.1 Arrancar (este primer sync usa los scripts de Oliva desde `~/oliva`, porque finanzas todavía no los tiene):
```bash
cd /home/marcos/finanzas-ong
git status -s                                   # vacío
git fetch -q oliva-upstream
/home/marcos/oliva/scripts/oliva/sync.sh start
```
8.2 Resolver **exactamente así**:

| Archivo | Resolución |
|---|---|
| `backend/Dockerfile` | finanzas agregó **`bcmath`** (el triage lo muestra con `+ bcmath`). Primero: `printf 'bcmath\n' >> backend/php-extensions.txt` (el archivo llega con el merge, con comentarios). Después: `git checkout --theirs -- backend/Dockerfile`. Verificar: `grep -c bcmath backend/Dockerfile` → 0 y `grep -x bcmath backend/php-extensions.txt` → bcmath |
| `backend/frankenphp/Caddyfile` | `git checkout --theirs -- backend/frankenphp/Caddyfile` (mismo fix de Mercure, otra posición). Verificar: `grep -c protocol_version_compatibility backend/frankenphp/Caddyfile` → **1** (con el merge a mano quedaba duplicado) |
| `docker-compose.staging.yml` | `git checkout --theirs -- docker-compose.staging.yml` (solo cambian nombres de imagen y comentarios) |
| `claude-commands.md` | `git checkout --theirs -- claude-commands.md` (trae el `-f` y la ruta de memoria genérica; mismo protocolo) |
| `agent-commits.md` | `git checkout --ours -- agent-commits.md` (el triage lo marca `[FORK]`: es el log de finanzas, el de Oliva no se mezcla) |
| `README.md` | combinar: dejar el bloque de Oliva (frontend servido por Caddy + "Known gap" del worker) y **debajo** la línea de finanzas sobre infra compartida. Sacar los marcadores |

Alinear además dos archivos de Oliva que finanzas tiene con comentarios distintos (drift sin
cambios de código; confirmado):
```bash
git checkout MERGE_HEAD -- docker-compose.shared-infra.yml scripts/deploy-staging.sh
```
8.3 Locks, chequeos y commit:
```bash
/home/marcos/oliva/scripts/oliva/sync.sh locks          # composer: sin cambios; yarn: genera frontend/yarn.lock
grep -n "yarn.lock" .gitignore                          # no debe aparecer frontend/yarn.lock
git grep -n -e '^<<<<<<< ' -e '^>>>>>>> '              # vacío (después del git add -A de abajo también)
git add -A && git commit --no-edit
cat OLIVA_VERSION                                       # 1.1.0
```
8.4 Stack dev con los nombres nuevos (la red pasa de `app_network` a `finanzas-ong_app_network`):
```bash
docker compose down                                     # sin -v: los volúmenes finanzas-ong_* no cambian de nombre
docker compose build frontend
docker compose build backend || echo "BACKEND BUILD FALLÓ"   # pecl 5xx → plan B: finanzas-ong-backend:dev ya existe
docker compose --profile cron up -d --wait            # finanzas corre con scheduler (heartbeat de auto_timeout) aunque su .env no lo active
docker compose ps --format '{{.Service}} {{.Status}}'  # backend, frontend, database, mailpit, scheduler
docker compose exec -T backend php -m | grep -x bcmath  # bcmath
OLIVA_VERIFY_SKIP="up prod-build" scripts/oliva/sync.sh verify
```
Si `verify` falla en algo que no sea por pecl: PARAR y mostrar la salida.

8.5 Merge local (sin push):
```bash
git switch main && git merge --no-ff --no-edit chore/oliva-sync-1.1.0 && git branch -d chore/oliva-sync-1.1.0
```
8.6 Memoria de finanzas (`/home/marcos/.claude/projects/-home-marcos-finanzas-ong/memory/project_state.md`):
en el párrafo "Gotcha descubierto … tag de imagen dev", reemplazar por "Resuelto en Oliva 1.1.0
(sync hecho <fecha>): imágenes `finanzas-ong-*:dev`, bcmath en `backend/php-extensions.txt`".
Cambiar las referencias a `-home-marcos-app` por `-home-marcos-oliva`. Agregar a su `CLAUDE.md`,
en los chequeos de inicio, `scripts/oliva/sync.sh check` si el merge no lo trajo; commitear.

## Fase 9 — Limpieza de lo global y cierre

9.1 Red e imágenes viejas (ya nadie las usa: CMP y finanzas usan nombres por proyecto):
```bash
docker ps -a --filter network=app_network --format '{{.Names}}'     # vacío
docker network rm app_network
docker image rm app-backend-dev:1.0 app-frontend-dev:1.0 app-backend-prod:1.0 app-frontend-prod:1.0 \
  app-backend-staging:1.0 app-frontend-staging:1.0
```
(`image rm` de un tag que también tiene otro nombre solo borra el tag: `finanzas-ong-backend:dev` queda.)

9.2 🛑 Quitar el banner de "SEPARACIÓN EN CURSO" del `CLAUDE.md` de crypto-pulse, commitear y pushear:
```bash
cd /home/marcos/crypto-pulse
# borrar la línea que empieza con "> ⚠️ **SEPARACIÓN EN CURSO" y la línea vacía siguiente
git commit -am "docs: separation from Oliva done"
git -c credential.helper= -c 'credential.helper=!gh auth git-credential' push
```
Memoria de crypto-pulse: en `crypto_pulse_state.md`, comprimir la sección "Separación de Oliva" a
una línea ("DONE <fecha>, runbook en `docs/runbook-separacion.md`") y en `MEMORY.md` sacar "EN VUELO".

9.3 `/home/marcos/CLAUDE.md` (guía raíz): donde lista los proyectos (`app`, `finanzas-ong`,
`mario-bros`, `ao-libre-upgrade`) poner `oliva`, `crypto-pulse`, `finanzas-ong`, `mario-bros`,
`ao-libre-upgrade`; en el paso 4 de `claude new project`, `~/app/claude-commands.md` → `~/oliva/claude-commands.md`.
Agregar una línea: "Las apps hechas con Oliva traen `scripts/oliva/` y se mantienen al día con
`claude oliva sync` (ver `~/oliva/docs/oliva/actualizaciones.md`)".

9.4 Reporte final a Marcos: qué fases se hicieron, hashes de los commits nuevos, qué gates
quedaron sin hacer (ej. 7.5 volúmenes) y si se usó algún plan B por pecl (en ese caso: "rebuildear
`crypto-pulse` y `finanzas-ong` con `docker compose build backend` cuando pecl vuelva").

## Si algo sale mal

| Síntoma | Qué es | Qué hacer |
|---|---|---|
| `pecl.php.net … 500/504` en un build | caída externa | plan B de la fase; seguir |
| `ERROR: el project '…' ya existe y pertenece a otro checkout` | guard de Oliva 1.1.0 | hay containers de ese project levantados desde otro dir: bajarlos desde su dir |
| `--frozen-lockfile` falla en el build del frontend | `yarn.lock` no coincide con `package.json` | `scripts/oliva/sync.sh locks` (o `/home/marcos/oliva/scripts/oliva/sync.sh locks`) y commitear el lock |
| `count(*)` en 0 tras la fase 5 | la copia del volumen no tomó | `docker compose down` (sin -v), repetir 4.2 con el volumen vacío y 4.3 |
| push 403 | credencial equivocada | usar el `-c credential.helper=…gh…` de la fase 2.3; no pegar tokens en URLs |
