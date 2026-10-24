# UPGRADING — notas para forks

Una sección por versión de Oliva, la más nueva arriba. `scripts/oliva/sync.sh` muestra
al fork las secciones más nuevas que su `OLIVA_VERSION`. Formato fijo (lo parsea el script):
encabezado `## X.Y.Z — fecha`, después **Acción requerida en el fork** (pasos concretos,
o "ninguna") y **Qué cambió** (resumen; el detalle está en `git log`).

## 1.4.3 — 2026-10-24

> Cuarta capa del audit: el runtime compilado (PHP y el binario de FrankenPHP). Se comprobó
> que **Trivy no ve a PHP** — en la imagen de FrankenPHP, PHP y el servidor salen compilados
> del source, no figuran como paquete, y Trivy no los matchea contra ninguna CVE DB (no detectó
> PHP2Shell en la imagen vulnerable). `composer`/`yarn audit` tampoco (PHP no es un paquete).
> El único rastro era `deps report` mostrando el bump de imagen cada ~45 días, sin marca de
> seguridad. La capa nueva lee las versiones pinneadas en el `FROM` del backend y las compara
> contra el upstream: PHP contra su rama en php.net (chequeo **duro**, falla el audit si hay un
> patch más nuevo), FrankenPHP contra su último release de GitHub (aviso **blando**, no falla).
> No es advisory-matching ni detección de lo no publicado — avisa cuando el upstream ya publicó
> el patch. El parseo del `FROM` tiene guardas contra falso verde: si no puede verificar (base
> que no es frankenphp, tag ilegible, o versión que no figura en php.net), avisa y saltea; nunca
> reporta "al día" sin confirmarlo.

> **Worker mode de FrankenPHP: ON por defecto en prod (fix de un apagado silencioso).** La
> imagen `frankenphp_prod` siempre horneó `FRANKENPHP_CONFIG=import worker.Caddyfile`, pero
> `.env.example` shipeaba `FRANKENPHP_CONFIG=` vacío en el `env_file` base. Ese env_file aplica
> a TODOS los entornos y pisa el `ENV` de la imagen (`environment:`/`env_file:` ganan sobre el
> `ENV` horneado), así que worker mode venía APAGADO en prod sin ningún error: `/health` daba ok
> igual. Se quitó la variable del template; ahora gana el valor de la imagen (dev=clásico,
> prod=worker). Opt-out deliberado a clásico: `FRANKENPHP_CONFIG=` vacío en el `environment:` de
> `docker-compose.prod.yml`, NUNCA en `.env` (ver `backend/docs/production.md`).

**Acción requerida en el fork**

- **Worker mode — borrar `FRANKENPHP_CONFIG` del `.env` del host.** El fix saca la variable de
  `.env.example`, pero tu `.env` real es gitignored: si lo copiaste de un `.env.example` viejo,
  todavía tiene la línea `FRANKENPHP_CONFIG=` y seguirá apagando worker mode. Borrala en **los dos**
  `.env` que importan: el local y el del **host en el VPS** (el que lee `scripts/deploy.sh`). Verificá
  después del deploy que worker arrancó: `docker logs <app>-backend-1 2>&1 | grep -i worker` debe
  mostrar el arranque del worker. Si querés seguir en clásico a propósito, movelo al `environment:`
  de `docker-compose.prod.yml` (no al `.env`).
- Audit de runtime: ninguna. `scripts/oliva/deps.sh` es OLIVA-owned y baja con el merge. El próximo
  `./oliva deps audit` del fork corre también la capa de runtime; como el `FROM` del backend
  también es owned, el fork hereda el mismo pin de PHP/FrankenPHP y verá lo mismo que Oliva.

**Qué cambió**

- Worker mode: se quita `FRANKENPHP_CONFIG=` de `.env.example` (y del `.env` de desarrollo del repo).
  `backend/frankenphp/worker.Caddyfile` fija `FRANKENPHP_LOOP_MAX 500` explícito (era el default
  implícito del runtime). Guard nuevo en CI (job `prod-config`: el stack prod no debe resolver
  `FRANKENPHP_CONFIG=''`) y en `verify.sh` (step `prod-worker`: la imagen prod hornea el valor).
  `backend/docs/production.md`: nota de opt-out corregida.
