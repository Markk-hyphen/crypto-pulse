# Plan de proyecto — "Crypto Pulse" (codename provisional)

> Proyecto-vidriera construido **sobre** la codebase Oliva.
> Estado: **planificación cerrada. Cero modificaciones físicas al código todavía** (salvo este doc y CLAUDE.md).
> Rama de trabajo: `release/plan-market-pulse`
> Fecha: 2026-05-31
>
> **Propósito de este documento:** ser un **runbook ejecutable de inicio a fin**. Está escrito para que un modelo más económico (Sonnet) pueda implementarlo paso a paso sin re-derivar decisiones. Cada paso trae: *objetivo · acciones concretas (archivos/comandos) · verificación*. Ver §11 (convenciones de ejecución) antes de empezar a codear.

---

## 0. Tesis del proyecto

Construir, **encima de la codebase Oliva**, una **plataforma de inteligencia de mercado cripto en tiempo real**: ingiere noticias y datos de mercado de fuentes públicas, los enriquece con IA (resumen, sentiment, clasificación, entidades, embeddings) y los emite en vivo a un dashboard vía Mercure.

El reparto de capas es deliberado:

| Capa | Mundo que representa | Rol en el proyecto |
|---|---|---|
| **Infraestructura / orquestación** | DevOps (relegado, a revivir) | **El titular.** Es lo que la codebase *es* y lo que tu CV no muestra. |
| **Pipeline IA (enriquecimiento, embeddings, RAG)** | IA (deep dive actual) | **El motor.** Mantiene la motivación y monta el músculo que querés. |
| **Dominio: mercado cripto (noticias + datos)** | Trading (en pausa) | **El sabor.** Mantiene trading tibio sin apostarle el proyecto. |
| **Backend Symfony** | 4 años de experiencia | **El piso.** Asumido, invisible, no se demuestra. |

**Decisión de fondo (cerrada):** el headline es **DevOps × IA** (AI infra / MLOps). No se construyen estrategias de trading: cripto es el dominio de datos, no el producto.

**Por qué cripto encaja aún mejor que mercados tradicionales:** opera **24/7** (no hay "mercado cerrado" que apague la demo), tiene **altísima velocidad de noticias** y volatilidad, y las **APIs públicas gratuitas y sin API key** son excelentes (CoinGecko, RSS de medios cripto). Refuerza justo lo que hace brillar el proyecto: el realtime es genuino y la demo está siempre viva.

### Por qué este proyecto y no el "Research OS" (cerrado)
- **No tiene arranque en frío:** las fuentes públicas lo llenan solas. La demo está viva desde el segundo cero.
- **El realtime es genuino y YA funciona:** el hub Mercure está operativo en la codebase (ver §1). Una noticia rompe → se enriquece → el dashboard se actualiza en vivo. Ese es el "wow" de 30s.
- **Maximiza superficie DevOps:** arquitectura event-driven, broker, workers, scheduler, observabilidad, CI/CD, deploy real.
- **El frontend actual alcanza:** dashboard de cards en vivo con el stack Vanilla JS/Bootstrap existente.

---

## 1. Estado actual del repositorio (línea de base real — verificado)

### Lo que YA existe y sirve
- **Orquestación dev/prod** con 3 compose (`docker-compose.yml` + `override` auto en dev + `prod`). Sólido.
- **Backend** FrankenPHP (PHP 8.3), multi-stage (`frankenphp_base` → `frankenphp_dev` xdebug+`--watch` / `frankenphp_prod` worker mode), JWT (lexik) instalado en build, healthcheck a `:2019/metrics`.
- **Hub Mercure ACTIVO** en `backend/frankenphp/Caddyfile` (módulo `mercure`, `anonymous` + `publisher_jwt`). **El realtime ya funciona.**
- **Demo realtime probado**: canvas colaborativo (`backend/public/live.php` + `frontend/src/js/live.js`) con `EventSource` + Mercure. Prueba viva del end-to-end.
- **Frontend** Vite 6, Vanilla JS modular (`main.js`, `setup.js`, `live.js`), Bootstrap 5, multi-stage (dev `yarn dev` / prod Caddy sirviendo `dist/`). Caddyfile con CSP, cache, compresión y proxy de `/api/*`, `/live.php`, `/.well-known/mercure*`.
- **Postgres 15** con healthcheck y volumen `db_data`.
- **`.env.example`** trae ya variables de Mercure y DB.
- **CI** existente (`backend/.github/workflows/ci.yml`).

