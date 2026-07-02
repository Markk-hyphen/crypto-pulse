# SYNC-NOTES — Oliva (`main`) → Crypto Market Pulse (`release/plan-market-pulse`)

> **Qué es este doc.** Handoff de una sesión de *sync/análisis* (no de desarrollo). Analiza qué avanzó
> Oliva en `main` mientras la rama CMP estuvo congelada, decide **cómo** traer esos avances (merge vs
> rebase), inventaría los conflictos con política de resolución por archivo, y marca las decisiones de
> arquitectura que **requieren a Marcos** antes de tocar nada. La sesión que retome (Fable) debería poder
> arrancar la construcción de 1.6+ leyendo solo esto + `PLAN-MARKET-PULSE.md`.
>
> **Estado al escribir esto:** NADA mergeado, NADA commiteado. Working tree en `HEAD = d7850af`. El sync
> está *analizado*, no *ejecutado*. No se resolvieron los conflictos no triviales (por §11.8 + pedido explícito).

---

## 0. TL;DR ejecutivo

1. **Ramas divergentes**, no fast-forward. Merge-base `e23bca2` (2026-05-30) es **anterior a versionar el
   backend** → main y CMP graduaron el esqueleto Symfony *por separado* → **19 archivos en conflicto**, la
   mayoría `add/add` (git no tiene ancestro común de `composer.json`, `bundles.php`, `config/**`, etc.).
2. **Recomendación: MERGE `main` → rama CMP (una sola vez), NO rebase.** El rebase reescribiría los 38
   hashes de CMP, y `agent-commits.md` los registra como verdad → rompería el protocolo de commits del
   proyecto, y encima repetiría el aluvión `add/add` commit por commit. El merge resuelve los 19 conflictos
   una vez y preserva la historia. Detalle en §3.
3. **Dos arreglos mecánicos NO negociables** que el sync dispara (§6): `APP_ENV: development → dev`, y
   renombrar `services_development.yaml → services_dev.yaml` (si no, el mock dev de enrichment muere en
   silencio y dev empieza a gastar tokens de Anthropic).
4. **D2 RESUELTA (ya no bloquea):** toda app Oliva soporta standalone **y** shared-infra por diseño; el
   **target de deploy de CMP es infra** (el objetivo de la infra es compartir recursos). La infra ya provee
   Postgres + RabbitMQ (este último apagado, nadie lo usaba). CMP es el **primer fork que prende el Rabbit
   compartido**. Coexistencia con finanzas-ong: **db/user de Postgres propios + vhost de RabbitMQ propio +
   `-p crypto`**. Camino concreto en §5-D2.
5. Estado real 0.1–**1.5** confirmado presente y coherente pre-merge (§7). Ojo: el proyecto ya tiene **1.5
   commiteado** (Mercure publish + null provider), no "hasta 1.4" — el próximo paso real es **1.6 (API REST)**.

---

## 1. Topología de las ramas

| | commit | nota |
|---|---|---|
| **merge-base** | `e23bca2` — "fix: update swiper... vite... terser" (2026-05-30 19:31) | backend **sin versionar**: se construía en build-time con `composer create-project`. No había `composer.json`, `src/`, ni `config/` en git. |
| **rama CMP** (`release/plan-market-pulse`) | tip `d7850af`, **+38 commits** sobre la base | pasos 0.1 → 1.5 del runbook. |
| **`main`** (Oliva) | tip `3a88d6a`, **+40 commits** sobre la base | graduación de Oliva a framework reutilizable + profiles + shared-infra + staging + APP_ENV fix + CI. |

Divergieron: `git rev-list --left-right --count main...HEAD` → `40  38`. No hay fast-forward posible en
ninguna dirección.

### Por qué el aluvión de `add/add` (causa raíz de todo)

En el merge-base el backend **no estaba en git**. Las dos ramas, independientemente, hicieron el paso
"graduar backend de boilerplate a app versionada":
- CMP lo hizo en su paso **0.1** (`59aab7c`, "graduate backend from generated boilerplate").
- Oliva/main lo hizo en `250789d` ("graduar Oliva a framework reutilizable").