- `scripts/oliva/deps.sh`: capa `runtime` nueva (`check_runtime` + `check_php_runtime` duro +
  `check_frankenphp_runtime` blando), cableada en `audit` (afecta el exit code vía PHP) y en
  `report` (informativa). FrankenPHP usa `curl -L`: `dunglas/frankenphp` hace 301 redirect.
- `deps.sh` ahora localiza sus libs por `BASH_SOURCE` (no `$0`) y el dispatcher va detrás de una
  guarda `[[ BASH_SOURCE == $0 ]]`, para poder sourcear el archivo y testear las funciones con
  tags fabricados. Sin cambio de comportamiento al ejecutarlo normalmente.
- Docs: README §3 y `docs/oliva/actualizaciones.md` pasan de tres a cuatro capas; se corrige el
  texto que atribuía el runtime de PHP a Trivy.

## 1.4.2 — 2026-10-23

> Cron en prod: el scheduler se activa con `COMPOSE_PROFILES` en el `.env` del host, no
> editando `deploy.sh`. Hasta acá el script le decía al fork "agregá `--profile cron` al up"
> (un archivo OLIVA-owned que el fork no debe tocar), y una app con tareas en el crontab y sin
> el profile declarado deployaba sin scheduler, sin ningún error.
>
> `down` de los scripts: bajaba con `COMPOSE_PROFILES=cron`, que reemplaza los profiles del
> `.env`: cualquier servicio de otro profile quedaba corriendo con la versión vieja después del
> deploy. Hoy no le pega a ningún fork (en shared-infra no hay servicios de `queues` en prod),
> pero sí al `worker` de prod que viene (va detrás de `queues`). Ahora baja con `--profile '*'`.
>
> Constraints de composer: `doctrine-migrations-bundle` y `maker-bundle` no tenían techo
> (`>=3.7.1`, `>=1.68`), y migrations-bundle 4.0 ya existe. Hoy no entraba solo porque pide
> PHP 8.4 y doctrine-bundle 3. Ahora llevan techo, y un guard frena cualquier constraint sin techo.

**Acción requerida en el fork**

- Si el fork usa cron (tiene tareas en `backend/scheduler/crontab`): asegurar
  `COMPOSE_PROFILES=cron` (o `queues,cron`) en el `.env` de cada host donde deploye, y
  conviene dejarlo también en su `.env.example` para que un host nuevo lo herede. Si no
  está, el próximo `deploy.sh` lo avisa al final con un bloque `!! CRON INACTIVO`.
- Si el fork no usa cron: ninguna.
- Constraints: nada a mano si el fork no tocó esas dos líneas de `backend/composer.json`. El
  merge las trae con techo y `sync.sh locks` refresca el `content-hash` del lock (no cambia
  versiones). Si el fork tiene deps **propias** sin techo, `sync.sh locks` aborta y las lista:
  ponerles techo y volver a correrlo. El CI del fork también las marca (job `composer-constraints`).

**Qué cambió**

- `scripts/lib/cron-guard.sh` (nuevo): `warn_if_cron_inactive`, le pregunta a Compose
  (`config --services`) si el scheduler entra en el `up`; si no entra y el crontab tiene
  tareas, imprime un aviso. No aborta el deploy.
- `scripts/deploy.sh`, `scripts/deploy-staging.sh`: llaman al aviso al final; el mensaje
  final de `deploy.sh` ya no pide editar el script.
- `scripts/deploy.sh`, `deploy-staging.sh`, `down.sh`, `down-staging.sh`: el `down` corre con
  `--profile '*'` en vez de `COMPOSE_PROFILES=cron`. Baja todos los servicios con profile,
  incluidos los que agregue el fork. Sin `-v`, como siempre: los volúmenes no se tocan.
- `backend/composer.json`: `doctrine/doctrine-migrations-bundle` `>=3.7.1` → `^3.7.1`,
  `symfony/maker-bundle` `>=1.68` → `^1.68`. `bump-after-update` se queda (ver `AGENTS.md`).