### Gaps reales (verificado por inspección)
- [ ] **`backend/composer.json` NO existe en el host; `backend/src/` solo tiene un `Controller/` vacío; git no versiona nada de eso.** El esqueleto Symfony se genera en build (`composer create-project` en el Dockerfile). → decisión estructural §3.1.
- [ ] No hay **Doctrine ORM ni Migrations**.
- [ ] No hay **`pgvector`**.
- [ ] No hay **`MercureBundle`** (publisher desde Symfony). El hub sí funciona; solo falta publicar limpio desde el dominio.
- [ ] No hay **Messenger / broker / workers**.
- [ ] No hay **scheduler**.
- [ ] No hay **integración LLM** ni capa de costo/caché.
- [ ] No hay **tests** (PHPUnit); pasos del CI en `if: false`.
- [ ] **CI desalineado**: referencia `compose.yaml`/`compose.override.yaml` (nombres del template) en vez de `docker-compose.yml`.
- [ ] No hay **observabilidad** más allá del healthcheck.
- [ ] No hay **deploy** ni dominio público.

---

## 2. Arquitectura objetivo

```
                         Fuentes públicas cripto
            (RSS: CoinDesk, Cointelegraph · CoinGecko REST · CryptoPanic)
                                   │
                                   ▼
        ┌────────── scheduler (cron container, supercronic) ──────────┐
        │           dispara polls cada N min → encola "fetch X"        │
        ▼                                                              │
   [ RabbitMQ ]  exchange→cola `ingest`  /  cola `enrich`  / DLX       │
        │                                                              │
        ▼                                                              │
   worker INGESTA ── normaliza, deduplica (hash) ── persiste crudo ─► Postgres
        │                                                          (+pgvector)
        ▼  encola "enrich item Y"                                      ▲
   worker ENRIQUECE ── LLM (Anthropic): resumen, sentiment, clase,     │
        │              entidades, embedding ── persiste enriquecido ───┘
        ▼  publish (HubInterface)
   [ Hub Mercure (embebido en FrankenPHP/Caddy) ]
        │  SSE
        ▼
   Frontend (Caddy/Vite) ── dashboard en vivo: feed, filtros,
                            búsqueda semántica, "market now"
        ▲
        │  /api/* (REST: histórico, búsqueda, detalle)
        └─ Backend (Symfony) ── API + publisher Mercure
```

### Servicios Docker objetivo
| Servicio | Estado | Notas |
|---|---|---|
| `database` | existe | migrar a `pgvector/pgvector:pg15`; extensión `vector` por migración |
| `backend` | existe | + Doctrine, Messenger, MercureBundle, cliente Anthropic; API + publish |
| `frontend` | existe | nuevo dashboard; reusa stack actual |
| `worker` | **nuevo** | misma imagen backend, `command: messenger:consume ingest enrich`; escalable a N réplicas |
| `scheduler` | **nuevo** ✅ | **contenedor cron dedicado (supercronic)**; encola polls; pieza de orquestación explícita |
| `rabbitmq` | **nuevo** ✅ | imagen `rabbitmq:3-management`; UI en `:15672`; volumen para durabilidad |
| `mercure` | existe (embebido) | no requiere servicio aparte: vive en el Caddy de FrankenPHP |
| `prometheus` | **nuevo (Fase 3)** | scrapea `:2019/metrics` de Caddy + métricas custom del pipeline |
| `grafana` | **nuevo (Fase 3)** | dashboards: lag de cola, throughput, latencia/costo LLM, errores |

---

## 3. Decisiones técnicas (TODAS CERRADAS)

