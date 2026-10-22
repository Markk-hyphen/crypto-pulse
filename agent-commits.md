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
**Hash:** ver `git log --grep "PHP2Shell"` (se registra en el mismo commit)
**Rama:** `main`
**Fecha:** 2026-10-22

### Cambios
| Archivo | Tipo | Descripción |
|---|---|---|
| `backend/Dockerfile` | modificado | Imagen base `dunglas/frankenphp:1.13.1-php8.3.35` → `1.13.2-php8.3.36`. Comentario del `FROM` ampliado con el porqué del bump (CVEs concretos, por qué 1.13.2 y no el mínimo `1.13.1-php8.3.36`, y que el fix exige RECREAR containers). |
| `.env.backend` | modificado | Eliminada `PHP_VERSION=8.3.13` (variable muerta). En su lugar, comentario que explica que la única fuente de verdad es el tag del `FROM` y por qué no debe volver. |
| `scripts/oliva/verify.sh` | modificado | Step nuevo `[php-version]` (corre justo después de `[up]`): compara `PHP_VERSION` del container contra el pin del Dockerfile y falla también si el tag no pinea un patch exacto. Header de pasos realineado. |
| `agent-commits.md` | modificado | Esta entrada. |

> El bump de `OLIVA_VERSION` y la sección de `docs/oliva/UPGRADING.md` van en el commit de release (`release.sh 1.1.5`), que es el paso siguiente.

### Justificación
**El parche.** PHP 8.3.36 (21 Oct 2026, release marcada `security` en php.net) arregla PHP2Shell: CVE-2026-109618 y CVE-2026-109619, dos RCE sin autenticación, CVSS 9.2. Oliva y los dos forks corrían 8.3.35, una patch por debajo. No es un CVE de espectador: el 109619 es **estado de request stale que un worker reusa en el request siguiente**, y `frankenphp_prod` corre worker mode (`FRANKENPHP_CONFIG="import worker.Caddyfile"`).

**Por qué 1.13.2 y no el bump mínimo.** La nota de sesión anterior decía que no existía `1.13.1-php8.3.36` y que por eso había que mover FrankenPHP también. **Es falso** — se verificó contra Docker Hub que ese tag existe (pusheado 2026-10-21 17:45 UTC, 4 arquitecturas), así que el bump mínimo de solo-PHP era posible. Se eligió igual 1.13.2 porque es a su vez un security release y 2 de sus 4 vulns propias aplican a esta topología: fuga de fragmentos del input del cliente anterior vía `error_get_last()`/`libxml_get_errors()` en worker mode (GHSA-4gfw-9v29-gp9h) y thread pool ocupable por un cliente sin auth que encola requests y se desconecta (GHSA-fq24-r53r-xcx3). La tercera (arrays cíclicos a Go) es marginal y la "high" (embedded apps en temp dir predecible) no aplica: Oliva no usa embedded apps. Sus upgrade notes son todas de static builds (glibc 2.28, assets de macOS) → irrelevantes, acá se usa la imagen Docker. Riesgo de regresión bajo: patch dentro del mismo minor, y el warning histórico del `FROM` era por el tag **flotante** `1-php8.3`, no por un bump deliberado.

**Costo real del bump: una línea.** El ejercicio confirmó que la versión de PHP vive en **un solo lugar** (`backend/Dockerfile:6`) y que nada la duplica: no hay `ARG PHP_VERSION`, `composer.json` pide `php: >=8.3.31` (8.3.36 lo cumple → sin `composer update` ni lock tocado), y al ser el mismo minor el ABI de Zend no cambia, así que las extensiones por PIE (`apcu 5.1.28`, `amqp 2.2.0`, `xdebug 3.5.3`) recompilan igual. `deps.sh` lee la imagen por `awk` del `FROM` en vez de duplicar el dato, así que siguió funcionando sin tocarlo (verificado: `backend_base_image`, detección de EOL y `report_images`).

**La variable muerta era una trampa, no un valor viejo.** `.env.backend` tenía `PHP_VERSION=8.3.13`, que no consumía **nadie** (verificado sobre todo el árbol: ni Dockerfile, ni compose, ni código PHP, ni docs, ni el heredoc que arma el CI) y estaba 23 patches atrás. El riesgo no era el número desactualizado: es que se lee como "la versión de PHP del proyecto", así que en un apuro por un CVE se bumpea **eso**, se ve el número correcto y se cree que el fix se aplicó. Como `.env.backend` es un path SHARED, los dos forks cargaban la misma mentira. Se borra en el mismo commit del parche, a propósito: dejarla para después mantenía la trampa viva justo durante la ventana en que se la iba a consultar.

**El hueco estructural que expuso el ejercicio.** Este CVE lo detectó Marcos leyendo las noticias, no el tooling: `deps.sh due` es **por calendario**, no por advisory, y un 9.2 explotándose activamente no puede esperar el ciclo mensual. No se resuelve en este commit (requiere decidir una fuente de advisories y dónde engancharla), queda anotado como deuda.

Lo que **sí** se cierra acá es el otro hueco: `verify.sh` no tenía forma de asegurar que el PHP que corre sea el que se pineó. En este CVE puntualmente, un build verde no prueba nada — el fix no toma efecto en procesos vivos, así que un `up` que reusa un container deja los workers sirviendo el PHP viejo, sin dejar rastro. Es el paso que más fácil se saltea en un apuro. El step `[php-version]` lo asserta, y de paso falla si el tag deja de pinear un patch exacto, convirtiendo en check automático la convención que hoy vive solo en un comentario (y cuya violación ya rompió Mercure una vez). Mismo criterio que el step `[mercure]`: cada incidente pasado se vuelve una assertion.

**Nota de operación:** el restart ya estaba cubierto — `scripts/deploy.sh` hace `down --remove-orphans` antes del `up`, así que no quedan workers vivos con el PHP viejo. Un `up -d` suelto sobre un tag cambiado también recrea; el peligro es solo un `restart` del servicio, que no.
