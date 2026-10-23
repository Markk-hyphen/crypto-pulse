# Actualizaciones: mantener Oliva vivo y bajarlo a cada app

Oliva es un framework: si no se actualiza envejece (este doc nace con Node 20 ya EOL), y si
las apps no bajan lo nuevo, divergen hasta que el merge cuesta 19 conflictos. Este doc define
**cómo se actualiza Oliva** y **cómo cada app trae esos cambios**, a escala de 1-3 apps y un
solo dev. No es un sistema automático: son tres scripts, una convención de propiedad de
archivos y un recordatorio en el chequeo de inicio de sesión.

## El modelo en una pantalla

```
            Oliva (repo framework)                         Fork (finanzas-ong, crypto-pulse, …)
 ┌───────────────────────────────────────┐            ┌─────────────────────────────────────────┐
 │ deps.sh due     ← chequeo de sesión     │            │ sync.sh check  ← chequeo de sesión      │
 │ deps.sh report  → qué está viejo/EOL    │            │ sync.sh start  → rama + merge + triage  │
 │ deps.sh update  → rama chore/deps-…     │            │ sync.sh locks  → regenera locks         │
 │   bump en rangos + verify + commit      │  push main │ sync.sh verify → smoke + tests          │
 │ (majors / imágenes base: a mano)        │ ─────────► │ merge local a main (sin PR)             │
 │ release.sh X.Y.Z → OLIVA_VERSION + tag  │  + tag     │                                         │
 │   exige notas en UPGRADING.md           │            │ deps.sh report → deps PROPIAS del fork  │
 └───────────────────────────────────────┘            └─────────────────────────────────────────┘
```

Tres principios, cada uno sale de un incidente real:

1. **Todo fijado, nada flotante.** Una actualización pasa cuando alguien la decide, no cuando
   alguien rebuildea. (El tag `1-php8.3` trajo FrankenPHP 1.13.1 en un rebuild cualquiera y
   rompió Mercure; el `yarn.lock` sin versionar hacía lo mismo con el frontend.)
2. **Cada archivo tiene dueño.** El framework y la app no editan los mismos archivos salvo una
   lista corta y conocida. Los conflictos de sync salen casi todos de archivos con dos dueños.
3. **El recordatorio vive en el flujo, no en la memoria.** La memoria del agente es por repo:
   no sirve para avisarle a un fork que Oliva avanzó. Por eso `check`/`due` van en los chequeos
   de inicio de sesión del `CLAUDE.md` de cada proyecto.

## Lado Oliva: el ciclo de mantenimiento (cada ~45 días)

`scripts/oliva/deps.sh due` (offline, instantáneo) dice si toca: mira la fecha del último
commit `chore(deps)`. Cuando toca:

1. **`scripts/oliva/deps.sh report`** (~40 s, usa red). Imprime:
   - **EOL** de PHP, Node, PostgreSQL, RabbitMQ y Symfony (endoflife.date). ⛔ = ya sin soporte.
   - **Imágenes base**: la versión fijada contra la más nueva con la misma forma de tag (Docker Hub)
     y supercronic (GitHub releases).
   - **Composer**: directas desactualizadas. ↑ = entra en el rango (lo hace `update`);
     ⇑ = salto de major, cambiar el constraint a mano. Más `composer audit` (CVEs).
   - **Frontend**: `yarn outdated` + `yarn audit` sobre el lock versionado.
   - **GitHub Actions**: major actual contra el último release.
2. **`scripts/oliva/deps.sh update`**: crea `chore/deps-<fecha>`, sube patch/minor **dentro de
   los rangos** (composer + yarn), corre `verify.sh` y, si pasa, commitea con el resumen de
   versiones. Si falla, deja los cambios sin commitear para inspeccionar.
3. **A mano, un commit por salto** (lo que el report marcó ⛔/⇑/↑ en imágenes): editar el
   `FROM`/`image:`/constraint, `scripts/oliva/verify.sh`, commit `chore(deps): …`. Nunca dos
   saltos grandes juntos: si algo se rompe, tiene que quedar claro cuál fue.
4. Mergear la rama a `main` local, escribir la sección en `docs/oliva/UPGRADING.md` y
   **`scripts/oliva/release.sh X.Y.Z`** (patch = solo deps; minor = features o pasos para forks;
   major = rompe algo que el fork tiene que reescribir). `git push origin main vX.Y.Z`.