### 3.1 — Versionar el `src/` del backend ⭐ (estructural — primer paso ineludible)
**Hoy:** el skeleton se regenera en cada build (`composer create-project`); `composer.json` y el código no están en git. Con dominio real eso es inviable: se perdería el código en cada rebuild.
**Decisión:** graduar de "boilerplate que se regenera" a "app versionada":
1. Generar el skeleton **una vez** dentro del contenedor y exportarlo al host.
2. Comitear `backend/composer.json`, `composer.lock`, `symfony.lock`, `src/`, `config/`, `bin/`, `public/index.php`, `migrations/`.
3. Quitar el bloque `composer create-project` del Dockerfile; dejar `composer install` sobre el código del repo. (El stage `frankenphp_prod` ya hace `COPY composer.* ...` + `composer install` + `COPY . ./`; alinear el base a eso.)
4. Eliminar el bloque "install first time" del `docker-entrypoint.sh` (lo indica el propio comentario del archivo).

### 3.2 — Persistencia ✅
Doctrine ORM (`symfony/orm-pack`) + Doctrine Migrations. Habilitar los pasos del `ci.yml` correspondientes.

### 3.3 — Capa vectorial ✅
`pgvector` sobre el Postgres existente (sin servicio nuevo). Imagen `pgvector/pgvector:pg15`. Extensión `vector` vía migración. Integración Doctrine: verificar el paquete vigente (`pgvector/pgvector` para PHP + tipo custom Doctrine `vector`). Índice HNSW/IVFFlat para búsqueda por similitud.

### 3.4 — Mensajería (broker) ✅
**RabbitMQ** (`rabbitmq:3-management`) + Messenger **AMQP transport**. Management UI en `:15672` (mostrable en la demo DevOps). Colas: `ingest` y `enrich`, con **dead-letter exchange** para fallos. Mensajes durables. Usuario con experiencia previa en Rabbit.

### 3.5 — Scheduler ✅
**Contenedor cron dedicado** (`supercronic`, imagen liviana). Ejecuta un comando Symfony (`app:sources:poll`) en intervalos configurables que encola en RabbitMQ. Orquestación explícita y observable.

### 3.6 — Publisher Mercure ✅
El **hub ya funciona**. Solo falta el publisher: instalar `symfony/mercure-bundle`, descomentar el COPY de `frankenphp/docker-configs/mercure.yaml` en el Dockerfile, publicar con `HubInterface`. Retirar `live.php` raw una vez migrado el demo (o conservarlo como página "playground" aparte).

### 3.7 — Proveedor LLM ✅ DECIDIDO
**Anthropic (Claude).** Modelos: **Haiku** (`claude-haiku-4-5`) para enriquecimiento de alto volumen (resumen/sentiment/clasificación/entidades por item) y **Sonnet** (`claude-sonnet-4-6`) para resúmenes agregados "Market Now". **No hay SDK oficial PHP**: usar `symfony/http-client` contra la API de Anthropic, encapsulado tras una interfaz `EnrichmentProvider` (mockeable en tests, intercambiable de proveedor).
**Controles de costo obligatorios:** (a) cada item se enriquece **una sola vez** (idempotencia por estado); (b) **caché** prompt→respuesta; (c) **prompt caching** de Anthropic en el system prompt fijo; (d) límite de gasto/rate configurable; (e) métrica de **costo en Grafana** (Fase 3). Embeddings: usar un proveedor de embeddings dedicado (verificar opción Anthropic/Voyage o un modelo local) — decisión de implementación a confirmar en el paso 1.4, abstraída tras `EmbeddingProvider`.

### 3.8 — Fuentes de datos ✅ DECIDIDO — dominio CRYPTO
**Stack elegido (cripto-nativo, óptimo y mayormente sin API key):**
- **MVP — Noticias (sin key):** RSS de **CoinDesk** y **Cointelegraph**. Cero dependencia de claves, alta velocidad, ideal para el primer loop.
- **MVP — Datos de mercado (sin key):** **CoinGecko REST** (precios, market cap, volumen, % cambio). Mejor cobertura gratuita y sin clave para endpoints públicos. Útil para contexto/impact y para enriquecer noticias con el activo afectado.
- **Fase 2 — Noticias enriquecidas (free tier con key):** **CryptoPanic API** — agregador cripto-nativo con metadata de fuente/sentiment/votos.
> Nota: de las tres APIs genéricas que estaban como opción original (Finnhub/Marketaux/NewsAPI), la mejor para cripto sería **Finnhub**; pero al ser el dominio 100% cripto, las fuentes cripto-nativas de arriba son superiores. Contrato `SourceAdapter` para sumar fuentes sin tocar el pipeline. **Respetar rate limits y términos de cada API.**

