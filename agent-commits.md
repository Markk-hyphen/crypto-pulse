# agent-commits.md — registro de commits del agente (Oliva)

Registro detallado de cambios del agente que merecen justificación de *por qué*
(no se anota cada commit — ver protocolo en `CLAUDE.md`). Formato en `CLAUDE.md`
§ "Protocolo de commits del agente".

---

## [PASO 1.1] fix(env): APP_ENV corto (prod/dev) — reactiva los bloques when@ de Symfony
**Hash:** `1fd2a7a`
**Rama:** `feat/env-isolation-deploy`
**Fecha:** 2026-06-30

### Cambios
| Archivo | Tipo | Descripción |
|---|---|---|
| `docker-compose.prod.yml` | modificado | `APP_ENV=production` → `prod` en `backend` y `scheduler` (×2). |
| `docker-compose.override.yml` | modificado | `APP_ENV: development` → `dev` en `backend`, `scheduler` y `worker` (×3). |
| `.env.example` | modificado | `APP_ENV=development` → `dev` (la `.env` base que el VPS copia en el deploy). |
| `docker-compose.staging.yml` | modificado | Comentario del override stale: citaba `APP_ENV=production` y "production no está en bundles.php" → `prod`. La lógica del override no cambia. |
| `CLAUDE.md` | modificado | Misma actualización stale en el gotcha de precedencia de `APP_ENV`. |

(El `.env` local del dev quedó alineado a `dev`, pero es gitignored y no entra en este commit.)

### Justificación
Deuda conocida (detectada 2026-06-30, ver memoria `oliva-state`): el `Dockerfile`
hornea el `ENV APP_ENV` corto y correcto (`dev`/`prod`/`staging`, los strings que
Symfony espera), pero los compose files lo **pisaban** con la palabra larga vía
`environment:`, que en Compose tiene mayor precedencia que el `ENV` de la imagen.

Symfony matchea los bloques `when@prod:` / `when@dev:` por **string exacto**:
`production` ≠ `prod`, `development` ≠ `dev`. Resultado medido (no cosmético): en
prod nunca se aplicaba el `when@prod:` de `backend/config/packages/doctrine.yaml`
— prod corría **sin** los cache pools de query/result de Doctrine y **regenerando
proxies** (`auto_generate_proxy_classes`), además de perder
`strict_requirements: null` de `routing.yaml`. En runtime, con `APP_ENV=production`,
Symfony buscaba `var/cache/production/` (inexistente; el build horneó
`var/cache/prod/`) y recompilaba la cache como entorno `production`.

Se verificó primero que **no fuera otra deuda nueva en los Dockerfiles** (sospecha
inicial): los `Dockerfile` ya estaban bien — las palabras largas que aparecen ahí
son falsos positivos (`php.ini-production`/`-development` son templates de PHP; los
stages `development`/`production` del frontend son nombres de build, no `APP_ENV`).
El bug vivía solo en compose + `.env.example`.

**Alternativa descartada:** quitar el `APP_ENV` de los compose y depender solo del
`ENV` horneado. Se eligió el cambio mínimo (`production`→`prod`, `development`→`dev`)
por ser de menor riesgo y porque el override explícito sigue siendo necesario en
`staging.yml` (donde debe pisar el `prod` heredado de `prod.yml`).

**Auditoría de regresión:** no hay ningún `when@production`/`when@development` real
(los únicos están en `config/reference.php`, un docblock de Symfony); no hay
`.env.production`/`.env.development` huérfanos; ningún código compara contra el
string largo; CI no asume la palabra larga. Verificado con `docker compose config`
que `APP_ENV` resuelve corto en `backend`/`scheduler` en los 3 entornos
(dev/prod/staging), incluyendo el `scheduler` tras el profile `cron`.

---

## [PASO 1.2] ci: post-merge smoke + caché de capas GHA + guard de APP_ENV prod
**Hash:** `57663fe`
**Rama:** `main` (mergeado vía FF desde `feat/env-isolation-deploy`)
**Fecha:** 2026-06-30

### Cambios
| Archivo | Tipo | Descripción |
|---|---|---|
| `.github/workflows/ci.yml` | modificado | Recalibración completa al flujo solo-dev (ver justificación). |

### Justificación
Marcos cuestionó si PRs + GitHub Actions tienen sentido a su escala (solo-dev, ONG,
1-3 apps chicas) si igual no mira el CI y tarda ~15 min. Diagnóstico tras leer el
workflow: **no había testeo de más** — el `tests` job ya es un smoke test correcto
(health + Mercure + migraciones + `schema:validate` + PHPUnit). El tiempo se iba en
**buildear sin caché** (compila extensiones PHP + `composer install` + `yarn install`
desde cero cada corrida). Tres cambios quirúrgicos:
- **Triggers:** se saca `pull_request` (se elimina la ceremonia de PR, ver
  [[feedback]] flujo solo-dev), se deja `push:main` + `workflow_dispatch`. El CI pasa a
  correr DESPUÉS del merge — red de seguridad que solo avisa en rojo, no algo que
  haya que vigilar.
- **Caché de capas GHA:** build vía `docker/bake-action` con `cache-from/to=type=gha`.
  Con deps sin cambios, las capas caras son cache-hit → el build cae de minutos a
  segundos. Requiere el driver docker-container de `setup-buildx-action` (el driver
  por defecto no soporta backends de caché). Sólo se buildean `backend`+`frontend`
  (los únicos con `build`); `database` se pullea en el `up`.
- **Job `prod-config` (la guarda que pidió Marcos):** valida vía `compose config`
  (sin build, corrió en **3s** en CI) que `APP_ENV` resuelve a `prod` en backend y
  scheduler del stack prod. Atrapa la clase de bug del PASO 1.1 (palabra larga
  pisando `APP_ENV` → `when@prod` de Symfony desactivado), que el job `tests` NO ve
  porque solo levanta el stack DEV.

**Resultado en CI:** los 3 jobs verdes. Primera corrida 12m18s (priming: además de
buildear, *escribe* el caché). El speedup esperado (~2-4 min) se valida recién en el
próximo push a main (caché disponible para *leer*). Deuda menor anotada: las actions
targetean Node 20 (deprecado), bumpear a `checkout@v5` etc. cuando convenga.

> Nota: este PASO 1.2 se registró a posteriori (en el `claude reiniciar` de cierre),
> no en el mismo commit `57663fe` — excepción puntual a la regla de "log y commit
> juntos", porque el valor de dejar el cierre de sesión documentado lo justifica.

---

## [PASO 2.1] docs(bruno): convención de API testing doc-only (README + runbook)
**Hash:** `468b2c2`
**Rama:** `main`
**Fecha:** 2026-06-30

### Cambios
| Archivo | Tipo | Descripción |
|---|---|---|
| `README.md` | modificado | Nueva fila en la tabla de stack: `API testing → Bruno collection in api/` (marcada como per-app, no shipeada por Oliva). |
| `CLAUDE.md` | modificado | Nuevo paso 12 en el runbook de deploy shared-infra: smoke de flujos de negocio con la collection Bruno contra `{{base_url}}`, simétrico al `fixtures:load` del runbook de staging. |
| `agent-commits.md` | modificado | Esta entrada. |

### Justificación
finanzas-ong (primer fork real) tiene una collection Bruno funcionando en `api/`
(commit `27ff98c`): environments prod/staging, auto-token post-login, `batch_id`
capturado para confirmar sin copy-paste, 9 requests cubriendo todos los flujos.
Surgió la pregunta de si eso debía subir a Oliva como stub físico (igual que
`AppFixtures` de la seeding layer).