Resultado: `composer.json`, `composer.lock`, `symfony.lock`, `bundles.php`, `reference.php`, y todo
`config/packages/*.yaml` fueron **creados en ambas ramas sin ancestro común** → git los marca `add/add` y
no puede hacer 3-way merge; muestra las dos versiones completas aunque sean casi idénticas (recipes de
Flex). Esto es lo que hace el merge parecer más grande de lo que es: gran parte se resuelve "quedate con
una de las dos" porque son iguales salvo detalles.

---

## 2. Qué cambió en Oliva (`main`) desde el branch — los 40 commits, agrupados

Todo esto es lo que CMP **quiere** heredar (es la razón del sync):

| Bloque | Commits clave | Qué aporta a CMP |
|---|---|---|
| **Graduación a framework** | `250789d` | El mismo trabajo que CMP hizo en 0.1, pero desde la óptica "Oliva reutilizable". Origen de casi todos los `add/add`. |
| **Servicios opcionales por profile** | `1869cc8`, merge `9d2abc4`, `8f46d85` | `rabbitmq`+`worker` bajo profile `queues`; `scheduler` bajo profile `cron`. Control por `COMPOSE_PROFILES`. Ver §4 + §5-D1. |
| **Infra compartida** | `1ca8e5f`, `e77b4bc`, `4514d56` | `docker-compose.shared-infra.yml`: overlay para colgar la app de un Postgres/RabbitMQ/proxy externos, con split `data_net`/`proxy_net` y project-name por app. Ver §5-D2. |
| **Sistema de staging** | `cbc2499`, `d7183a5`, `b392a4d`, `674b8f1`, `7446886`, `9f37da4`, `52f35a2` | `docker-compose.staging.yml` + `frankenphp_staging` (Foundry+fixtures) + `deploy-staging.sh`/`down-staging.sh`. Staging como "una app más" en el VPS. |
| **APP_ENV corto** | `93b7816`, `57663fe` | `development`/`production` → `dev`/`prod`. Reactiva los bloques `when@dev`/`when@prod` de Symfony (con la palabra larga se desactivan silenciosamente). **CMP todavía usa `development`.** Ver §6. |
| **CI reescrito** | `5933ef1`, `57663fe` | Post-merge smoke + caché de capas GHA + guard de APP_ENV=prod. Reemplaza el `ci.yml` de CMP. |
| **Deploy shared-infra** | `be90133`, `f613a91`, `9deba3f`, `65321d9`, `b579658` | `scripts/deploy.sh`, `scripts/down.sh` + runbook de deploy con infra compartida. |
| **Seeding layer** | merge `8b0caff`, `fc1bd9e` | Foundry + Doctrine Fixtures + stage `frankenphp_staging`. |
| **Bruno / API testing** | `468b2c2` | Convención doc-only de testing de API (relevante cuando CMP haga 1.6 API REST). |
| **concepts.md movido** | (varios) | main lo tiene en `docs/concepts.md`; CMP lo tiene en la raíz. Ver §5-D3. |

Fuentes consultadas en main para el *por qué* (no repito acá): `agent-commits.md` (PASO 1.1 APP_ENV,
PASO 1.2 CI), `oliva-upgrade-optional-services.md` (modelo de profiles), y los comentarios in-file de
`docker-compose.shared-infra.yml` / `docker-compose.staging.yml`.

---

## 3. Merge vs Rebase — decisión y por qué

**Decidido: `git merge main` dentro de `release/plan-market-pulse` (merge de una sola vez). Rebase descartado.**

| Criterio | Merge `main`→CMP | Rebase CMP sobre `main` |
|---|---|---|
| Hashes de CMP | **se preservan** → `agent-commits.md` sigue válido | **se reescriben los 38** → el log de commits del proyecto (que registra hashes reales como entregable) queda mentiroso. Rompe el protocolo de §"Protocolo de commits" del CLAUDE.md. |
| Conflictos `add/add` | se resuelven **una vez** en el merge commit | se re-presentan **commit por commit** (los archivos del esqueleto se introducen a lo largo de 0.1–0.5) → resolver el mismo storm N veces |
| Dirección del proyecto | CMP es una **vidriera construida sobre** Oliva; el sync es one-way (framework→app). Un merge deja claro "traje Oliva hasta acá" | rebase sugiere que CMP eventualmente aterriza limpio en main, cosa que no pasa (no se mergea el dominio cripto al framework reutilizable) |
| Reversibilidad | un merge commit se revierte fácil | rebase fallido a mitad = 38 commits a medio replayar |