---

## 4. Runbook por fases (orden = protección de la motivación)

> **Regla de oro:** el producto que funciona va primero; la vidriera DevOps va después. No front-cargar infra antes de tener algo andando — fue donde el proyecto se trabó hace un año.
> Cada paso: **Objetivo · Acciones · Verificación.** Marcado de versiones/paquetes "(verificar vigente)" = el ejecutor confirma nombre/versión exactos al momento de instalar.

### FASE 0 — Fundaciones (sin features visibles)

**✅ 0.1 — Versionar el `src/` del backend** ⭐
- *Objetivo:* dejar el código de la app en git; quitar la regeneración en build.
- *Acciones:* levantar el backend actual; dentro del contenedor exportar el skeleton generado al host; comitear `composer.json/lock`, `symfony.lock`, `src/`, `config/`, `bin/`, `public/`, `migrations/`; editar `backend/Dockerfile` quitando `composer create-project` y dejando `composer install`; limpiar el bloque "install first time" de `docker-entrypoint.sh`; ajustar `.dockerignore`.
- *Verificación:* `docker compose build backend && docker compose up backend` levanta sin `create-project`; `git status` muestra el código versionado; `bin/console about` corre dentro del contenedor.

**✅ 0.2 — Doctrine ORM + Migrations**
- *Acciones:* `composer require symfony/orm-pack` y `symfony/maker-bundle --dev` (verificar vigente); configurar `DATABASE_URL`; primera migración vacía.
- *Verificación:* `bin/console doctrine:migrations:migrate` corre contra la DB del compose; `doctrine:schema:validate` ok.

**✅ 0.3 — pgvector**
- *Acciones:* cambiar imagen de `database` a `pgvector/pgvector:pg15` en `docker-compose.yml`; migración `CREATE EXTENSION IF NOT EXISTS vector`; instalar integración Doctrine de vectores (verificar paquete).
- *Verificación:* migración aplica; un insert/select de un `vector` de prueba funciona vía SQL.

**✅ 0.4 — MercureBundle (publisher)**
- *Acciones:* `composer require symfony/mercure-bundle`; descomentar COPY de `mercure.yaml` en Dockerfile; configurar `MERCURE_URL`/`MERCURE_PUBLIC_URL`/JWT en `.env*`.
- *Verificación:* un comando de prueba publica a un topic y `live.js` (o `curl` al hub) lo recibe.

**✅ 0.5 — Messenger + RabbitMQ**
- *Acciones:* agregar servicio `rabbitmq:3-management` (puertos 5672/15672, volumen, healthcheck, env user/pass) al compose; `composer require symfony/messenger symfony/amqp-messenger` (verificar vigente); configurar transports `ingest` y `enrich` con DSN AMQP + DLX en `config/packages/messenger.yaml`; añadir servicio `worker` (misma imagen backend, `command: bin/console messenger:consume ingest enrich -vv`, `restart: unless-stopped`, `depends_on` rabbitmq healthy).
- *Verificación:* UI de Rabbit en `:15672`; un mensaje de prueba viaja por la cola y el worker lo procesa; un fallo va al DLX.

**✅ 0.6 — Scheduler (cron container)**
- *Acciones:* servicio `scheduler` con `supercronic` (verificar imagen) ejecutando `bin/console app:sources:poll` cada N min (crontab en repo); comando stub que por ahora solo loguea/encola.
- *Verificación:* logs del scheduler muestran ejecución periódica; encola en Rabbit.

**✅ 0.7 — CI base coherente**
- *Acciones:* corregir `ci.yml` para usar `docker-compose.yml` reales; quitar `if: false` de los pasos de ORM/migraciones a medida que existan; agregar healthcheck de servicios nuevos al `up --wait`.
- *Verificación:* CI verde en push a la rama.

