# QA y staging en Oliva

Qué garantías ofrece el framework antes de que algo llegue a producción, y con qué
herramienta se obtiene cada una. Documento para humanos; los runbooks paso a paso de
deploy viven en `CLAUDE.md` (que es la guía operativa para agentes).

Hay **tres capas de verificación**, de la más rápida a la más completa, más una cuarta
que es responsabilidad de cada app:

| Capa | Herramienta | Dónde corre | Qué prueba |
|---|---|---|---|
| 1 | `scripts/oliva/verify.sh` | tu máquina | que el stack levanta y funciona, end-to-end |
| 2 | `.github/workflows/ci.yml` | GitHub Actions | lo mismo, en limpio, en cada push/PR |
| 3 | stack de staging | VPS (o local) | el código en un entorno igual a prod, con datos sembrados |
| 4 | collection Bruno `api/` | donde apuntes | los flujos de negocio de **tu** app (no lo shipea Oliva) |

---

## Capa 1 — `verify.sh`: el smoke test local

Un solo comando que levanta el stack y asserta 8 cosas. Es lo que se corre después de un
sync de Oliva, después de un cambio en el Dockerfile, o antes de un release.

```bash
scripts/oliva/verify.sh
```

| Step | Qué asserta |
|---|---|
| `up` | `docker compose up -d --build --wait` — todos los servicios llegan a healthy |
| `php-version` | el PHP que **corre** coincide con el pin del `Dockerfile`, y el tag pinea un patch exacto |
| `health` | `GET /health` devuelve OK |
| `mercure` | el hub responde y `MERCURE_PUBLISHER_JWT_KEY` no está vacía |
| `migrations` | `doctrine:migrations:up-to-date` — no quedan migraciones pendientes |
| `schema` | `doctrine:schema:validate` — el schema real coincide con el mapeo |
| `phpunit` | la suite de tests |
| `prod-build` | las imágenes de **producción** buildean (no solo las de dev) |

**Cada step es un incidente pasado convertido en assertion.** Eso explica por qué hay dos
que parecen redundantes:

- `php-version` existe porque **un build verde no prueba que estés parcheado**: si el `up`
  reusó un container vivo, sus workers siguen sirviendo el PHP anterior. Es exactamente el
  modo de falla de un CVE como PHP2Shell, donde el fix solo toma efecto al recrear el
  proceso — el paso que más fácil se saltea en un apuro, y el que no deja rastro.
- `prod-build` existe porque dev y prod son stages distintos del Dockerfile: el stack de
  dev puede andar perfecto y el build de prod estar roto.

### Saltear steps: `OLIVA_VERIFY_SKIP`

```bash
OLIVA_VERIFY_SKIP="schema prod-build" scripts/oliva/verify.sh
```

Un fork puede divergir legítimamente de lo que un step espera y producir un rojo falso.
Caso real: una app con índices HNSW de pgvector creados a mano hace que
`doctrine:schema:validate` reporte drift permanente. El step se saltea, no se borra, y la
salida lo imprime como `SKIP` en vez de `PASS` para que la excepción quede a la vista.

---

## Capa 2 — CI: lo mismo, en limpio

`.github/workflows/ci.yml` corre en cada push y PR, con **tres jobs**:

| Job | Qué hace |
|---|---|
| **Tests (smoke + PHPUnit)** | buildea las imágenes (con caché de capas de GHA), levanta los servicios, chequea alcanzabilidad HTTP y de Mercure, corre migraciones, valida el schema de Doctrine y corre PHPUnit. Si algo falla, vuelca los logs de los servicios |
| **Prod config guard** | verifica que `APP_ENV` resuelve a `prod` en el stack de producción, en backend **y** scheduler. Es un guard de configuración, no de código: nació de que la precedencia de Compose (`environment:` > `env_file:` > `ENV` de la imagen) hizo que un entorno resolviera mal en silencio |
| **Docker Lint** | hadolint sobre el `Dockerfile` del backend |

La diferencia con la capa 1 no es qué se prueba, es **dónde**: CI parte de cero, sin
imágenes cacheadas localmente ni containers vivos, así que caza lo que tu máquina esconde.

### Saltear steps: `OLIVA_CI_SKIP`

Es una **variable de repositorio** de GitHub, no un secret:

```bash
gh variable set OLIVA_CI_SKIP --body schema
```

Acepta `schema` y `phpunit`, con el mismo criterio que `OLIVA_VERIFY_SKIP`: la excepción
se declara una vez y queda visible, en vez de que alguien conviva con un CI rojo.

---

## Capa 3 — El stack de staging

**Qué es:** una instancia más de la app, con el **mismo build que producción** pero con
base de datos propia y desechable, y datos sembrados. Sirve para probar el código
compilado como en prod sin tocar datos reales.

No es un entorno aparte con reglas propias: es **una app más** en el host, con su propio
project name (`-p <app>-staging`), así que convive con producción sin interferir.