- `scripts/oliva/unbound-constraints.php` (nuevo) + `require_bounded_constraints` en `lib.sh`:
  aborta `deps.sh update` y `sync.sh locks` si hay constraints sin techo en `require` o
  `require-dev`. Job de CI nuevo `composer-constraints`.
- `deps.sh update`: el resumen marca `⇑ MAJOR` los saltos de major (en 0.x, de minor), que
  solo pueden venir de deps transitivas.
- `AGENTS.md`, `.env.example`: documentan `COMPOSE_PROFILES` del host como el mecanismo.

## 1.4.1 — 2026-10-23

> Fix del extension point de PHP (`backend/php-extensions.txt`): con el driver buildx del CI
> (`docker-container`) todo fork con extensiones fallaba con `exit 100`
> (`mkstemp /tmp/apt.sig.* Permission denied`). finanzas-ong estaba rojo así desde 1.1.0.

**Acción requerida en el fork**

Ninguna obligatoria: el fix es transparente (baja con el `backend/Dockerfile`).

- Opcional, si el fork tiene una PECL con el formato viejo (`redis-6.2.0`): pasarla al nombre
  PIE (`phpredis/phpredis:6.2.0`) para no depender de pecl.php.net. El comentario de cabecera
  de `php-extensions.txt` del fork quedó viejo (Oliva no toca ese archivo para no generarle
  conflictos); la sintaxis vigente está en el comentario del extension point en `backend/Dockerfile`.
- Después del push del sync, mirar que el CI del fork quede verde: `./oliva doctor` ahora lo muestra.

**Qué cambió**

- `backend/Dockerfile`: `php-extensions.txt` entra por bind-mount en vez de `COPY --link` a
  `/tmp` (el `--link` dejaba `/tmp` en 755 con el driver del CI; el driver `docker` local no lo
  reproduce). Líneas con `/` (`vendor/paquete:versión`) se instalan con PIE.
- `scripts/oliva/verify.sh`: paso `[ci-build]`, rebuildea el backend con el driver del CI. Solo
  corre si `php-extensions.txt` tiene extensiones; si no, se saltea solo.
- `./oliva doctor`: muestra el último run del CI en `main` (solo si `gh` está instalado y logueado).

## 1.4.0 — 2026-10-23

> Capa agéntica: entry point `./oliva` + migración de los docs agénticos a `AGENTS.md`
> (formato abierto, vendor-neutral). Los dos ejes van juntos porque ambos tocan el mismo
> archivo SHARED (`CLAUDE.md` → `AGENTS.md`): hacerlo en dos releases sería pagar el mismo
> conflicto dos veces. Detalle completo: `docs/roadmap/epics/E-capa-agentica.md`.

**Acción requerida en el fork**

1. **Antes de resolver el merge**, en el fork (para que git vea el rename en ambos lados
   y mergee el contenido en vez de tratarlo como borrado + archivo nuevo):
   ```bash
   git mv CLAUDE.md AGENTS.md
   git mv claude-commands.md agent-commands.md
   git commit -m "chore: renombrar docs agénticos antes del sync de Oliva 1.4.0"
   ```
2. **Sync.** Baja `./oliva` (CLI, nuevo — entra a `scripts/oliva/owned-paths.txt` como
   OLIVA-owned), el `CLAUDE.md` nuevo (ahora es el stub de una línea `@AGENTS.md` — también
   OLIVA-owned, nunca se vuelve a editar) y los cambios de `AGENTS.md`/`agent-commands.md`
   (SHARED → resolver a mano, igual que siempre). El `agent-commands.md` de Oliva declara el
   prefijo de los comandos de chat una sola vez arriba; si el fork usa un prefijo distinto de
   `claude`, es la única línea a tocar.
3. **Después del merge:**
   ```bash
   mv rules-claude.md AGENTS.local.md
   ```
   (está gitignored → no viene en el merge, no genera conflicto; actualizar también la línea
   en `.gitignore` si el fork la tiene copiada en vez de heredada).
4. **Chequeos de inicio de sesión.** Si el fork tenía el bloque de 7 comandos pegado en su
   propio `AGENTS.md` (heredado de antes de esta versión), reemplazarlo por `./oliva doctor`.