**✅ 0.8 — PHPUnit base**
- *Acciones:* `composer require --dev phpunit/phpunit symfony/test-pack` (verificar vigente); 1 test trivial; habilitar el paso PHPUnit del CI.
- *Verificación:* `php vendor/bin/phpunit` verde local y en CI. (`bin/phpunit` ya no es generado por la recipe en PHPUnit 12; usar `vendor/bin/phpunit` directamente.) `failOnDeprecation/Notice/Warning` relajados intencionalmente hasta paso 3.4.

**GATE Fase 0 ✅:** `docker compose up` levanta DB+pgvector, backend, rabbitmq, worker, scheduler; un comando publica a Mercure y se ve en el front; un mensaje recorre Rabbit→worker; CI verde con un test.

### FASE 1 — Producto end-to-end (1 fuente, 1 tarea IA) — "que ande y dé orgullo"

**✅ 1.1 — Modelo de dominio**
- *Acciones:* entidades `NewsItem` (source, externalId, title, url, body, publishedAt, contentHash único, status enum) y `Enrichment` (summary, sentiment, assetClass/tickers, entities JSON, embedding `vector`, model, tokens, costUsd, createdAt). Migraciones. Índice único por `contentHash`. Índice vectorial.
- *Verificación:* migraciones aplican; fixtures de prueba persisten.

**✅ 1.2 — Ingesta (CoinDesk/Cointelegraph RSS)**
- *Acciones:* interfaz `SourceAdapter`; `RssAdapter` para los 2 feeds; `IngestMessage` + handler: fetch → parse → normaliza → dedup por `contentHash` → persiste `NewsItem(status=pending)` → despacha `EnrichMessage`.
- *Verificación:* corriendo el poll, aparecen `NewsItem` reales en la DB sin duplicados.

**✅ 1.3 — Poll programado**
- *Acciones:* implementar `app:sources:poll` real (recorre adapters, despacha `IngestMessage`); cron del scheduler lo dispara.
- *Verificación:* sin intervención manual, entran items nuevos periódicamente.

**✅ 1.4 — Enriquecimiento IA**
- *Acciones:* `EnrichmentProvider` (Anthropic Haiku vía http-client) → resumen + sentiment + clase de activo + tickers/entidades; `EmbeddingProvider` → embedding (definir proveedor aquí, §3.7); handler de `EnrichMessage`: idempotente, cachea, persiste `Enrichment`, registra tokens/costo, marca `NewsItem(status=enriched)`.
- *Verificación:* items pasan a `enriched` con resumen y embedding; reintentos no duplican costo; fallo de API → DLX, no se pierde el item.

**✅ 1.5 — Publish a Mercure**
- *Acciones:* al persistir `Enrichment`, publicar el item enriquecido al topic `crypto/feed` con `HubInterface`.
- *Verificación:* `curl` al hub / front recibe el evento.

**✅ 1.6 — API REST**
- *Acciones:* `GET /api/feed` (paginado, filtros básicos) y `GET /api/items/{id}`; serialización; CORS/headers según Caddyfile.
- *Verificación:* endpoints responden JSON correcto; paginación ok.

**✅ 1.7 — Dashboard en vivo**
- *Acciones:* nueva vista (reusar patrón `live.js`/Bootstrap): carga inicial vía REST + suscripción Mercure a `crypto/feed`; cada card muestra resumen IA, sentiment, etiquetas/tickers, fuente, timestamp; indicador LIVE/RECONNECTING.
- *Verificación:* abrir 2 pestañas; entra noticia real; aparece enriquecida y se actualiza en vivo en ambas sin recargar.

**✅ 1.8 — Robustez del pipeline**
- *Acciones:* reintentos con backoff en Messenger; idempotencia; manejo de DLX (comando para reprocesar/inspeccionar); timeouts de http-client; degradación con gracia del front.
- *Verificación:* matar el worker / cortar la API LLM no pierde datos; al reanudar, procesa el backlog.