### Cómo se diferencia de producción

Staging es un stage del Dockerfile que **extiende** el de prod:

```
frankenphp_prod  →  frankenphp_staging
```

Y le cambia tres cosas:

1. `APP_ENV=staging`.
2. **Borra el `.env.local.php` horneado por prod.** Prod compila el entorno con
   `composer dump-env prod`; heredar ese archivo pisaría el `APP_ENV` de staging. Hay que
   borrarlo *antes* del install para que el entorno se resuelva en runtime.
3. **Instala también las dependencias de dev.** Por eso staging tiene
   `doctrine:fixtures:load`, `phpunit` y Foundry, y prod no: viven en `require-dev`.

### Levantarlo

```bash
./scripts/deploy-staging.sh
```

Hace, en orden: `git pull` (salteable con `SKIP_PULL=1`) → `down` → `up -d --build` con
los 4 overlays → migraciones → `fixtures:load --group=staging`.

Para reiniciar con datos frescos sin volver a traer código: `SKIP_PULL=1 ./scripts/deploy-staging.sh`.

Para bajarlo: `./scripts/down-staging.sh`. **Nunca borra volúmenes** (no pasa `-v`), así
que la DB desechable sobrevive; para purgarla de verdad hay que bajar a mano con `-v`.

### Seeding: Foundry + Doctrine Fixtures

Las fixtures se agrupan por entorno con `FixtureGroupInterface`. Las de Oliva
(`backend/src/DataFixtures/AppFixtures.php`) declaran los grupos `staging` y `dev`, y
`deploy-staging.sh` carga solo `--group=staging`.

Los grupos son lo que hace seguro el `fixtures:load`: **la carga purga la base**, y eso es
inocuo en staging justamente porque su DB es desechable. La misma orden contra la base de
producción sería destructiva — por eso prod no tiene ni el comando (no instala dev deps).

### Un gotcha de precedencia que ya costó caro

`docker-compose.prod.yml` hardcodea `environment: APP_ENV=prod`. En Compose,
`environment:` > `env_file:` > `ENV` de la imagen — así que ese valor pisaba el
`.env.staging` **y** el `ENV` del Dockerfile, pese a que `staging.yml` se apila encima.
Síntoma real: `fixtures:load` fallaba con "command not defined", porque `prod` no está en
`bundles.php`. Por eso `docker-compose.staging.yml` fija `environment: [APP_ENV=staging]`
explícito en backend y scheduler.

Regla general para diagnosticar cualquier env var que no toma el valor esperado: primero
`docker exec <c> printenv VAR` y `docker compose ... config` (para ver de qué capa sale),
recién después editar algo.

> `docker-compose.staging.yml` usa `env_file: !override` para **reemplazar** la lista del
> base en vez de concatenarla, de modo que quede `[.env, .env.backend, .env.staging]` y
> `.env.staging` cargue último. Requiere **Docker Compose ≥ 2.24**.

---

## Capa 4 — Flujos de negocio: la collection Bruno (por app)

El health check confirma que el proceso arranca; **no** confirma que el dominio funcione.
Esa es la última capa, y Oliva no la shipea: los requests son 100% específicos de cada
app. La convención es una collection [Bruno](https://www.usebruno.com/) en `api/`, que se
corre contra el entorno recién levantado y verifica login + los flujos de dominio.

> **Deuda conocida:** Bruno **escribe de vuelta** al archivo del environment en disco
> cuando editás una variable desde la UI o cuando un script `post-response` hace
> `bru.setVar(...)`. Como los `environments/*.bru` están trackeados en git, cada sesión de
> testeo real ensucia archivos commiteados con valores efímeros (ids de fixtures, montos
> de prueba). Mitigación hoy: `git checkout -- api/` después de testear. El fix pensado —
> clonar los environments a copias `*.local.bru` gitignoreadas, mismo patrón que
> `.env.example` → `.env` — está pendiente de implementar en Oliva.

---

## Qué NO cubre esto

Para no leer más garantías de las que hay:

- **No hay tests de navegador ni end-to-end.** Las capas 1-3 prueban que el stack levanta y
  responde; el frontend solo se verifica en que buildea y sirve.
- **No hay gate de cobertura.** PHPUnit corre, pero nada falla por cobertura baja.
- **No hay tests de carga ni de performance.**
- **No hay `worker` de producción.** `docker-compose.override.yml` (dev) define uno con
  `messenger:consume`, pero no hay equivalente en prod. Si tu app usa Messenger en serio,
  hay que agregarlo antes de ir a producción.
- **Las alertas de dependencias son por calendario, no por advisory.** `scripts/oliva/deps.sh due`
  avisa cuando toca el ciclo de mantenimiento; no sabe de CVEs. Un CVSS 9.2 explotándose
  activamente no espera el ciclo mensual — ese hueco está abierto y es el que dejó a dos
  forks con un RCE sin parchear hasta que alguien lo leyó en las noticias.