5. **Verificar en la sesión siguiente** (gate de carga efectiva — es un fallo mudo si no se
   chequea): abrir sesión nueva en el repo, correr `/context` y confirmar que `AGENTS.md`
   aparece bajo "Memory files". Si no aparece, el agente dejó de leer la guía operativa y
   nadie se entera sin este chequeo.

**Qué cambió**

- **`./oliva`** (nuevo): dispatcher puro sobre `scripts/oliva/*.sh` y `scripts/*.sh`, con
  `exec` para propagar argumentos/exit codes verbatim. `oliva doctor` colapsa los 7 chequeos
  de sanidad en una llamada read-only (ningún paso lo aborta, ni con Docker abajo).
- **`AGENTS.md`** (antes `CLAUDE.md`) y **`agent-commands.md`** (antes `claude-commands.md`):
  mismo contenido, renombrados vía `git mv` para que el merge en forks sea limpio. Formato
  abierto, lo leen Claude Code, Codex, Cursor, Gemini CLI, Copilot, Aider, Zed y otros.
- **`CLAUDE.md`** (nuevo, stub OLIVA-owned): una línea, `@AGENTS.md` — import de Claude Code.
  Necesario porque Claude Code lee `AGENTS.md` nativo solo si no hay `CLAUDE.md` ni
  `CLAUDE.local.md` en el cwd ni en ningún directorio por encima; sin el stub, un `CLAUDE.md`
  de más arriba en el filesystem tapa la guía del repo en silencio.
- **`rules-claude.md` → `AGENTS.local.md`**: mismo mecanismo (gitignored, lectura explícita),
  solo cambia el nombre.
- `scripts/oliva/owned-paths.txt`: `oliva` y `CLAUDE.md` (stub) pasan a OLIVA-owned; la nota
  SHARED ahora dice `AGENTS.md`/`agent-commands.md`.

## 1.3.0 — 2026-10-22

> Feature: "el aviso por advisory". Chequeo de CVEs fuera del ciclo de 45 días, y una
> capa nueva que antes no miraba nadie: los CVEs del SO y los binarios DENTRO de las
> imágenes base (Trivy). Nada que instalar en el host: Trivy corre como contenedor.

**Acción requerida en el fork**

1. **Sync.** Baja `scripts/oliva/deps.sh` (nuevos subcomandos `audit` y `scan-images`),
   el job `image-scan` del CI y `.trivyignore`. `.gitignore` y `CLAUDE.md` son SHARED →
   resolver a mano el merge (agregar la línea `.oliva/` al `.gitignore` y el renglón de
   `deps.sh audit` en "Chequeos de sanidad").
2. **Correr el primer audit:** `scripts/oliva/deps.sh audit`. Baja la DB de Trivy y escanea
   las 5 imágenes base. Deja la fecha en `.oliva/audit-state` (gitignored, por-repo). De ahí
   en más, `scripts/oliva/deps.sh due` avisa cuando pasaron >7 días sin audit.
3. **(Opcional) Si un CVE HIGH/CRITICAL con fix es infixable** (espera rebuild del upstream)
   o no aplica a la app: anotarlo en `.trivyignore` con su justificación, para que no siga
   marcando. Trivy ya filtra por `--ignore-unfixed`, así que esto es excepcional.
4. **(Opcional) Apagar el scan en CI** si molesta en un fork puntual:
   `gh variable set OLIVA_CI_SKIP --body trivy` (se concatena con los otros tokens, ej. `schema trivy`).

**Qué cambió**

- `scripts/oliva/deps.sh`: subcomando **`audit`** (solo CVEs, a demanda: `composer audit` +
  `yarn audit` + Trivy sobre las imágenes base) y **`scan-images`** (solo Trivy, lo usa el CI).
  `due` ahora también reporta la frescura del audit (umbral `OLIVA_AUDIT_DUE_DAYS`, default 7).
  `report` incluye la sección de Trivy. Trivy pinneado en `TRIVY_VERSION` (0.72.0; nunca < 0.71.1
  por el incidente de supply-chain de la v0.69.4).