**✅ GATE Fase 1 (DEMO):** 2 pestañas → entra noticia cripto real → en segundos aparece enriquecida por IA y se actualiza en vivo en ambas. Pipeline resiste caídas. *(2 pestañas en vivo verificado en 1.7; resiliencia verificada en 1.8: worker muerto → backlog en cola → drena al reanudar; feed roto → 3 retries con backoff → 1 mensaje inspeccionable en `failed`; backend muerto con página abierta → watchdog reconecta y resincroniza.)*

### FASE 2 — Profundizar IA y dominio

**2.1** Múltiples fuentes vía `SourceAdapter`: sumar CoinGecko (datos de mercado/contexto) y CryptoPanic (Fase 2 con key).
- *Decisión de diseño (cierra ambigüedad — no improvisar en ejecución):* CoinGecko **no es una fuente de noticias** y no encaja en `NewsItem` (no tiene title/url/body de artículo). No forzarlo dentro del contrato `SourceAdapter` actual ni del pipeline de enriquecimiento LLM (enriquecer un snapshot de precio con Haiku es gasto sin sentido — viola el control de costo de §3.7). En cambio: entidad liviana propia `MarketSnapshot` (asset, priceUsd, marketCap, volume24h, changePct24h, fetchedAt), poblada por un poller propio (`app:market:poll`, mismo scheduler), **sin pasar por `EnrichMessage`/LLM**. Se consume como contexto para lo ya previsto: impact score (2.5) y "asset afectado" al enriquecer noticias. El contrato `SourceAdapter` queda reservado a fuentes de *noticias*; CryptoPanic (cuando haya key) sí lo implementa y entra por el mismo camino que RSS.
- *Acciones:* entidad + migración `MarketSnapshot`; interfaz `MarketDataProvider` + `CoinGeckoProvider` (http-client; endpoint `/coins/markets` o `/simple/price` — verificar vigente, sin key para uso público); comando `app:market:poll` con entrada propia en el crontab (intervalo más corto que noticias); retención acotada (snapshot por asset + timestamp truncado a N min, o purga por ventana) para no acumular sin límite; respetar el rate limit público de CoinGecko (~10-30 req/min sin key — verificar vigente) con backoff ante 429.
- *Verif:* `MarketSnapshot` se puebla periódicamente sin tocar `NewsItem`/`Enrichment`; 3+ fuentes estables en paralelo (2 RSS + CoinGecko; CryptoPanic al tener key).
**2.2** Búsqueda semántica (pgvector): `GET /api/search?q=` (embed query → kNN) + UI. *Verif:* resultados relevantes por significado, no keyword.
**2.3** Clustering/dedupe por tema (similitud de embeddings): agrupar noticias que cuentan lo mismo. *Verif:* eventos repetidos se agrupan.
**2.4** "Market Now": resumen agregado periódico (Sonnet) publicado en vivo. *Verif:* panel creíble que se refresca.
**2.5** Impact score (heurística + IA) para priorizar. *Verif:* orden por impacto sensato.
**2.6** Filtros del dashboard (clase, sentiment, fuente, impacto, ticker). *Verif:* filtros aplican sobre feed y búsqueda.
**2.7** (Opcional) Alertas por reglas del usuario → Mercure. *Verif:* regla dispara notificación en vivo.

**GATE Fase 2:** búsqueda semántica útil + "Market Now" creíble + varias fuentes estables.

### FASE 3 — Vidriera DevOps (el titular) ⭐