> **Nota de dirección:** se mergea **main → rama CMP** (traer Oliva a CMP), NO al revés. `main` no debe
> tocarse (CLAUDE.md + §11.4). CMP no vuelve a main.

---

## 4. El modelo de profiles de Oliva (contexto para resolver los compose)

Oliva agrupa servicios opcionales por **profile semántico**, controlado por `COMPOSE_PROFILES` en `.env`:

| Profile | Servicios que levanta | Vars que hay que configurar |
|---|---|---|
| (ninguno) | `backend`, `frontend`, `database` | `DATABASE_URL`, `APP_SECRET`, ... |
| `queues` | `+ rabbitmq`, `+ worker` | `RABBITMQ_DSN` / `MESSENGER_TRANSPORT_DSN` |
| `cron` | `+ scheduler` | (crontab poblado) |

- **NO existe profile `realtime`.** Se propuso para un mercure standalone y **se descartó**: Mercure corre
  embebido en el backend vía el hub de Caddy (FrankenPHP). Es **always-on dentro del backend**, no hay
  contenedor que togglear. (Confirmado por Marcos + `oliva-upgrade-optional-services.md §4`.)
- Regla de Oliva: *si activás un profile, configurás también sus variables* — responsabilidad del fork.

**Implicancia para CMP:** CMP es precisamente el fork que necesita **todo** el pipeline. Lo que en CMP hoy
son servicios "siempre on" (rabbitmq, scheduler, worker sin profile), en el modelo de Oliva se expresa
activando `COMPOSE_PROFILES=queues,cron` en el `.env` de CMP. El "realtime" que Marcos menciona = el backend
mismo (Mercure en Caddy), que ya está siempre arriba. Ver §5-D1.

---

## 5. Decisiones de arquitectura (PARAR y preguntar — no improvisar, §11.8)

### D1 — Reconciliación de profiles en los compose  · *riesgo bajo, casi mecánico*
CMP tiene `rabbitmq`/`scheduler`/`worker` **sin profile** (siempre on) y `backend depends_on rabbitmq`.
main los puso bajo `queues`/`cron` y desacopló `backend` (depende solo de `database`).
- **Recomendación:** adoptar el compose de main (con profiles) y setear `COMPOSE_PROFILES=queues,cron` en el
  `.env` de CMP. Reproduce el "todo arriba" de CMP sin pelearse con el diseño de Oliva, y mantiene paridad
  con el framework. Quitar `backend depends_on rabbitmq` (seguir a main): el `worker` ya espera a rabbitmq
  healthy; acoplar el backend al broker no aporta y rompe el `up` si algún día se corre sin `queues`.
- **Por qué lo listo igual:** es la única forma en que CMP "siempre on" convive con el modelo opt-in sin que
  un `docker compose up` pelado deje el pipeline a medias. Confirmá que te cierra el default `queues,cron`.

### D2 — Identidad en infra compartida  · **RESUELTA (Marcos, esta sesión)**
**Regla de Oliva:** toda app forkeada debe poder correr **standalone Y en infra compartida** — es una
capacidad, no una elección de fork. CMP mantiene ambos modos. **Su target de deploy en el VPS es infra
compartida** (el objetivo de la infra es ahorrar recursos compartiéndolos entre apps; finanzas-ong ya está
así). O sea: standalone para dev/pruebas locales; **infra cuando se deploya**.

**La infra (`/home/marcos/infra`) ya está lista — no hay gap:**
- Provee `postgres` (pgvector:pg15), `rabbitmq` (`rabbitmq:3-management`, bajo profile `queues`,
  **hoy apagado porque ninguna app usaba colas**), y `reverse-proxy` (Caddy), sobre redes externas
  `data_net` + `proxy_net`.