**Decisión: NO shipear archivos.** A diferencia de las fixtures —donde el stub
`AppFixtures` es genérico y reutilizable—, una collection Bruno es 100% dominio de
la app (los endpoints, los payloads, los flujos son de finanzas-ong, no de Oliva) y
Bruno es una app externa, no parte del stack corriendo. Con n=1 fork, extraer una
convención de *layout de archivos* es prematuro: no hay evidencia de qué es
invariante entre apps.

**Lo que SÍ va en Oliva (doc-only, este commit):** (1) una línea en la tabla de
stack del README declarando la convención "API testing: Bruno en `api/`, por app";
(2) un paso en el runbook de deploy simétrico al `fixtures:load` de seeding —
health check confirma que el proceso arranca, la collection confirma que el dominio
funciona end-to-end. Extraer una convención de archivos recién cuando la app #2
confirme que el layout es invariante.

---

## [1.1.0] Oliva 1.1.0 — nombres por proyecto + sistema de actualizaciones para Oliva y sus forks
**Hash:** `1090b30..d6b95b4` (9 commits; registrados juntos al cerrar la versión, a pedido de Marcos)
**Rama:** `main`
**Fecha:** 2026-10-21

### Cambios
| Archivo | Tipo | Descripción |
|---|---|---|
| `docker-compose.override.yml` / `docker-compose.prod.yml` / `docker-compose.staging.yml` | modificado | Imágenes `${COMPOSE_PROJECT_NAME}-<servicio>:<dev\|prod\|staging>` en vez de `app-*-<env>:1.0` (`1090b30`). |
| `docker-compose.yml` | modificado | `app_network` sin `name:` fijo → `<project>_app_network` (`1090b30`). |
| `scripts/lib/project-guard.sh` | nuevo | Guard de colisión: aborta si el project pertenece a otro checkout; rechaza apps `*-staging` (`1090b30`). |
| `scripts/deploy.sh`, `deploy-staging.sh`, `down.sh`, `down-staging.sh` | modificado | Sourcean el guard (`1090b30`). |
| `.github/workflows/ci.yml` | modificado | `COMPOSE_PROJECT_NAME` fijo para que bake y compose coincidan (`1090b30`); pasos `schema`/`phpunit` apagables por fork con la variable de repo `OLIVA_CI_SKIP` (`f31a329`). |
| `frontend/yarn.lock`, `.gitignore`, `frontend/Dockerfile` | nuevo / modificado | Lock versionado + `yarn install --frozen-lockfile` (`920d6f4`). |
| `backend/Dockerfile` | modificado | PECL y composer fijados: `amqp-2.2.0`, `apcu-5.1.28`, `xdebug-3.5.3`, composer `2.10.3` (`a857f44`); instala lo que liste `backend/php-extensions.txt` (`d6b95b4`). |
| `backend/php-extensions.txt` | nuevo | Extension point: extensiones PHP propias de la app, vacío en Oliva (`d6b95b4`). |
| `frontend/Caddyfile` | modificado | `trusted_proxies static private_ranges`, backport de finanzas-ong `a42aced` (`4db5de1`). |
| `OLIVA_VERSION` | nuevo | `1.1.0` (`15fc532`). |
| `docs/oliva/actualizaciones.md`, `docs/oliva/UPGRADING.md` | nuevo | Modelo de actualización y notas por versión para forks (`15fc532`, ampliados después). |
| `scripts/oliva/deps.sh`, `sync.sh`, `verify.sh`, `release.sh`, `lib.sh`, `owned-paths.txt` | nuevo | Herramientas de mantenimiento y sync (`15fc532`; shellcheck en `b6893aa`; triage seguro en `d6b95b4`). |
| `claude-commands.md` | modificado | `-f` de `claude reiniciar`, ruta de memoria genérica, comandos `claude oliva deps` / `claude oliva sync` (`15fc532`, `76d8e79`). |
| `CLAUDE.md`, `README.md` | modificado | Sección de versiones/forks, aislamiento por app, chequeos de inicio con `deps.sh due` (`1090b30`, `15fc532`). |
| `agent-commits.md`, `scripts/oliva/sync.sh`, `scripts/oliva/owned-paths.txt`, `docs/oliva/actualizaciones.md` | modificado | Esta entrada; el log del proyecto queda fuera del sync (gana el del fork). |

### Justificación
**Nombres por proyecto.** Un nombre fijo en Docker es global al daemon, no al repo. Con dos apps en la misma máquina, el build de finanzas-ong pisaba `app-backend-dev:1.0` y los containers de CMP quedaron apuntando a un ID huérfano: un `up` sin `--build` habría arrancado CMP con el `vendor` de finanzas. La red fija `app_network` metía los dos stacks dev en la misma red, donde el DNS de Docker hace round-robin entre los `backend`/`database` de ambas apps (el mismo bug que motivó el split de redes de la infra). En el VPS iba a pasar lo mismo con `app-backend-prod:1.0` el día que CMP se deployara al lado de finanzas. Se eligió `<project>-<servicio>:<entorno>` en vez de omitir `image:` (Compose nombraría `<project>-<servicio>` solo) porque `backend`/`worker`/`scheduler` comparten una imagen: sin nombre explícito se construirían tres veces y dev y prod se pisarían dentro del mismo proyecto. El guard cierra la deuda documentada: si el nombre de proyecto se repite entre checkouts, ahora también chocarían las imágenes, así que el chequeo pasa a ser parte del mismo fix.

**Todo fijado.** Los dos incidentes de dependencias tuvieron la misma causa: algo flotante que cambió en un rebuild cualquiera (el tag `1-php8.3` de FrankenPHP rompió Mercure; el `yarn.lock` sin versionar hacía lo mismo con el frontend). Las extensiones PECL se fijaron después de ver a pecl.php.net devolver 500/504 en plena sesión.

**Sistema de actualización.** Se descartó Dependabot/Renovate con PRs (el flujo es solo-dev sin PRs; un bot abriendo PRs que nadie mergea es ruido) y un cron que syncee solo (un merge puede tocar código del fork; alguien tiene que verlo). Lo elegido: recordatorios baratos en el chequeo de inicio de sesión (`deps.sh due`, `sync.sh check`), un ciclo semiautomático que solo sube versiones dentro de los rangos y la red de seguridad `verify.sh`. Los saltos de major e imagen base quedan manuales, uno por commit. La pieza clave es la propiedad de archivos (`owned-paths.txt`) con extension points: el ensayo del sync de finanzas mostró que quedarse con la versión de Oliva del Dockerfile **borraba `bcmath`** y rompía el cálculo de dinero. De ahí `backend/php-extensions.txt` y que `sync.sh` muestre lo que cambió el fork antes de sugerir nada.

**Problema encontrado durante la ejecución:** el `agent-commits.md` de Oliva viaja con cada merge y chocaría con el log propio de cada fork. `sync.sh` ahora lo clasifica `[FORK]` (gana el del fork).

---

## [1.1.1] chore(scripts): limpiar restos de build al deployar y al actualizar dependencias
**Hash:** ver `git log --grep "prune build leftovers"` (se registra en el mismo commit)
**Rama:** `main`
**Fecha:** 2026-10-21