**3.1 Observabilidad — métricas:** Prometheus scrapea `:2019/metrics` (Caddy/FrankenPHP ya lo expone) + métricas custom (lag de cola desde Rabbit, items/min, latencia y **costo LLM**, tasa de error/DLX). Grafana con dashboards del pipeline. *Verif:* Grafana muestra el pipeline en vivo.
**3.2 Observabilidad — logs:** logs estructurados JSON (Monolog) en backend y workers; (opcional) Loki/Promtail. *Verif:* logs correlacionables por item/mensaje.
**3.3 Health/readiness** de `worker`, `scheduler`, `rabbitmq`. *Verif:* `docker compose ps` healthy; `up --wait` pasa.
**3.4 Tests:** unitarios de dominio + adapters (LLM mockeado) + 1 integración del pipeline; habilitar todos los pasos del `ci.yml`. *Verif:* cobertura de los caminos críticos; CI verde.
**3.5 CI/CD:** Actions → build multi-stage, hadolint (ya está), tests, **push de imágenes a GHCR** con tag por versión. *Verif:* imágenes publicadas por release.
**3.6 Deploy:** VPS con stack `prod`; dominio público; **HTTPS automático** (Caddy con `SERVER_NAME` real); CD que despliega en push a `main`. *Verif:* URL pública HTTPS; deploy automatizado.
**3.7 Operación:** backups de Postgres (dump periódico + retención), migraciones en deploy (paso controlado), límites de recursos por servicio, rotación de logs, durabilidad de colas Rabbit, runbook breve. *Verif:* restore de backup probado; deploy con migración sin downtime perceptible.
**3.8 Secrets:** sacar credenciales de `.env` versionados; usar secrets del entorno/CI; rotar JWT/Mercure/DB/API keys. *Verif:* repo sin secretos; `git log` limpio (o secretos rotados si hubo exposición).

**GATE Fase 3:** URL pública HTTPS; `git push main` despliega solo; Grafana muestra pipeline + costo LLM; README con badges reales y GIF de la demo.

### FASE 4 — Puente a trading (FUTURO, fuera de scope inicial)
Diferido. Solo tras cerrar 0–3: señales derivadas del sentiment/impact agregado; backtest del valor predictivo; watchlists por ticker con alertas. **No empezar por acá.**

---

## 5. Mapa skill → entregable (narrativa de portfolio)
- **DevOps/infra:** arquitectura event-driven, RabbitMQ, workers escalables, cron container, observabilidad (Prometheus/Grafana), CI/CD, deploy HTTPS, backups. → Fases 0, 3.
- **IA Systems:** pipeline LLM con caché y control de costo, embeddings + búsqueda semántica (RAG básico), clustering, resúmenes agregados. → Fases 1, 2.
- **Cripto/datos:** modelado del dominio, fuentes cripto-nativas, clasificación, impact scoring. → Fases 1, 2.
- **Backend (asumido):** Symfony/Doctrine/API — el piso, no el argumento.

---

## 6. Riesgos y mitigaciones
| Riesgo | Mitigación |
|---|---|
| Abandono por front-cargar infra | Producto andando (Fase 1) antes de observabilidad/deploy. |
| Scope creep hacia "OS" | Anti-scope §7. Fase 1 = 1 tipo de fuente, 1 tarea IA. |
| Costo LLM descontrolado | Enriquecer una vez + caché + prompt caching + Haiku para volumen + métrica de costo + límite configurable. |
| Regenerar skeleton borra el dominio | Paso 0.1 al inicio: versionar `src/`. |
| Rate limits / caída de fuentes | Reintentos+backoff, DLX, respetar límites de API, degradación con gracia. |
| Demo vacía | Dominio cripto 24/7 con fuentes públicas; seed al primer arranque. |
| Secrets en el repo | Auditar `.env*` antes del deploy público (3.8). |

## 7. Anti-scope (qué NO hacer)
- ❌ Estrategias de trading / señales en el MVP (Fase 4).
- ❌ Knowledge graph / UI de grafos.
- ❌ Multi-tenant / auth compleja en MVP (JWT ya está si hace falta).
- ❌ Reescribir el frontend a un framework SPA.
- ❌ Kubernetes en MVP (Compose alcanza; k8s sería otra vidriera, Fase 4+).
- ❌ "Soportar todas las fuentes": empezar con RSS, crecer vía `SourceAdapter`.

## 8. Definición de "demo de 60 segundos" (la vara)
1. Abro la URL pública (HTTPS) en dos pestañas.
2. Señalo el indicador **LIVE** y el panel **Market Now**.
3. Entra una noticia cripto real → en segundos aparece **enriquecida por IA** (resumen, sentiment, tickers) y se actualiza **en vivo en ambas pestañas**.
4. Hago una **búsqueda semántica** ("regulación", "ETF", "hack") y muestro resultados por significado.
5. Abro **Grafana**: throughput, lag de cola y **gasto LLM** en vivo. (Bonus: la UI de RabbitMQ con las colas.)
> Si los 5 puntos funcionan sin recargar y sin explicación, el proyecto cumplió.