- `.github/workflows/ci.yml`: job **`image-scan`** (report-only, no rompe `main`; opt-out
  `OLIVA_CI_SKIP=trivy`). Usa el mismo Trivy pinneado vía `docker run`, no la `trivy-action`.
- `.trivyignore` (nuevo, SHARED) y `.gitignore` (`.oliva/`).
- **Por qué una sola fuente por capa y no varias:** las bases de advisories de paquetes
  (Packagist/GHSA/OSV/NVD) se alimentan entre sí → apilarlas sobre el mismo lock es redundante.
  La robustez viene de cubrir capas distintas; la única descubierta eran las imágenes. Detalle en
  `docs/oliva/actualizaciones.md`.

## 1.2.0 — 2026-10-22

> Bump de dos imágenes base que llegaron a EOL: Node y RabbitMQ. Node es un swap
> limpio (rebuild y listo). RabbitMQ **solo** necesita acción manual en un fork que
> ya corra un nodo con datos persistidos de un 3.x — ver abajo.

**Acción requerida en el fork**

1. **Sync + rebuild del frontend** (Node 20 → 24). Es un swap de imagen base, sin acción
   manual: `scripts/oliva/sync.sh` baja el `frontend/Dockerfile` nuevo y el rebuild usa
   node 24. Verificar con `scripts/oliva/verify.sh` (su `prod-build` corre el `vite build`
   sobre node 24).
2. **RabbitMQ 3 → 4 — depende de si el fork tiene un nodo con datos:**
   - **El fork NUNCA activó el profile `queues`** (no hay nodo ni volumen `*_rabbitmq_data`):
     **ninguna acción**. Un nodo 4.0 fresco arranca con todos los feature flags enabled.
   - **El fork SÍ corre RabbitMQ con un volumen poblado de un 3.x:** ANTES de swappear la
     imagen (es decir, con el nodo **todavía en 3.13** corriendo), habilitar todos los
     feature flags estables:
     ```bash
     docker compose exec rabbitmq rabbitmqctl enable_feature_flag all
     ```
     Recién después sync + recrear el container. Si no, el nodo 4.0 **se niega a bootear**
     con un *required feature flag* sin habilitar, y no deja rastro obvio. El tag viejo
     `3-management` ya resolvía a 3.13.7, que es la única versión desde la que 4.0 soporta
     upgrade directo — no hay salto intermedio que dar.
   - **Si el fork usaba classic mirrored queues (HA policies):** 4.0 las **eliminó**. Migrar
     a quorum queues antes de subir. Los transports de ejemplo de Oliva
     (`ingest`/`enrich`/`failed`) son classic queues normales, no mirrored → no les afecta.

**Qué cambió**

- `frontend/Dockerfile`: imagen base `node:20-slim` → **`node:24-slim`**. Node 20 quedó EOL
  el 2026-04-30. Se eligió 24 ("Krypton", Active LTS) y no 26, que salió este mes como
  *Current* y todavía no es LTS. Verificado: runtime `v24.22.1`, `verify.sh` 8/8 (el
  `vite build` de prod corre sobre node 24 sin cambios).
- `docker-compose.yml`: `rabbitmq:3-management` → **`rabbitmq:4-management`** (4.4.0). El 3.x
  está EOL desde 2024-09. Verificado levantando el profile `queues`: nodo 4.4.0 healthy
  (`rabbitmq-diagnostics ping`) y el worker de Symfony Messenger conecta por AMQP y declara
  las colas `ingest`/`enrich` sin errores. La extensión `php-amqp` habla AMQP 0-9-1, que no
  cambió entre 3 y 4, así que no hay bump de dependencias PHP.

## 1.1.5 — 2026-10-22

> ⚠️ **Release de seguridad. Syncear y rebuildear cuanto antes.** Parchea dos RCE sin
> autenticación (CVSS 9.2) que afectan a todo fork que corra la imagen base anterior.

**Acción requerida en el fork**

1. **Sync + rebuild, y RECREAR los containers — no basta un `restart`.** El parche no toma
   efecto en procesos vivos: un `docker compose restart` deja los workers de FrankenPHP
   sirviendo el PHP viejo, sin dejar rastro. `./scripts/deploy.sh` ya hace
   `down --remove-orphans` antes del `up`, así que alcanza con eso. En dev:
   `docker compose up -d --build --force-recreate`.