- Scripts: `provision-postgres.sh <db> <user>` y `provision-rabbitmq.sh <vhost> <user> [pass]`.
- Aislamiento por app: **db/user de Postgres propio + vhost de RabbitMQ propio + project name `-p <app>`**
  (→ `app_network` project-scoped, sin colisión DNS entre apps). Confirmado en `infra/CLAUDE.md`: "un solo
  Postgres, un solo RabbitMQ; cada app su propio vhost".

**CMP es el primer fork que efectivamente enciende el RabbitMQ compartido.** El mecanismo existe pero nunca
se ejerció en la práctica → **smoke-test obligatorio en el primer deploy** (colas de CMP aisladas en su
vhost, no visibles desde otras apps).

**Camino de deploy de CMP en infra (para cuando toque; NO es parte del sync de código):**
1. En `infra/`: setear `RABBITMQ_ADMIN_PASSWORD` en `.env` y levantar con `COMPOSE_PROFILES=queues docker
   compose up -d` (prende el Rabbit compartido por primera vez).
2. `./scripts/provision-postgres.sh crypto_db crypto_user` y `./scripts/provision-rabbitmq.sh crypto
   crypto_user` (nombres a confirmar; siguen el patrón `ong_*`).
3. En CMP `.env.backend` (prod): **descomentar/setear** `DATABASE_URL` → host `postgres` con
   `crypto_user`/`crypto_db`, y `RABBITMQ_DSN` → host `rabbitmq` con el vhost `crypto`.
4. Deploy con `-p crypto` + overlay `docker-compose.shared-infra.yml` (+ `staging.yml` para el staging de CMP).

**Consecuencia para el sync de código (§9):** traer `shared-infra.yml` y `staging.yml` de main como
**ciudadanos de primera** (no standalone-only), y dejar en `.env.backend` el template shared-infra (líneas
`DATABASE_URL`/`RABBITMQ_DSN` comentadas, listas para descomentar en el VPS) — igual que finanzas-ong. El
merge de código se hace igual; el deploy en infra es un paso posterior.

### D3 — Ubicación de `concepts.md`  · *menor, pero elegí*
main → `docs/concepts.md`; CMP → `concepts.md` (raíz). Recomiendo alinear a `docs/concepts.md` (paridad con
Oliva). Es mover un archivo + actualizar la referencia en CLAUDE.md.

---

## 6. Arreglos mecánicos que el sync OBLIGA (no son opcionales)

### M1 — `APP_ENV: development` → `dev` (y `production` → `prod`)
CMP usa la palabra larga en los 3 lugares del `docker-compose.override.yml` (`backend`, `scheduler`,
`worker`) y en `.env.example`. main ya lo arregló (`93b7816`): el Dockerfile hornea `ENV APP_ENV` corto y
los `when@dev`/`when@prod` de Symfony **solo matchean el string corto**. Con `development` esos bloques de
config se desactivan **en silencio**. Al mergear, adoptar la forma corta de main.

### M2 — `services_development.yaml` → `services_dev.yaml`  · *(consecuencia directa de M1, fácil de pasar por alto)*
El paso 1.5 creó `backend/config/services_development.yaml` con el alias
`EnrichmentProviderInterface → NullEnrichmentProvider` (mock dev, costo $0). Symfony carga
`services_{APP_ENV}.yaml`: con `APP_ENV=development` cargaba ese archivo. **En cuanto APP_ENV pase a `dev`
(M1), Symfony busca `services_dev.yaml` — que no existe — y el alias deja de aplicarse.** Efecto: dev cae al
`AnthropicEnrichmentProvider` real → pide API key y **gasta tokens** en cada corrida local. Es exactamente la
deuda que 1.5 dio por resuelta. **Renombrar el archivo** como parte del merge y verificar que
`bin/console debug:container EnrichmentProviderInterface` en dev resuelve al Null.

---

## 7. Estado real de Fase 0 y 1.x (verificado contra el código en `HEAD`, pre-merge)

Verificación **estática** (código presente y coherente con el runbook). La verificación **runtime** (bootear
el stack) debe rehacerse **post-merge**, porque el merge toca justo los archivos que hacen arrancar dev
(APP_ENV, `services_dev`, profiles de compose) — bootear ahora validaría una config que el merge cambia.