## 9. Costos estimados (mensual, orden de magnitud)
- **VPS** (2 vCPU / 4 GB): bajo. (Rabbit + Prometheus + Grafana suman RAM; dimensionar.)
- **LLM**: controlado por caché + Haiku; depende del volumen de noticias (cientos/día ≈ bajo).
- **APIs de datos**: MVP 100% sin key (RSS + CoinGecko); CryptoPanic free tier en Fase 2.
- **Dominio**: anual, mínimo.

---

## 10. Próximo paso inmediato
Arrancar por **0.1 (versionar `src/`)** — cuello de botella estructural. Antes de tocar código de implementación, conviene cambiar al modelo de ejecución (ver §11).

---

## 11. Convenciones de ejecución (LEER antes de implementar — handoff de modelo)

**Para qué modelo ejecuta esto:** este plan fue redactado con Opus a propósito (decisiones de arquitectura y altitud). **La implementación conviene hacerla con Sonnet** (`claude-sonnet-4-6`): excelente para seguir un runbook detallado y escribir código multi-archivo, mucho más barato. **Haiku** reservarlo para pasos mecánicos triviales (ediciones puntuales, renombres); para código de dominio/Docker/pipeline, Sonnet es el equilibrio correcto. El cambio de modelo no rompe nada: este archivo es el artefacto de handoff; cualquier modelo retoma desde acá.

**Reglas para el ejecutor:**
1. **Una fase a la vez, una caja a la vez.** No avanzar de paso sin cumplir su *Verificación*. No avanzar de fase sin cumplir su *GATE*.
2. **Verificar versiones/paquetes vigentes** donde dice "(verificar vigente)" antes de instalar; no hardcodear versiones a ciegas.
3. **No commitear ni pushear salvo pedido explícito** del usuario. Trabajar en `release/plan-market-pulse`.
4. **No tocar `main`.** No borrar el demo de Mercure sin avisar (es activo de §1).
5. **Respetar el anti-scope (§7).** Si una tarea empuja fuera de scope, parar y preguntar.
6. **Costo LLM:** nunca enriquecer un item dos veces; caché siempre activo; en dev usar un mock de `EnrichmentProvider` por defecto para no gastar.
7. **Secrets:** jamás commitear claves; usar `.env*` ignorados.
8. **Ante ambigüedad o decisión no cubierta por este plan: parar y preguntar al usuario,** no improvisar arquitectura.
9. **Marcar progreso** tildando las cajas `[ ]` de §4 a medida que se cierran (con su verificación cumplida).

## 12. Checklist maestro "listo para producción"
- [x] `src/` versionado; build sin `create-project` (0.1)
- [x] Migraciones versionadas y aplicables en deploy (0.2) — completar en 3.7
- [x] pgvector habilitado (0.3) — índice vectorial en 1.1
- [x] Mercure publisher operativo (0.4)
- [x] RabbitMQ durable + DLX + UI (0.5)
- [x] Workers escalables con reintentos/backoff e idempotencia (0.5, 1.8)
- [x] Scheduler (cron container) estable (0.6)
- [ ] Healthchecks en TODOS los servicios (3.3)
- [x] Tests unitarios base + CI verde (0.8) — ampliar cobertura en 3.4
- [ ] CI/CD con push de imágenes a GHCR (3.5)
- [ ] Deploy a VPS con HTTPS automático + dominio (3.6)
- [ ] CD en push a `main` (3.6)
- [ ] Observabilidad: Prometheus + Grafana (métricas, lag, costo LLM) (3.1)
- [ ] Logs estructurados (3.2)
- [ ] Backups de Postgres con restore probado (3.7)
- [ ] Límites de recursos y rotación de logs (3.7)
- [ ] Sin secretos en el repo; secrets gestionados fuera (3.8)
- [ ] Control de costo LLM (caché, prompt caching, límite, métrica) (3.7, 3.1)
- [ ] README con badges reales + GIF de la demo (3.6)
- [ ] Demo de 60s (§8) reproducible de punta a punta