2. **Borrar `PHP_VERSION` del `.env.backend` del fork** (si lo tiene). `.env.backend` es un
   path SHARED: el sync NO lo baja solo, hay que hacerlo a mano. No hace falta reemplazarlo
   por nada — la versión de PHP la fija el tag de la imagen base en `backend/Dockerfile`, que
   es la única fuente de verdad y baja con el sync.
3. **Destrackear `backend/config/reference.php`:** `git rm --cached backend/config/reference.php`.
   La línea del `.gitignore` baja con el sync (también SHARED → resolver a mano), pero el
   `rm --cached` hay que correrlo en cada fork. El archivo se queda en disco y se regenera
   solo; no se pierde nada.
4. **Verificar:** `scripts/oliva/verify.sh`. El step nuevo `[php-version]` falla si lo que
   corre no es el PHP pineado — es lo que confirma que el parche realmente se aplicó.

**Qué cambió**

- `backend/Dockerfile`: imagen base `dunglas/frankenphp:1.13.1-php8.3.35` →
  **`1.13.2-php8.3.36`**. PHP 8.3.36 (security release del 2026-10-21) parchea **PHP2Shell**
  (CVE-2026-109618 + CVE-2026-109619), dos RCE sin auth, CVSS 9.2. No es un CVE de
  espectador: el 109619 es estado de request stale que un worker reusa en el request
  siguiente, y `frankenphp_prod` corre worker mode.
- Se eligió FrankenPHP **1.13.2** y no el bump mínimo `1.13.1-php8.3.36` (que existe) porque
  1.13.2 es a su vez un security release y 2 de sus 4 vulns propias aplican a esta topología:
  fuga de fragmentos del input del cliente anterior vía `error_get_last()`/`libxml_get_errors()`
  en worker mode (GHSA-4gfw-9v29-gp9h) y thread pool ocupable por un cliente sin auth que
  encola requests y se desconecta (GHSA-fq24-r53r-xcx3). Sus upgrade notes son todas de
  static builds (glibc 2.28, assets de macOS) → no aplican, acá se usa la imagen Docker.
  Riesgo de regresión bajo: patch dentro del mismo minor.
- **Sin cambios de dependencias.** `composer.json` ya pedía `php: >=8.3.31`, así que 8.3.36
  lo cumple sin tocar `composer.lock`. Al ser el mismo minor el ABI de Zend no cambia: las
  extensiones por PIE (`apcu`, `amqp`, `xdebug`) recompilan igual, sin cambiar sus pines.
- `.env.backend`: **eliminada `PHP_VERSION`**, que no consumía nadie (ni el Dockerfile —no
  tiene `ARG`—, ni compose, ni el código, ni el CI) y estaba 23 patches atrás. El problema no
  era el valor viejo: se lee como "la versión de PHP del proyecto", así que al parchear un CVE
  se bumpea esa variable, se ve el número correcto y se cree que el fix se aplicó.
- `scripts/oliva/verify.sh`: step nuevo **`[php-version]`** (después de `[up]`). Compara el
  `PHP_VERSION` del container contra el pin del `Dockerfile`, y falla también si el tag deja de
  pinear un patch exacto. Un build verde no prueba que estés parcheado si el `up` reusó un
  container vivo. Mismo criterio que `[mercure]`: cada incidente pasado se vuelve una
  assertion.
- `.gitignore`: **`backend/config/reference.php` destrackeado.** Es auto-generado por
  `cache:clear` solo para autocompletado del IDE (nada en runtime lo lee), pero estaba
  trackeado y cada build lo reescribía → todo `verify.sh` dejaba sucio un archivo commiteado
  y bloqueaba a `release.sh`, que exige árbol limpio. La copia que había en git además quedó
  stale (listaba `when@development`, un entorno que el proyecto ya no usa).

## 1.1.4 — 2026-10-22

**Acción requerida en el fork**

Ninguna en el código. Rebuild (`docker compose build` / `./scripts/deploy.sh`). Relevante sobre
todo para forks con extensiones propias en `backend/php-extensions.txt` (ej. finanzas-ong: bcmath).