`verify.sh` es la red de seguridad de todo: levanta el stack dev con `--build`, chequea
`/health`, **Mercure de punta a punta** (publish con JWT, el suscriptor con token recibe el
privado y el anónimo no), migraciones al día, `schema:validate`, PHPUnit y build de las
imágenes de prod. Cada paso se saltea con `OLIVA_VERIFY_SKIP="paso otro"`.
En CI (GitHub Actions) el equivalente es la **variable de repo** `OLIVA_CI_SKIP` (`schema`,
`phpunit`): un fork que tiene un paso en rojo conocido lo apaga sin editar `ci.yml`, que es de
Oliva — `gh variable set OLIVA_CI_SKIP --body schema -R <owner>/<repo>`.

## El aviso por advisory (CVEs, fuera del ciclo)

El ciclo de arriba corre cada ~45 días: eso sirve para **frescura**, no para
**seguridad**. Un CVE crítico no espera al próximo ciclo. Por eso hay una segunda
cadencia, más corta y solo-CVE: **`scripts/oliva/deps.sh audit`** (~7 días), fiel al
principio de que el recordatorio vive en el flujo —  `deps.sh due` (el chequeo de
inicio de sesión de siempre) ahora también dice hace cuánto que no corrés `audit`.

**Una fuente por capa, no varias apiladas.** Es la decisión de diseño del audit. Las
grandes bases de advisories de *paquetes* se alimentan entre sí (GHSA ⟵ NVD +
FriendsOfPHP; la API de Packagist que usa `composer audit` ⟵ FriendsOfPHP + GHSA;
OSV ⟵ GHSA). Apilar GHSA + OSV + Packagist sobre el **mismo `composer.lock`** da
casi los mismos hallazgos con distinto ID: es redundancia, no robustez. La robustez
viene de cubrir **capas distintas**, cada una con una buena fuente:

| Capa | Qué puede tener un CVE | Fuente |
|---|---|---|
| Paquetes PHP (`composer.lock`) | Symfony, Doctrine, … | `composer audit` → Packagist/GHSA |
| Paquetes JS (`yarn.lock`) | Vite y su árbol | `yarn audit` → GHSA |
| **Imágenes base** | **SO + binarios DENTRO de la imagen** (OpenSSL del postgres, el binario de Caddy en FrankenPHP, …) | **Trivy** (DB propia ≈ GHSA + NVD + distros) |

La capa de imágenes era el agujero: `composer`/`yarn audit` ven los *paquetes* de la
app, nunca lo que vive adentro de la imagen base. Trivy la cierra. `deps.sh audit`
corre las tres; `deps.sh report` incluye la de Trivy en la foto completa; y el CI
tiene un job `image-scan` (report-only) con la misma versión pinneada de Trivy.

Detalles operativos: Trivy corre como **contenedor pinneado** (nada que instalar en
el host), escanea el **ref base** fijado (no la imagen prod buildeada: ahí viven casi
todos los CVEs de imagen y no hace falta buildear), filtra HIGH/CRITICAL **con fix
disponible** (`--ignore-unfixed`), y lee `.trivyignore` para los CVEs aceptados. El
pin de Trivy se bumpea en el ciclo de deps como cualquier otra imagen (nunca < 0.71.1:
la v0.69.4 estuvo comprometida en un incidente de supply-chain).

## Lado fork: traer Oliva

Requisitos: remote `oliva-upstream` → `https://github.com/Markk-hyphen/oliva.git`, y el fork
ya mergeó Oliva ≥ 1.1.0 al menos una vez (ese primer merge trae los scripts; ver
`UPGRADING.md` 1.1.0).

1. **`scripts/oliva/sync.sh check`** en cada inicio de sesión. Dice "al día" o cuántos commits
   y desde cuándo, más las notas de `UPGRADING.md` pendientes.
2. **`scripts/oliva/sync.sh start`**: exige árbol limpio, activa `git rerere`, crea
   `chore/oliva-sync-<versión>`, mergea y **clasifica cada conflicto**:
   - `[OLIVA]`: archivo del framework (`owned-paths.txt`) → tomar el de Oliva (`git checkout --theirs`).
   - `[LOCK]`: `composer.lock`/`yarn.lock` → no tocar a mano, lo resuelve `locks`.
   - `[MANUAL]`: archivo compartido (`CLAUDE.md`, override, `config/**`…) → combinar.

   También lista el **drift**: archivos de Oliva que el fork editó desde el último sync. Cada uno
   es un conflicto futuro asegurado: o se documenta por qué, o se devuelve a Oliva.
3. **`scripts/oliva/sync.sh locks`**: parte del `composer.lock` **del fork** y re-aplica solo los
   paquetes que Oliva cambió (no arrastra updates de los paquetes propios del fork). `yarn.lock`
   se regenera contra el `package.json` del fork.