### Cambios
| Archivo | Tipo | Descripción |
|---|---|---|
| `scripts/lib/docker-prune.sh` | nuevo | `prune_build_leftovers`: `docker image prune -f` (solo sin tag) + `docker builder prune --filter until=168h`. Saltea con `OLIVA_NO_PRUNE=1`. |
| `scripts/deploy.sh`, `scripts/deploy-staging.sh` | modificado | Lo llaman al final, después del `ps`. |
| `scripts/oliva/deps.sh` | modificado | `update` lo llama tras el commit del ciclo. |
| `docs/oliva/actualizaciones.md`, `docs/oliva/UPGRADING.md` | modificado | Sección "Espacio en disco" y notas de 1.1.1. |
| `agent-commits.md` | modificado | Esta entrada. |

### Justificación
Marcos preguntó si las actualizaciones periódicas engordan los proyectos. Medido el 2026-10-21 en su máquina: git no (un ciclo son decenas de KB de lockfile), Docker sí, y por cualquier rebuild, no solo por las actualizaciones. Había 4,1 GB de caché de build sin usar, 2,3 GB de imágenes recuperables y 1 GB de volúmenes anónimos huérfanos. En el VPS (droplet chico) cada `deploy.sh --build` deja ~750 MB de imagen de backend sin tag, así que el disco se llena solo con el tiempo.

Qué se limpia y qué no: solo imágenes **sin tag**. Las imágenes de plan B para cuando pecl está caído van taggeadas a propósito, y el prune nunca toca volúmenes. La caché de build se poda con antigüedad (7 días) en vez de entera, para que el próximo deploy no rebuildee todo desde cero; eso además importa cuando pecl está caído, porque una capa de extensiones cacheada evita descargarlas. Los volúmenes anónimos de dev quedan documentados como limpieza manual: borrarlos desde un script de deploy podría llevarse el `var/` de un stack que está parado pero que se quiere volver a levantar.

---

## [1.1.2–1.1.4] Migración de extensiones PECL → PIE (sacar el build de pecl.php.net)
**Hash:** `3c6fba2` (1.1.2, band-aid), `f7a1f9d` (1.1.3, PIE), `0c7435c` (apt sandbox + hadolint), `f32398a` (1.1.4, fix de orden)
**Rama:** `main`
**Fecha:** 2026-10-22

### Cambios
| Archivo | Tipo | Descripción |
|---|---|---|
| `backend/Dockerfile` | modificado | `amqp`/`apcu`/`xdebug` pasan de `install-php-extensions` (PECL) a `pie install` (imagen oficial `ghcr.io/php/pie:1.5.3-bin` montada en build-time, no queda en la imagen). `@composer`/`intl`/`opcache`/`pdo_pgsql`/`zip` siguen en `install-php-extensions` (pineado `mlocati/php-extension-installer:2.12.3`): no pasan por pecl. El RUN de PIE va al final del stage base y usa `-o APT::Sandbox::User=root`. |
| `docs/oliva/UPGRADING.md` | modificado | Secciones 1.1.2 (band-aid), 1.1.3 (PIE) y 1.1.4 (fix de orden). |
| `OLIVA_VERSION` | modificado | 1.1.1 → 1.1.4 (tres releases en el mismo día). |
| `agent-commits.md` | modificado | Esta entrada. |

### Justificación
`pecl.php.net` entró en phase-out (RFC "Adopt PIE, deprecate PECL", aceptada 2025-09-20) y su REST de metadata responde intermitente, rompiendo el build de backend con `install-php-extensions ... exit code 100`. El CI de los 3 repos estaba en rojo y, peor, no se podía buildear limpio desde cero (VPS, futuro bump de PHP).

**Por qué NO el camino "obvio" primero.** Se probó bumpear `install-php-extensions` a 2.12.3 (band-aid, 1.1.2): consulta el REST solo cuando hace falta, pero las extensiones con versión pineada se SIGUEN bajando de pecl.php.net. Verificó local por suerte (pecl arriba en ese momento) y el CI lo tiró igual en `xdebug`. Lección: para extensiones pecl-dependientes, bumpear el instalador no alcanza — hay que salir de pecl.

**Por qué PIE y por qué híbrido.** Al verificar contra Packagist (no de memoria: el corte de conocimiento era pre-ecosistema-PIE), los tres (`xdebug/xdebug`, `apcu/apcu`, `php-amqp/php-amqp`) ya existen como `php-ext` instalables con PIE, que baja de Packagist/GitHub y nunca toca pecl. Se migran esos tres; el resto (composer de getcomposer, y las bundled de PHP que se compilan del source) no toca pecl, así que queda en `install-php-extensions` — que además resuelve solo las libs de sistema. PIE no instala libs de SO: `amqp` necesitó `librabbitmq-dev` explícito.