| Paso | Qué es | Estado en `HEAD` |
|---|---|---|
| 0.1 | `src/` versionado, build sin `create-project` | ✅ presente (`composer.json/lock`, `symfony.lock`, `src/`, `config/`) |
| 0.2 | Doctrine ORM + Migrations | ✅ `doctrine.yaml`, `doctrine_migrations.yaml`, migraciones en git |
| 0.3 | pgvector | ✅ imagen `pgvector/pgvector:pg15`, migración `CREATE EXTENSION vector`, tipo Doctrine `vector` |
| 0.4 | Mercure publisher | ✅ `MercureBundle`, `mercure.yaml`, hub en Caddyfile |
| 0.5 | RabbitMQ + Messenger + worker | ✅ transports `ingest`/`enrich`/`failed`, DLX, backoff; `worker` en override |
| 0.6 | Scheduler (supercronic) | ✅ `scheduler/crontab` con `*/5 app:sources:poll`; servicio scheduler |
| 0.7 | CI + `/health` | ✅ (CI se reemplaza por el de main en el merge) |
| 0.8 | PHPUnit base | ✅ `phpunit.dist.xml`, primer test unitario |
| 1.1 | Modelo de dominio + HNSW | ✅ `NewsItem`, `Enrichment`, `NewsItemStatus`, migración con índice HNSW parcial |
| 1.2 | Ingesta RSS | ✅ `SourceAdapterInterface`, `RssAdapter`, `EnrichItemMessage`, handler |
| 1.3 | Poll programado | ✅ `SourcesPollCommand` itera adapters |
| 1.4 | Enriquecimiento IA | ✅ `AnthropicEnrichmentProvider`, `VoyageEmbeddingProvider`, `EnrichItemHandler` |
| **1.5** | **Mercure publish + null provider dev** | ✅ **commiteado** (`c15bc35`). `EnrichItemHandler` publica a `crypto/feed`; `NullEnrichmentProvider` + `services_development.yaml`; `MERCURE_URL=http://backend/...` (fix worker). **Ojo M2.** |

> **Corrección al brief de la sesión:** el proyecto NO está "hasta 1.4 inclusive" — **1.5 ya está commiteado**.
> El próximo paso real (según CLAUDE.md) es **1.6 — API REST** (`GET /api/feed` paginado + `GET /api/items/{id}`).

La deuda técnica conocida (mock dev, prompt-caching no-op, dual-write, contentHash=hash de URL, RssAdapter
RSS-2.0-only, gap de re-embedding) sigue vigente y está en el CLAUDE.md de la rama — no la repito acá.

---

## 8. Pendiente de estudio (NO definir sin Marcos)

- **pgvector / índice HNSW** — bloqueante para Fase 2 (2.2 búsqueda semántica depende directo). Marcos aún no
  lo estudió. La migración 1.1 ya crea un índice HNSW parcial, pero **el diseño del índice (parámetros `m`/
  `ef_construction`, operador de distancia, re-embedding de items con `embedding=null`) queda sin definir**
  hasta que Marcos lo vea. No avanzar 2.x apoyándose en esto como si estuviera cerrado.

---

## 9. Inventario de conflictos (19 archivos) + política de resolución

Simulado con `git merge-tree --write-tree main HEAD` (no toca el working tree). Política sugerida:
**dominio/pipeline → gana CMP; framework/infra → gana main; docs → unión manual.**