4. `git add -A && git commit --no-edit` → **`scripts/oliva/sync.sh verify`** → si pasa,
   `git switch main && git merge --no-ff chore/oliva-sync-…`. Push y deploy, como siempre.

**Por qué merge y no rebase ni cherry-pick:** el merge preserva los hashes que registra
`agent-commits.md`, deja un punto de sync explícito en la historia y hace que el próximo merge
parta de un ancestro común. `git rerere` recuerda cómo se resolvió cada conflicto.

## Backport: un fix genérico nacido en un fork

Cuando el drift muestra un archivo de Oliva que el fork cambió **por una razón que aplica a
cualquier app** (caso real: `trusted_proxies` en `frontend/Caddyfile` de finanzas-ong, para que el
throttling de login vea la IP real detrás del reverse-proxy compartido), no se documenta como
excepción: se lleva a Oliva (commit propio, citando el hash del fork) y baja a todos en el
próximo sync. Al llegar, el archivo queda idéntico en el fork y el drift desaparece solo.
Si el cambio es específico del fork, se documenta en su `CLAUDE.md` y se asume el conflicto.

## Propiedad de archivos (`scripts/oliva/owned-paths.txt`)

| Dueño | Qué | En un sync |
|---|---|---|
| **Oliva** | Dockerfiles, `backend/frankenphp/`, los 4 compose salvo el override, `scripts/` de deploy y `scripts/oliva/`, CI, `docs/oliva/`, `OLIVA_VERSION` | Gana Oliva. Si un fork necesita otra cosa, se agrega a Oliva como opción (env var, profile) y baja a todos. |
| **Compartido** | `docker-compose.override.yml`, `composer.json`, `package.json`, `config/**`, `.env.example`, `.env.backend`, `.gitignore`, `CLAUDE.md`, `README.md`, `claude-commands.md` | Se combina a mano; `rerere` lo aprende. |
| **Log del proyecto** | `agent-commits.md`, `commits.md` | Gana el del fork (`git checkout --ours`): Oliva registra lo suyo en su propio archivo. |
| **Locks** | `composer.lock`, `yarn.lock` | `sync.sh locks`. `symfony.lock`: unión a mano (raro). |
| **Fork** | `src/`, `migrations/`, `tests/`, `docs/` (salvo `docs/oliva/`), `backend/php-extensions.txt`, todo lo demás | Oliva no los toca. |

**Extension points** (para no editar archivos de Oliva): `backend/php-extensions.txt` (extensiones
PHP de la app), `docker-compose.override.yml` (servicios de dev propios, ej. mailpit), `COMPOSE_PROFILES`
(servicios opcionales), `OLIVA_VERIFY_SKIP` / variable de repo `OLIVA_CI_SKIP` (pasos en rojo conocido).
Si un fork necesita cambiar un archivo de Oliva y no hay extension point, el extension point se
agrega en Oliva.

## Espacio en disco

El repo casi no crece con los ciclos (un ciclo cambia líneas de los lockfiles: decenas de KB).
Lo que crece es Docker: cada rebuild deja la imagen anterior sin tag y suma caché de build.
`deploy.sh`, `deploy-staging.sh` y `deps.sh update` llaman al final a
`scripts/lib/docker-prune.sh`: borra imágenes sin tag y caché de build de más de 7 días. Nunca
toca imágenes con tag, volúmenes ni containers. Se saltea con `OLIVA_NO_PRUNE=1`.

En dev queda una fuga que el script no cubre a propósito: `docker compose down` sin `-v` deja
huérfanos los volúmenes anónimos (`node_modules` del frontend, `var/` del backend). Limpiarlos a
mano de vez en cuando con `docker volume prune -f` (en Docker ≥ 23 borra solo anónimos sin uso;
los volúmenes con nombre, como las DBs, no se tocan).

## Qué NO se automatizó (a propósito)

- **Dependabot/Renovate con PRs:** el flujo es solo-dev sin PRs, y un bot abriendo PRs que nadie
  mergea es ruido. Sí conviene activar en GitHub las **alertas de seguridad de Dependabot**
  (solo avisan, no abren PRs): Settings → Code security → Dependabot alerts, en los tres repos.
- **Cron que sincroniza solo:** un merge siempre tiene que verlo alguien (o un agente en sesión)
  porque puede tocar código del fork. El recordatorio de sesión es el término medio.
- **Saltos de major e imágenes base:** dependen de juicio (changelog, breaking changes). El
  report los encuentra; el humano decide.