**Qué cambió**

- `backend/Dockerfile`: fix de orden en el stage base. El `RUN` de PIE (amqp/apcu) **purga el
  toolchain de compilación** (`$PHPIZE_DEPS`) al terminar. En 1.1.3 ese RUN quedó ANTES del
  extension point del fork (`install-php-extensions $exts`), que necesita `gcc` para compilar sus
  extensiones → un fork con algo en `php-extensions.txt` fallaba el build con `gcc: not found`
  (`exit 127`). Oliva/crypto-pulse no lo notaron porque su `php-extensions.txt` está vacío. Ahora
  el RUN de PIE va ÚLTIMO en el stage base, después del extension point, así todos los
  `install-php-extensions` corren con el toolchain presente y la purga limpia al final.

## 1.1.3 — 2026-10-22

**Acción requerida en el fork**

Ninguna en el código (el `backend/Dockerfile` es de Oliva y baja con el sync). Solo
rebuildear: `docker compose build` (dev) o `./scripts/deploy.sh` (VPS).

**Qué cambió**

- `backend/Dockerfile`: **`amqp`, `apcu` y `xdebug` migradas de PECL a PIE** (`php/pie`). El
  band-aid de 1.1.2 (pinear `install-php-extensions`) NO alcanzó: las extensiones con versión
  pineada se siguen bajando de `pecl.php.net`, que está en phase-out e intermitente → el CI
  seguía rompiendo con `exit 100` (ahora en `xdebug`). PIE baja de Packagist/GitHub, nunca toca
  `pecl.php.net`. La imagen oficial de PIE se monta solo en build-time
  (`--mount=type=bind,from=ghcr.io/php/pie:1.5.3-bin`), no queda en la imagen final. amqp suma
  `librabbitmq-dev` como dep de build. Versiones pineadas exactas, idénticas a antes
  (amqp 2.2.0, apcu 5.1.28, xdebug 3.5.3).
- `install-php-extensions` (mlocati 2.12.3) queda SOLO para lo que no pasa por pecl: `@composer`
  y las bundled de PHP (`intl`/`opcache`/`pdo_pgsql`/`zip`).
- **Punto de extensión del fork (`backend/php-extensions.txt`) sigue usando
  `install-php-extensions`.** Para extensiones bundled de PHP (bcmath, gmp, …) no hay problema.
  Si un fork agrega ahí una extensión PECL y el build flakea, migrar esa a `pie install` también.
- Verificado con build `--no-cache` del target `frankenphp_dev`: las 3 compilan vía PIE
  (0 menciones de pecl.php.net), cargan en runtime con las versiones correctas, amqp linkea
  `librabbitmq.so.4`, y el toolchain de build queda purgado.

## 1.1.2 — 2026-10-22

**Acción requerida en el fork**

Ninguna en el código (el `backend/Dockerfile` es de Oliva y baja con el sync). Solo
rebuildear: `docker compose build` (dev) o `./scripts/deploy.sh` (VPS). Esto
destraba los builds limpios desde cero, que estaban rotos por `install-php-extensions
... exit code 100`.

**Qué cambió**

- `backend/Dockerfile`: `install-php-extensions` pasa a pinearse fresco desde
  `mlocati/php-extension-installer:2.12.3` (en vez del que viene congelado en la imagen
  base). El viejo bajaba siempre la lista REST de metadata de `pecl.php.net` y rompía con
  `exit 100` ahora que ese endpoint está en phase-out (PECL deprecado, RFC
  `adopt_pie_deprecate_pecl`). El 2.12.x solo la consulta cuando hace falta.
- **Deuda viva — TODO(PIE):** esto es un band-aid; seguimos en PECL. La salida definitiva
  es migrar los `install-php-extensions` a `pie install vendor/pkg`. Bloqueado hoy porque
  PIE solo tiene publicado `xdebug`, no `amqp` ni `apcu`. Migrar el día que esos dos estén
  disponibles como paquetes PIE.

## 1.1.1 — 2026-10-21

**Acción requerida en el fork**

Ninguna. En el VPS, el primer `./scripts/deploy.sh` posterior ya limpia las imágenes viejas
sin tag que se hayan acumulado.