| Archivo | Tipo | Resolución sugerida |
|---|---|---|
| `docker-compose.yml` | content | **main** (profiles) + D1. Quitar `backend depends_on rabbitmq`. |
| `docker-compose.override.yml` | content | **main** (profiles en worker, APP_ENV corto) + conservar el `worker` de CMP. Aplicar M1. |
| `.env.example` | content | **unión**: base de main (COMPOSE_PROFILES, APP_ENV corto, shared-infra template) + vars de CMP (ANTHROPIC/VOYAGE). |
| `.env.backend` | content | **unión**: template shared-infra de main + `MERCURE_URL=http://backend` (fix 1.5 de CMP) + keys de CMP. |
| `.github/workflows/ci.yml` | add/add | **main** (CI reescrito, smoke, guard APP_ENV). |
| `.gitignore` | content | **unión** (ambos suman entradas). |
| `CLAUDE.md` | add/add | **unión manual**: es el CLAUDE de CMP (dominio) pero incorporando protocolos nuevos de Oliva si aplican. |
| `agent-commits.md` | add/add | **CMP** (es el log de CMP; el de main es otra historia). |
| `backend/composer.json` / `.lock` | add/add | **unión de deps**: base de CMP (tiene dominio: mercure, messenger, amqp, pgvector, http-client) + deps de framework de main (Foundry/fixtures si se adopta staging). Requiere `composer install` y re-lock post-merge. |
| `backend/symfony.lock` | add/add | idem composer: reconciliar recipes. |
| `backend/config/bundles.php` | add/add | **unión**: bundles de CMP + los que sume main (Foundry/staging). |
| `backend/config/services.yaml` | add/add | **unión** (autowiring base ~ igual; revisar diffs puntuales). |
| `backend/config/reference.php` | add/add | generado por Flex — regenerar, no resolver a mano. |
| `backend/config/packages/cache.yaml` | add/add | **CMP** (usa Symfony Cache por contentHash) — verificar diff. |
| `backend/config/packages/doctrine.yaml` | add/add | **CMP** (tiene `mapping_types` vector + server_version 15). |
| `backend/config/packages/messenger.yaml` | add/add | **CMP** (routing activo; main lo tiene comentado como ejemplo). |
| `backend/phpunit.dist.xml` | add/add | **main** (endurecido) o el que tenga la config más nueva — verificar. |
| `backend/scheduler/crontab` | add/add | **CMP** (`app:sources:poll` activo; main lo tiene vacío). |

**Entran limpios por el merge (main-only, CMP no los tiene → sin conflicto):** `docker-compose.shared-infra.yml`,
`docker-compose.staging.yml`, `scripts/deploy.sh`, `scripts/deploy-staging.sh`, `scripts/down.sh`,
`scripts/down-staging.sh`, `.env.staging.example`, `docs/roadmap/epics/E-seeding-layer.md`,
`backend/src/DataFixtures/`, `backend/src/Story/`, config de Foundry. Son justamente las capacidades de Oliva
que CMP debe heredar (D2). Verificar que el `frankenphp_staging` del Dockerfile se integre bien con el
Dockerfile de CMP (que tiene sus propios stages).

**No-conflicto pero a limpiar:** `_CMP_DIFF.md` y `_CMP_SYNC_NOTES.md` (materia prima de esta sesión,
commiteados en `d7850af`) se pueden borrar una vez leído este doc. `concepts.md` (raíz) → ver D3.

---

## 10. Próxima acción para la sesión que retome (Fable)

1. **D2 ya resuelta** (CMP soporta ambos modos; deploy target = infra). Quedan por confirmar con Marcos
   solo **D1** (default `COMPOSE_PROFILES=queues,cron`) y **D3** (`concepts.md` a `docs/`) — ambas de bajo riesgo.
2. Ejecutar el **merge `main` → `release/plan-market-pulse`** resolviendo por la política de §9. Traer
   `shared-infra.yml` + `staging.yml` como activos (CMP se deploya en infra) y dejar el template shared-infra
   en `.env.backend` (D2).
3. Aplicar **M1** (APP_ENV corto) y **M2** (`services_development.yaml → services_dev.yaml`) — sin esto, dev
   gasta tokens.
4. `composer install` + regenerar `reference.php` + re-lock; correr migraciones; **bootear y re-verificar
   0.1–1.5 en runtime** (§7) — recién ahí los checkmarks valen post-merge.
5. Verificado el stack, arrancar **1.6 — API REST** siguiendo `PLAN-MARKET-PULSE.md`.
6. Registrar el merge en `agent-commits.md` (protocolo del CLAUDE.md) cuando Marcos lo pida.

> Recordatorio §11: una caja a la vez, no avanzar sin verificación, no tocar `main`, no commitear/pushear sin
> pedido explícito, ante ambigüedad de arquitectura **parar y preguntar**.