**Dos gotchas no obvios, cada uno un release más (ver [[oliva-reference]] #12):**
1. **apt no podía escribir `/tmp`** (`mkstemp Permission denied` → exit 100): el `COPY --link php-extensions.txt /tmp/` le saca el sticky 1777 en el buildkit del CI, y el sandbox `_apt` falla. Fix: `apt-get -o APT::Sandbox::User=root update` (como hacía install-php-extensions por dentro). También se silenció hadolint DL3008/SC2086 en los RUN de PIE (no se pinean paquetes apt a propósito).
2. **`gcc: not found` (exit 127):** el RUN de PIE purga el toolchain al final; estaba ANTES del extension point del fork (`install-php-extensions $exts`), que necesita gcc para compilar. Un fork con algo en `php-extensions.txt` (finanzas-ong: bcmath) rompía; Oliva/crypto no, por tenerlo vacío. Fix: mover el RUN de PIE al final del stage base (1.1.4).

**Problema de método encontrado durante la ejecución:** la verificación local se hacía siempre sobre Oliva (con `php-extensions.txt` vacío), que no ejercita el extension point del fork — justo el caso que el gotcha #2 rompía. Lo atrapó el `verify` de finanzas-ong (con bcmath). Regla nueva: todo cambio al Dockerfile se prueba con una extensión en `php-extensions.txt`, no solo sobre Oliva. Propagado a los 3 repos con `sync.sh`, todos en verde (crypto saltea `schema` por el drift pgvector/HNSW conocido).

---

## [1.1.5] fix(security): parche PHP2Shell (PHP 8.3.36 / FrankenPHP 1.13.2) + cerrar el loop de verificación
**Hash:** `7c8bfd4` (parche), `e400f69` (untrack + UPGRADING), `2b3f09f` (release 1.1.5 + tag `v1.1.5`)
**Rama:** `main`
**Fecha:** 2026-10-22

### Cambios
| Archivo | Tipo | Descripción |
|---|---|---|
| `backend/Dockerfile` | modificado | Imagen base `dunglas/frankenphp:1.13.1-php8.3.35` → `1.13.2-php8.3.36`. Comentario del `FROM` ampliado con el porqué del bump (CVEs concretos, por qué 1.13.2 y no el mínimo `1.13.1-php8.3.36`, y que el fix exige RECREAR containers). |
| `.env.backend` | modificado | Eliminada `PHP_VERSION=8.3.13` (variable muerta). En su lugar, comentario que explica que la única fuente de verdad es el tag del `FROM` y por qué no debe volver. |
| `scripts/oliva/verify.sh` | modificado | Step nuevo `[php-version]` (corre justo después de `[up]`): compara `PHP_VERSION` del container contra el pin del Dockerfile y falla también si el tag no pinea un patch exacto. Header de pasos realineado. |
| `.gitignore` | modificado | Ignora `backend/config/reference.php`, con el porqué. |
| `backend/config/reference.php` | eliminado del índice | `git rm --cached` (queda en disco). Auto-generado por `cache:clear` solo para autocompletado del IDE. |
| `docs/oliva/UPGRADING.md` | modificado | Sección 1.1.5, la primera de esta serie con **4 pasos** de acción requerida en el fork, no "ninguna". |
| `OLIVA_VERSION` | modificado | 1.1.4 → 1.1.5. |
| `agent-commits.md` | modificado | Esta entrada. |

### Justificación
**El parche.** PHP 8.3.36 (21 Oct 2026, release marcada `security` en php.net) arregla PHP2Shell: CVE-2026-109618 y CVE-2026-109619, dos RCE sin autenticación, CVSS 9.2. Oliva y los dos forks corrían 8.3.35, una patch por debajo. No es un CVE de espectador: el 109619 es **estado de request stale que un worker reusa en el request siguiente**, y `frankenphp_prod` corre worker mode (`FRANKENPHP_CONFIG="import worker.Caddyfile"`).

**Por qué 1.13.2 y no el bump mínimo.** La nota de sesión anterior decía que no existía `1.13.1-php8.3.36` y que por eso había que mover FrankenPHP también. **Es falso** — se verificó contra Docker Hub que ese tag existe (pusheado 2026-10-21 17:45 UTC, 4 arquitecturas), así que el bump mínimo de solo-PHP era posible. Se eligió igual 1.13.2 porque es a su vez un security release y 2 de sus 4 vulns propias aplican a esta topología: fuga de fragmentos del input del cliente anterior vía `error_get_last()`/`libxml_get_errors()` en worker mode (GHSA-4gfw-9v29-gp9h) y thread pool ocupable por un cliente sin auth que encola requests y se desconecta (GHSA-fq24-r53r-xcx3). La tercera (arrays cíclicos a Go) es marginal y la "high" (embedded apps en temp dir predecible) no aplica: Oliva no usa embedded apps. Sus upgrade notes son todas de static builds (glibc 2.28, assets de macOS) → irrelevantes, acá se usa la imagen Docker. Riesgo de regresión bajo: patch dentro del mismo minor, y el warning histórico del `FROM` era por el tag **flotante** `1-php8.3`, no por un bump deliberado.

**Costo real del bump: una línea.** El ejercicio confirmó que la versión de PHP vive en **un solo lugar** (`backend/Dockerfile:6`) y que nada la duplica: no hay `ARG PHP_VERSION`, `composer.json` pide `php: >=8.3.31` (8.3.36 lo cumple → sin `composer update` ni lock tocado), y al ser el mismo minor el ABI de Zend no cambia, así que las extensiones por PIE (`apcu 5.1.28`, `amqp 2.2.0`, `xdebug 3.5.3`) recompilan igual. `deps.sh` lee la imagen por `awk` del `FROM` en vez de duplicar el dato, así que siguió funcionando sin tocarlo (verificado: `backend_base_image`, detección de EOL y `report_images`).

**La variable muerta era una trampa, no un valor viejo.** `.env.backend` tenía `PHP_VERSION=8.3.13`, que no consumía **nadie** (verificado sobre todo el árbol: ni Dockerfile, ni compose, ni código PHP, ni docs, ni el heredoc que arma el CI) y estaba 23 patches atrás. El riesgo no era el número desactualizado: es que se lee como "la versión de PHP del proyecto", así que en un apuro por un CVE se bumpea **eso**, se ve el número correcto y se cree que el fix se aplicó. Como `.env.backend` es un path SHARED, los dos forks cargaban la misma mentira. Se borra en el mismo commit del parche, a propósito: dejarla para después mantenía la trampa viva justo durante la ventana en que se la iba a consultar.

**El hueco estructural que expuso el ejercicio.** Este CVE lo detectó Marcos leyendo las noticias, no el tooling: `deps.sh due` es **por calendario**, no por advisory, y un 9.2 explotándose activamente no puede esperar el ciclo mensual. No se resuelve en este commit (requiere decidir una fuente de advisories y dónde engancharla), queda anotado como deuda.

Lo que **sí** se cierra acá es el otro hueco: `verify.sh` no tenía forma de asegurar que el PHP que corre sea el que se pineó. En este CVE puntualmente, un build verde no prueba nada — el fix no toma efecto en procesos vivos, así que un `up` que reusa un container deja los workers sirviendo el PHP viejo, sin dejar rastro. Es el paso que más fácil se saltea en un apuro. El step `[php-version]` lo asserta, y de paso falla si el tag deja de pinear un patch exacto, convirtiendo en check automático la convención que hoy vive solo en un comentario (y cuya violación ya rompió Mercure una vez). Mismo criterio que el step `[mercure]`: cada incidente pasado se vuelve una assertion.

**Nota de operación:** el restart ya estaba cubierto — `scripts/deploy.sh` hace `down --remove-orphans` antes del `up`, así que no quedan workers vivos con el PHP viejo. Un `up -d` suelto sobre un tag cambiado también recrea; el peligro es solo un `restart` del servicio, que no.

**Hallazgo lateral: `backend/config/reference.php` estaba trackeado y cada build lo reescribía.** Lo expuso el propio `verify.sh` de este parche, que dejó el árbol sucio. Es auto-generado (`cache:clear`, vía `auto-scripts` → `post-install-cmd`) y solo sirve para el autocompletado del IDE: nada en runtime lo lee. Es la misma clase de problema que los environments de Bruno ya documentados en `CLAUDE.md` —archivo trackeado que una herramienta reescribe sola—, pero acá con un costo extra: `release.sh` exige árbol limpio, así que un archivo que se ensucia en cada build bloquea el release justo cuando se quiere publicar rápido. Encima la copia que estaba en git quedó **stale**: listaba `when@development`, un entorno que el proyecto dejó de usar cuando `APP_ENV` pasó a nombres cortos (PASO 1.1), así que lo versionado era además incorrecto. Se destrackeó en vez de commitear la regeneración (volvería a ensuciarse en el build siguiente). Verificado antes de sacarlo del índice que se regenera: borrado del disco + `cache:clear` lo recrea idéntico en tamaño (1577 líneas).

**Deuda que este ejercicio expuso y NO se resolvió acá:** `deps.sh due` avisa **por calendario**, no por advisory. Un CVSS 9.2 explotándose activamente no puede esperar el ciclo mensual, y este lo detectó Marcos leyendo las noticias, no el tooling. No se improvisó un fix en el commit del parche a propósito: requiere decidir una fuente de advisories (GitHub Security Advisories, feed de php.net) y dónde engancharla, y mezclarlo con un parche urgente habría sido meter una decisión de diseño sin discutir en un commit que tiene que ser revisable de un vistazo.

## [deps 1er ciclo] chore(deps): techo `^0.4` en mercure-bundle + update dentro de rangos (a medias)
**Hash:** `98c19fd` (techo), `46e661f` (update), merge `aa3b6c9`
**Rama:** `chore/deps-2026-10-22` → `main` (local, sin pushear)
**Fecha:** 2026-10-22

### Cambios
| Archivo | Tipo | Descripción |
|---|---|---|
| `backend/composer.json` | modificado | `symfony/mercure-bundle` `"*"` → `"^0.4"` (98c19fd). Después `deps.sh update` subió el resto dentro de rangos (46e661f). |
| `backend/composer.lock` | modificado | ~50 paquetes: Symfony 7.4.21, doctrine/orm 3.7.5, dbal 4.5.0, phpunit 12.5.40, `mercure-bundle` 0.4.3. |
| `frontend/package.json`, `frontend/yarn.lock` | modificado | `yarn upgrade` dentro de rangos; `package.json` quedó reordenado alfabéticamente (ruido, sin cambio funcional). |
| `agent-commits.md` | modificado | Esta entrada. |

### Justificación
**Primer ciclo de mantenimiento de Oliva.** Cierra las 2 CVE del `composer audit` (`http-foundation` ReDoS, `yaml` recursión sin tope): ambas se tapan con bumps dentro de rango (→ 7.4.21). `verify.sh` 8/8 y `composer audit` limpio.

**Problema no previsto: el primer `update` rompió el build.** `composer.json` tenía `"*"` en `mercure-bundle` (también en `doctrine-migrations-bundle` y `maker-bundle`). Para composer cualquier versión está "en rango", así que `deps.sh update` lo subió 0.4.2 → **0.6.1**, aunque `report` lo marcaba `⇑` (manual). 0.6.1 exige claims `iss`/`sub`/`client_id` (RFC 9068) en `mercure.yaml` y el build de prod caía en `cache:clear` (`verify.sh`: 6 de 8 en FAIL). El `report` y el `update` no coinciden porque el primero compara contra el lock y el segundo contra el constraint.

**Decisión: techo, no fix de config.** Se descartó arreglar `mercure.yaml` en el mismo ciclo: toca el corazón de Oliva, requiere decidir qué claims poner y afecta a los forks (es la deuda "Mercure en modo compat 8"). El doc pide un commit por salto, así que el 0.6 va aparte. El bundle no se puede sacar: Oliva no lo usa (`live.php` publica con HTTP crudo), pero **ambos forks inyectan `HubInterface`** (finanzas-ong en `NotificationPublisher`, crypto-pulse en 3 clases) y un fork no edita archivos de Oliva.

**Efecto lateral a tener presente:** `"bump-after-update": true` en `composer.json` reescribe los constraints a lo instalado (`"*"` → `">=x"`, `^2.18` → `^2.19.1`), así que se pierden techos; uno explícito como `^0.4` sí sobrevive. Quedan otros `"*"` sin techo. Los forks tienen `"*"` en mercure-bundle: su próximo `composer update` rompe igual.

**Pendiente del ciclo (no hecho):** Node 20→24 (EOL), RabbitMQ 3→4 (EOL), notas en `UPGRADING.md`, `release.sh`, push y sync a forks. Fuera de alcance a propósito: pg15→18, php8.3→8.5, 6 majors de frontend, actions.

## [1.2.0] chore(deps): cierre del 1er ciclo — Node 24 + RabbitMQ 4 (ambos EOL) y release
**Hash:** `d409ce9` (node), `fb0370b` (rabbitmq), `e146283` (UPGRADING), `8304522` (release)
**Rama:** `main` (directo; los saltos de imagen no fueron por `chore/deps-*`)
**Fecha:** 2026-10-22

### Cambios
| Archivo | Tipo | Descripción |
|---|---|---|
| `frontend/Dockerfile` | modificado | Imagen base `node:20-slim` → `node:24-slim` (d409ce9). |
| `docker-compose.yml` | modificado | `rabbitmq:3-management` → `rabbitmq:4-management` (4.4.0) (fb0370b). |
| `docs/oliva/UPGRADING.md` | modificado | Sección 1.2.0: acción requerida por fork + qué cambió (e146283). |
| `OLIVA_VERSION` | modificado | `1.1.5` → `1.2.0` (8304522, vía `release.sh`). |
| `agent-commits.md` | modificado | Esta entrada. |

### Justificación
**Cierra los pendientes que el 1er ciclo dejó anotados** (ver entrada anterior): Node 20→24 y RabbitMQ 3→4, ambos por EOL, más notas y release. Un commit por salto, como pide el protocolo — no un bump masivo.

**Node: por qué 24 y no 26.** Node 20 quedó EOL el 2026-04-30. Se eligió 24 ("Krypton") por ser **Active LTS**; 26 salió este mes como *Current* y todavía no es LTS. Un framework base no estrena línea no-LTS: el costo de equivocarse lo pagan todos los forks. Swap limpio, `verify.sh` 8/8 con el `vite build` de prod sobre node 24.

**RabbitMQ: el salto con trampa, y es la razón por la que esto necesitó `UPGRADING.md` sí o sí.** 3.x está EOL desde 2024-09. Pero un nodo 4.0 levantado sobre un volumen poblado por un 3.x **se niega a bootear** si quedan *required feature flags* sin habilitar, y **no deja rastro obvio** — parece que el container simplemente no arranca. El `enable_feature_flag all` hay que correrlo **antes** del swap, con el nodo todavía en 3.13. Dato que evita un paso intermedio: el tag viejo `3-management` ya resolvía a 3.13.7, que es la única versión desde la que 4.0 soporta upgrade directo. Un fork que nunca activó el profile `queues` no tiene nada que hacer (un nodo 4.0 fresco nace con todos los flags enabled), y por eso la nota está escrita por caso y no como un paso único.

**Además, 4.0 eliminó las classic mirrored queues.** Se verificó que no afecta: los transports de ejemplo de Oliva (`ingest`/`enrich`/`failed`) son classic queues normales, no mirrored. Se dejó dicho igual en `UPGRADING.md` porque un fork sí pudo haber definido HA policies propias.

**Por qué el release es parte de esta entrada y no un trámite:** `release.sh` se niega a publicar una versión sin su sección en `UPGRADING.md`. En un salto como el de RabbitMQ ese gate es lo único que separa a un fork con datos de un nodo que no bootea — el canal hacia los forks es la entrega, no un anexo.

**No verificado por imposibilidad:** el procedimiento de feature flags sobre un volumen 3.x real. Se validó el camino limpio (nodo 4.4.0 healthy por `rabbitmq-diagnostics ping`, worker de Messenger conectando por AMQP y declarando colas). AMQP 0-9-1 no cambió entre 3 y 4, así que `php-amqp` no necesitó bump.

## [PASO 3.1] feat(deps): el aviso por advisory — audit de CVEs fuera del ciclo + Trivy para imágenes base
**Hash:** `14aaeaa`
**Rama:** `feat/advisory-audit`
**Fecha:** 2026-10-22

### Cambios
| Archivo | Tipo | Descripción |
|---|---|---|
| `scripts/oliva/deps.sh` | modificado | Subcomando `audit` (solo CVEs: `composer audit` + `yarn audit` + Trivy sobre las imágenes base) y `scan-images` (solo Trivy, lo usa el CI). `due` ahora reporta también la frescura del audit (umbral `OLIVA_AUDIT_DUE_DAYS`, default 7). `report` incluye `report_trivy`. Refactor: extracción de imágenes base a `base_images()` (compartido por `report_images` y `scan_images`). Constantes `AUDIT_DUE_DAYS`, `AUDIT_STATE`, `TRIVY_VERSION` (0.72.0). |
| `.github/workflows/ci.yml` | modificado | Job `image-scan` (report-only, `|| true`) que corre `deps.sh scan-images`. Opt-out por fork: `OLIVA_CI_SKIP=trivy`. Usa el mismo Trivy pinneado vía `docker run`, no la `trivy-action`. |
| `.gitignore` | modificado | `.oliva/` (estado local del audit, por-repo). |
| `.trivyignore` | nuevo | Plantilla para CVEs aceptados/infixables de las imágenes base. |
| `CLAUDE.md` | modificado | "Chequeos de sanidad": `deps.sh due` reporta las dos cadencias; mención de `deps.sh audit`. |
| `docs/oliva/actualizaciones.md` | modificado | Sección nueva "El aviso por advisory": modelo de capas, una-fuente-por-capa, detalles operativos de Trivy. |
| `docs/oliva/UPGRADING.md` | modificado | Sección 1.3.0 (acción requerida + qué cambió). |
| `agent-commits.md` | modificado | Esta entrada. |

### Justificación
**El gap que cierra:** el ciclo de deps (`report`/`update`) corre cada ~45 días por **frescura**; un CVE crítico no espera. Y había una capa sin cubrir por ninguna fuente: el SO y los binarios **dentro** de las imágenes base (OpenSSL del postgres, el binario de Caddy en FrankenPHP). `composer`/`yarn audit` solo ven los *paquetes* de la app.

**Decisión de diseño — una fuente por capa, no varias apiladas.** Las bases de advisories de paquetes se alimentan entre sí (GHSA ⟵ NVD + FriendsOfPHP; Packagist ⟵ FriendsOfPHP + GHSA; OSV ⟵ GHSA), así que apilar GHSA + OSV + Packagist sobre el mismo `composer.lock` es redundancia, no robustez (mismos hallazgos, distinto ID). La robustez viene de cubrir capas distintas: PHP (`composer audit`), JS (`yarn audit`), imágenes (**Trivy**). Se descartó osv-scanner (no hay gap en la capa de paquetes) y la API de NVD/OSV por-request (online, rate-limited; Trivy con DB local encaja mejor con el flujo de sesión/CI).

**Mecanismo del aviso:** `deps.sh audit` (a demanda, solo CVEs) + gate barato y offline en `deps.sh due` (lee la fecha de `.oliva/audit-state`, umbral 7 días). Fiel a "el recordatorio vive en el flujo": el chequeo de inicio de sesión de siempre ahora surfacea el audit sin red.

**Trivy:** corre como contenedor pinneado (`aquasec/trivy:0.72.0` — nada que instalar en el host) sobre el **ref base** fijado (no la imagen prod buildeada: ahí viven casi todos los CVEs de imagen y no hace falta buildear), filtra HIGH/CRITICAL **con fix** (`--ignore-unfixed`) y lee `.trivyignore`. Pin ≥ 0.71.1 obligatorio: la v0.69.4 estuvo comprometida (incidente de supply-chain 2026-03, que también afectó tags de `trivy-action` → por eso en CI se usa `docker run` con el pin, no la action). En CI el job es report-only a propósito: un CVE de imagen base puede ser infixable hasta que el upstream rebuildee; no se quiere `main` en rojo perpetuo.

**Dos bugs propios que destapó la corrida real** (no previstos en el plan), ambos de interacción con `set -e`: (1) `[[ cond ]] && rc=1` abortaba el loop en la 1ª imagen sin findings (short-circuit → lista en falso → `set -e`); (2) el pipeline `trivy ... | sed` con `--exit-code 1` + `pipefail` abortaba en la 1ª imagen *con* findings. Por eso la 1ª corrida solo escaneó `caddy`. Fix: capturar salida+estado con `out="$(...)" || status=$?` y un `if` explícito, nunca el idiom `&&`. Verificado: scan de las 5 imágenes completo, exit 1 con findings (caddy 26+68, node 3, pgvector 29+26, rabbitmq 4; FrankenPHP 0 — ya parchado en 1.1.5).

## [docs] README — sección "Built for agentic development"
**Hash:** `b6f83df`
**Rama:** `main`
**Fecha:** 2026-10-23

### Cambios
| Archivo | Tipo | Descripción |
|---|---|---|
| `README.md` | modificado | Sección nueva, hermana de `## Staying patched`: qué guardrails para agentes shipea Oliva con el código. |
| `agent-commits.md` | modificado | Esta entrada. |

### Justificación
**Qué hace distinto a la sección:** encuadra los guardrails **por nivel de garantía**, no como una lista plana de features. Ownership (`owned-paths.txt`) se nombra explícitamente como **convención, no candado** — *"git won't stop you"* —; `release.sh` y `project-guard.sh` se nombran como **gates reales** (abortan); `deps.sh due` como **cadencia**. Mezclar los tres niveles vendería como garantía algo que no lo es, y la primera vez que un fork editara un `owned-path` sin que pasara nada, el README quedaría desmentido.

**Omisiones deliberadas:** no menciona `rules-claude.md` ni el `CLAUDE.md` raíz de la máquina. Son setup personal y **no bajan a ningún fork**; nombrarlos en el README público daría a entender que son parte de lo que se clona.

**Consecuencia a tener presente:** `README.md` es **SHARED**, así que esta sección **no baja por sync**. Si se la quiere en los READMEs de los forks hay que adaptarla a mano, uno por uno (no pedido aún).

Solo-docs → no dispara CI, gracias al `paths-ignore` de `a7c3267`.

## [docs] Epic de la capa agéntica + ítem 5 del roadmap
**Hash:** `87632ca`
**Rama:** `main`
**Fecha:** 2026-10-23

### Cambios
| Archivo | Tipo | Descripción |
|---|---|---|
| `docs/roadmap/epics/E-capa-agentica.md` | nuevo | Plan completo de los 2 ejes (CLI `./oliva` + migración a `AGENTS.md`): decisiones cerradas, diseño del CLI, 4 fases con gates, texto obligatorio de `UPGRADING.md` 1.4.0, riesgos. |
| `docs/roadmap.md` | modificado | Ítem 5 "Agent layer: one entry point, vendor-neutral spec" + diagrama de secuencia actualizado. |
| `agent-commits.md` | modificado | Esta entrada. |

### Justificación
**El hallazgo que define el diseño, y la razón de que esto se planificara antes de ejecutar:** el rename directo de `CLAUDE.md` a `AGENTS.md` **rompe, y rompe mudo**. Verificado contra la doc oficial: Claude Code lee `AGENTS.md` nativo desde v2.1.277, pero **solo si no hay `CLAUDE.md` ni `CLAUDE.local.md` en el cwd ni en ningún directorio por encima**. Como existe uno por encima de los repos, taparía el `AGENTS.md` de cada proyecto y el agente dejaría de leer la guía operativa **sin ningún síntoma**. De ahí que la solución no sea el rename limpio sino `AGENTS.md` (contenido real) + stub `CLAUDE.md` de una línea con `@AGENTS.md`. El symlink se descartó por no ser Windows-safe: git lo checkoutea como texto plano salvo `core.symlinks`.

**Por qué el CLI no se justifica por ergonomía.** El argumento inicial (ahorro de tipeo) era débil y se corrigió durante el análisis: `scripts/oliva/deps.sh due` → `oliva deps due` no vale el churn. Lo que sí lo vale es que hoy **los docs referencian paths** y el doc agéntico es **SHARED**, así que mover, partir o renombrar un script es un diff en un archivo que cada fork también edita → superficie de conflicto en todos. Un `oliva <verbo>` estable es una **capa de indirección**: las internals se mueven sin tocar los docs compartidos. Es el mismo razonamiento que ya justifica `owned-paths.txt`, y es lo que hace al ítem 5 independiente del friction log del ítem 1.

**Hallazgo lateral que mejora el diseño:** el stub `CLAUDE.md` se declara **OLIVA-owned**. Nunca cambia y ningún fork lo edita → conflicto cero para siempre, y la superficie SHARED queda solo en `AGENTS.md` (igual que hoy, no empeora).

**Guardrail escrito por duplicado, a propósito:** los comandos de operación (`deploy`/`down`) son pass-throughs sin flags nuevos. Está en el epic **y** en el roadmap porque es la decisión más fácil de erosionar después, y el roadmap es donde alguien va a ir a buscar permiso para agregar `--cron`. Los flags son el ítem 3 y esperan la señal del ítem 1.

**Alcance de la planificación:** las fases 1-3 quedaron con gates verificables (comparar exit codes, un `grep` de completitud con allowlist de 4 archivos, `/context` para confirmar que el import carga) justamente porque el modo de falla es mudo. La fase 4 (forks) se marcó como **criterio, no mecánica**: resolver merges sobre un archivo SHARED no se delega a un checklist.

## [1.4.0] feat: capa agéntica — CLI `./oliva` + migración a `AGENTS.md` (vendor-neutral)
**Commits:** `0fb3a68` feat(cli) · `9ac83f3` feat(agents) · `e4ca9ec` docs(upgrading) · `e644e09` release
**Rama:** `main`
**Fecha:** 2026-10-23
**Ejecuta el plan de:** `docs/roadmap/epics/E-capa-agentica.md` (entrada `87632ca`). Release `v1.4.0`.

### Cambios
| Archivo | Tipo | Descripción |
|---|---|---|
| `oliva` | nuevo | Entry point del framework. Dispatcher puro (`exec` preserva args/stdin/stdout/exit) sobre `scripts/oliva/*.sh` y `scripts/*.sh`; única lógica propia: `doctor` (chequeos read-only que sobreviven a cada paso). No va al PATH. |
| `CLAUDE.md` | nuevo | Stub de 1 línea `@AGENTS.md` (import de Claude Code). OLIVA-owned. |
| `CLAUDE.md` → `AGENTS.md` | renombrado (`git mv`) | La guía operativa pasa al formato abierto. `git mv` preserva rename-detection para que el fork merjee limpio. Self-refs internas actualizadas; bloque de 7 chequeos de sanidad reemplazado por `./oliva doctor`. |
| `claude-commands.md` → `agent-commands.md` | renombrado (`git mv`) | Título `# Agent Commands`; nota de prefijo configurable. Los triggers `claude <x>` quedan igual (es frase-gatillo, no herramienta). |
| `rules-claude.md` → `AGENTS.local.md` | renombrado (`mv`, gitignored) | + entrada en `.gitignore`. |
| `scripts/oliva/owned-paths.txt` | modificado | `oliva` y `CLAUDE.md` marcados OLIVA-owned; comentario SHARED actualizado a `AGENTS.md`/`agent-commands.md`. |
| `README.md`, `docs/oliva/actualizaciones.md`, `docs/qa-y-staging.md`, `docs/concepts.md`, `scripts/deploy.sh`, `scripts/oliva/sync.sh`, `docs/roadmap/epics/E-seeding-layer.md` | modificado | Barrido de cross-refs `CLAUDE.md`→`AGENTS.md` / `claude-commands.md`→`agent-commands.md`. |
| `docs/oliva/UPGRADING.md` | modificado | Sección `## 1.4.0` (gate del release): "Acción requerida en el fork" + "Qué cambió". |
| `OLIVA_VERSION` | modificado | `1.3.0` → `1.4.0` (vía `./oliva release`). Tag anotado `v1.4.0`. |
| `agent-commits.md` | modificado | Esta entrada. |

### Justificación
**Por qué el stub `CLAUDE.md` y no el rename limpio** (lo que define todo el diseño): Claude Code lee `AGENTS.md` nativo pero **solo si no hay `CLAUDE.md`/`CLAUDE.local.md` en el cwd ni en ningún padre**; como `/home/marcos/CLAUDE.md` vive por encima de todos los repos, un `AGENTS.md` a secas quedaría tapado y el agente dejaría de leer la guía **sin ningún síntoma**. El stub (import `@AGENTS.md` en primera línea sin fence) resuelve el choque sin duplicar contenido, y se declara OLIVA-owned → conflicto cero para siempre, la superficie SHARED queda solo en `AGENTS.md`.

**Por qué el CLI vale el churn:** no es ergonomía (eso se descartó en el análisis) sino una **capa de indirección**. Los docs SHARED referencian paths de scripts; mover/partir/renombrar un script era un diff en archivo compartido → conflicto en cada fork. `oliva <verbo>` estable desacopla las internals de los docs. Mismo razonamiento que `owned-paths.txt`.

**`doctor` y `set -e`:** read-only por diseño, ningún paso puede matar al comando (helper `step()` captura cada fallo y sigue) — tiene que correr con Docker abajo, que es justo cuando más se lo necesita al arrancar. Verificado en sesión posterior: con containers abajo, el paso de migraciones informó el fallo y el resto siguió.

**Gates verificados antes del release** (el modo de falla es mudo, así que no alcanzaba con revisar el código): output idéntico CLI vs script directo, bit ejecutable (`100755`), propagación de exit codes, resiliencia de `doctor`, `verify.sh` full PASS, barrido `grep` de cross-refs con allowlist, y **gate 13** — `/context all` en sesión fresca confirmó que cargan tanto el stub `CLAUDE.md` (14 tokens) como `AGENTS.md` (11k). 

**Fuera del repo pero parte del trabajo:** `/home/marcos/CLAUDE.md` (spec de `claude new project`) se actualizó a la convención nueva en una sesión posterior — no se versiona (no es repo). La **Fase 4** (sync de forks a 1.4.0) queda pendiente, explícitamente no-mecánica, una sesión por fork.


## [1.4.1] fix: extension point de PHP por bind-mount — el CI rojo de finanzas-ong desde 1.1.0
**Commits:** `324c448` fix(backend) · `9e627c5` feat(verify) · `e05bf71` feat(doctor) · `db18c2a` docs(agents) · `e73607d` docs(upgrading) · `f9930cf` release
**Rama:** `main`
**Fecha:** 2026-10-23
**Origen:** diagnóstico `/home/marcos/diagnose.md` + auditoría de "puntos sensibles para forks" pedida por Marcos. Release `v1.4.1`.

### Cambios
| Archivo | Tipo | Descripción |
|---|---|---|
| `backend/Dockerfile` | modificado | `php-extensions.txt` entra por `RUN --mount=type=bind` en vez de `COPY --link ... /tmp/`. Líneas con `/` (`vendor/paquete:versión`) se instalan con PIE dentro del RUN de PIE. `APT::Sandbox::User=root` queda como defensa en profundidad. `DL4006` silenciado en los dos RUN con pipe. |
| `scripts/oliva/verify.sh` | modificado | Paso `[ci-build]`: rebuild del backend con un builder `docker-container` (`oliva-ci`). Solo si `php-extensions.txt` tiene extensiones. |
| `oliva` | modificado | `doctor` muestra el último run del CI en `main` (solo con `gh` instalado y logueado; timeout de 10 s). |
| `AGENTS.md` | modificado | Deuda: worker en prod (ya no es teórica), profiles en deploy, constraints sin techo. |
| `docs/oliva/UPGRADING.md` | modificado | Sección `## 1.4.1`. |
| `OLIVA_VERSION` | modificado | `1.4.0` → `1.4.1`. |
| `agent-commits.md` | modificado | Esta entrada. |

### Justificación
**Tres versiones apuntaron a la causa equivocada.** Los 9 runs rojos de finanzas-ong (sync 1.1.2 → 1.4.0) tienen el mismo error, `mkstemp /tmp/apt.sig.* Permission denied`, desde el primer push con el extension point. 1.1.2–1.1.4 (PECL→PIE) arreglaron problemas reales, pero no este: se validaron en Oliva y crypto-pulse, con `php-extensions.txt` vacío, donde el RUN del fork es no-op.

**La causa no es "el buildkit del CI" en general, es el driver.** `COPY --link` a un directorio existente deja `/tmp` en 755 con el driver buildx `docker-container` (el de `setup-buildx-action`, buildkit v0.33); con el driver `docker` local (buildkit v0.23) queda en 1777. Reproducido con un Dockerfile de 3 líneas. Por eso "local verde, CI rojo" y por eso `verify.sh` no lo podía ver.

**Por qué bind-mount y no las opciones del diagnóstico:** (A) apt global como root parchea el síntoma y deja /tmp roto para cualquier otra herramienta; (C) `chmod 1777` es igual de local. El bind-mount no crea capa, así que no hay nada que rompa /tmp, y de paso el archivo no queda en la imagen.

**Por qué `[ci-build]` es condicional:** Marcos pidió que el framework siga sirviendo para desarrollos simples. El driver local y el del CI difieren justo en el camino del extension point, así que el paso solo corre cuando el fork lo usa; sin extensiones cuesta cero. Verificado que sobre finanzas-ong sin fix **falla** (antes, verde).

**Sintaxis PIE en el extension point:** el comentario del archivo invitaba a `redis-6.2.0`, que sigue bajando de pecl.php.net — la dependencia que Oliva abandonó en 1.1.2. No se cambió el `php-extensions.txt` de Oliva: es del fork, y editar su cabecera le generaría conflicto a todo fork que haya agregado líneas.

**Descartado con pruebas** (para no reabrirlo): la purga `--auto-remove` del RUN de PIE no borra libs de runtime (gd/gmp andan); con pecl.php.net caído, las extensiones bundled instalan igual (el `Updating channel` falla y sigue).

## [1.4.2] fix: cron en prod vía `COMPOSE_PROFILES` del host + aviso si falta (#7 de la auditoría)
**Hash:** `1ad0625`
**Rama:** `main`
**Fecha:** 2026-10-23
**Origen:** auditoría "puntos sensibles para forks" (#7). Va en la release 1.4.2 (sin publicar).

### Cambios
| Archivo | Tipo | Descripción |
|---|---|---|
| `scripts/lib/cron-guard.sh` | nuevo | `warn_if_cron_inactive`: si `backend/scheduler/crontab` tiene tareas y `config --services` no incluye `scheduler`, imprime `!! CRON INACTIVO` con el fix. No aborta. Silencioso si Compose no resuelve la config. |
| `scripts/deploy.sh` | modificado | Sourcea el guard y lo llama al final. El mensaje final ya no pide `--profile cron` (editar el script). Comentario del `down` corregido: el `up` sí respeta los profiles del `.env`. |
| `scripts/deploy-staging.sh` | modificado | Sourcea y llama el guard al final. |
| `AGENTS.md` | modificado | Tabla de servicios, bloque shared-infra y runbook: `COMPOSE_PROFILES` en el `.env` del host es el mecanismo. Sale el ítem de cron de la deuda de profiles. |
| `.env.example` | modificado | Aclara que en prod vale el `.env` del host y que el deploy avisa. |
| `docs/oliva/UPGRADING.md` | modificado | Sección `## 1.4.2 — sin publicar`. |
| `agent-commits.md` | modificado | Esta entrada (commit aparte, pedido después del commit del fix). |

### Justificación
**El mensaje del script le pedía al fork romper la regla de propiedad.** `deploy.sh` es OLIVA-owned; "agregá `--profile cron` al up" solo se cumple editándolo, y el próximo sync lo pisa. El mecanismo correcto ya existía y estaba verificado (`config --services` respeta `COMPOSE_PROFILES` del `.env`): faltaba decirlo.

**Por qué un aviso y no solo docs:** el modo de falla es silencioso (el scheduler no levanta y ninguna tarea corre, sin error). finanzas-ong necesita cron en prod (auto-confirm de pagos, reintentos de notificaciones) y su `.env.example` tiene `COMPOSE_PROFILES=` vacío: exactamente el caso.

**Por qué preguntarle a Compose y no parsear el `.env`:** `config --services` resuelve lo mismo que el `up` (`.env`, variable exportada, overlays). Un parser propio driftearía.

**Por qué no aborta:** un fork puede tener el crontab lleno y elegir no correr cron en un host puntual; el deploy no debe fallar por eso. Si Compose falla al resolver, no se avisa (sería un falso positivo).

**Descartado:** sumar el aviso a `./oliva doctor`. En dev no tener `cron` activo es normal y sería ruido (decisión de Marcos).

## [1.4.2] fix: `down` con `--profile '*'` en los scripts de deploy (#8 de la auditoría)
**Hash:** `642fd13`
**Rama:** `main`
**Fecha:** 2026-10-23
**Origen:** auditoría "puntos sensibles para forks" (#8). Prerequisito del worker de prod (#6). Release 1.4.2 (sin publicar).

### Cambios
| Archivo | Tipo | Descripción |
|---|---|---|
| `scripts/deploy.sh` | modificado | `COMPOSE_PROFILES=cron ... down` → `... --profile '*' down --remove-orphans`. Comentario reescrito con el porqué. |
| `scripts/deploy-staging.sh` | modificado | Ídem. |
| `scripts/down.sh` | modificado | Ídem. |
| `scripts/down-staging.sh` | modificado | Ídem. |
| `AGENTS.md` | modificado | Sale la deuda "profiles en los scripts de deploy"; queda una nota de por qué `'*'`. La deuda del worker ya no depende de esto. |
| `docs/oliva/UPGRADING.md` | modificado | Ítem en la sección `## 1.4.2 — sin publicar`. Sin acción para el fork. |
| `agent-commits.md` | modificado | Esta entrada (commit aparte). |

### Justificación
**El disparador es el overlay, no el profile solo.** Con Compose 2.26, un `down` sin el profile activo deja corriendo (sin error) a un servicio con `profiles:` **cuando un overlay lo redefine**, como hace `prod.yml` con `scheduler`/`rabbitmq`. Con un solo archivo, el `down` sí lo baja: las primeras pruebas mínimas daban falso negativo. Con el overlay: `down` sin profile deja `scheduler`+`rabbitmq`; el `COMPOSE_PROFILES=cron` de antes deja `rabbitmq` (la variable **reemplaza** los profiles del `.env`, no suma); `--profile '*'` no deja nada. Verificado también con el `down.sh` real contra un stack busybox que imita los 3 archivos de prod, con `COMPOSE_PROFILES=queues,cron` y vacío.

**Por qué `'*'` y no listar los profiles:** una lista fija (`cron,queues`) se pudre en cuanto un fork agrega un servicio con profile propio, y el script es OLIVA-owned: el fork no la puede extender.

**Por qué es inocuo con shared-infra:** `'*'` mete en scope a `database`/`rabbitmq` desactivados (`disabled-in-shared-infra`). En ese project no tienen containers, así que el `down` no los toca; sin `-v` no se borra ningún volumen.

**Impacto real hoy:** latente. En shared-infra no corre nada de `queues` en prod (`rabbitmq` desactivado, sin `worker`), así que ningún fork lo sufría todavía. Le iba a pegar al `worker` de #6.