**Qué cambió**

- `scripts/lib/docker-prune.sh`: `deploy.sh`, `deploy-staging.sh` y `deps.sh update` borran al
  final las imágenes sin tag y la caché de build de más de 7 días (`OLIVA_NO_PRUNE=1` para saltear).

## 1.1.0 — 2026-10-21

**Acción requerida en el fork**

1. **Primer sync con las herramientas.** Este es el merge que trae `scripts/oliva/`. Si el
   fork todavía no las tiene, el merge se hace a mano una única vez:
   `git fetch oliva-upstream && git switch -c chore/oliva-sync-1.1.0 && git merge oliva-upstream/main`.
   De ahí en más: `scripts/oliva/sync.sh start`.
2. **Imágenes por proyecto.** Los compose ahora nombran las imágenes
   `${COMPOSE_PROJECT_NAME}-<servicio>:<dev|prod|staging>`. Si el fork agregó un servicio
   propio con `image:` (no de Docker Hub) o tocó algún `image:` en su override, pasarlo a la
   misma convención. Nunca un tag fijo: es global al host y otra app lo pisa.
3. **Red por proyecto.** `app_network` ya no tiene `name:` fijo (pasa a `<project>_app_network`).
   Si el fork tiene `name: app_network` en algún archivo propio, sacarlo.
4. **`frontend/yarn.lock` versionado.** El build ahora usa `--frozen-lockfile`. Después del
   merge: `scripts/oliva/sync.sh locks` (genera el lock contra el `package.json` del fork),
   verificar que `frontend/yarn.lock` ya no está en el `.gitignore` y commitearlo.
5. **Dev local:** `docker compose down && docker compose up -d --build`. Las imágenes
   `app-*-dev:1.0` y la red `app_network` quedan huérfanas: borrarlas cuando **ninguna** app
   las use (`docker image rm app-backend-dev:1.0 app-frontend-dev:1.0`, `docker network rm app_network`).
6. **VPS (en el próximo deploy, no antes):** `./scripts/deploy.sh` construye `<app>-backend:prod`
   y `<app>-frontend:prod` y recrea los containers. Volúmenes, red y alias no cambian (dependen
   de `-p`, que es el mismo). Después: `docker image rm app-backend-prod:1.0 app-frontend-prod:1.0
   app-backend-staging:1.0 app-frontend-staging:1.0` cuando ninguna app del VPS siga sin syncear.
7. **Extensiones PHP propias → `backend/php-extensions.txt`.** Si el fork había agregado
   extensiones en `backend/Dockerfile` (finanzas-ong: `bcmath`), ese archivo es de Oliva y en
   el merge **hay que sacarlas de ahí y listarlas en `backend/php-extensions.txt`** (una por
   línea), antes de tomar el Dockerfile de Oliva. Si no, la imagen se construye sin ellas.
8. **Chequeos de inicio de sesión.** Agregar al `CLAUDE.md` del fork, en "Chequeos de sanidad":
   `scripts/oliva/sync.sh check` y `scripts/oliva/deps.sh due`.

**Qué cambió**

- Nombres de imagen y red derivados del project name (fin de las colisiones entre apps).
- `scripts/lib/project-guard.sh`: `deploy*.sh`/`down*.sh` abortan si el project pertenece a
  otro checkout y rechazan nombres `*-staging`.
- `frontend/yarn.lock` versionado + `--frozen-lockfile`.
- `backend/php-extensions.txt`: extensiones PHP propias de la app sin tocar el Dockerfile.
- Extensiones PECL y composer fijados (`amqp-2.2.0`, `apcu-5.1.28`, `xdebug-3.5.3`, composer `2.10.3`).
- `frontend/Caddyfile`: `trusted_proxies static private_ranges` (backport de finanzas-ong `a42aced`):
  detrás del reverse-proxy compartido, el backend recibe la IP real del cliente.
- Sistema de actualización: `OLIVA_VERSION`, `docs/oliva/` (este archivo y `actualizaciones.md`),
  `scripts/oliva/{sync,deps,verify,release}.sh`, `scripts/oliva/owned-paths.txt`.
