# Estudio + auditoría — Crypto Market Pulse, hitos 1.5–2.6

> Documento de referencia para releer, no para leer una sola vez. Recorre cada hito **presente en el código** (1.5, 1.6, 1.7, 1.8, 2.1, 2.4, 2.5, 2.6) con: qué problema resuelve en el pipeline real, el código concreto que lo implementa (archivo + función), las decisiones de diseño que quedaron abiertas y cómo se cerraron, la frontera entre lo que ya dominás y lo nuevo, y un checkpoint que podés correr vos.
>
> **Cómo está calibrado:** para **2.4 / 2.5 / 2.6** (construidos en la última sesión intensiva con Sonnet, sin revisión sobre la marcha) el recorrido incluye una **búsqueda activa de weak points** — casos borde, supuestos frágiles, valores hardcodeados, lugares donde el código asume el happy path. Lo que encontré va **dentro** del hito, no en un anexo: si una debilidad es real, el hito la refleja. Para **1.5–2.1** el nivel es de auditoría de diseño (decisiones + checkpoints), sin bug-hunt línea por línea.
>
> Fecha del recorrido: 2026-07-02. Rama `release/plan-market-pulse`. Sin cambios de código: este archivo es el único entregable.

---

## 0. La frontera: lo que ya dominás vs. lo genuinamente nuevo

Antes de entrar hito por hito, dónde está el límite (lo dijiste vos: 0.0–1.4 los entendés a fondo).

| Ya lo dominás (0.0–1.4) | Genuinamente nuevo (1.5–2.6) |
|---|---|
| Messenger: transportes `ingest`/`enrich`/`failed`, retry/backoff, DLX | **Publisher Mercure** desde el dominio (`HubInterface`) y su **degradación** (publish fuera del camino de fallo) |
| Idempotencia por estado (`status` guard) + caché LLM por `contentHash` | **Payload compartido REST↔Mercure** como única fuente de forma (`NewsItemPayload`) |
| Deduplicación por hash de URL | **Cliente SSE resiliente**: backoff, resync, watchdog anti-zombie |
| Las dos cachés (Symfony Cache vs Anthropic prompt caching) | **Datos fuera del pipeline LLM**: `MarketSnapshot` (2.1) — poller directo, sin cola, sin Haiku |
| | **Segunda familia de llamada LLM**: Sonnet agregado (2.4), distinto de Haiku por-item |
| | **Señal derivada sin costo extra**: impact score = salience (en el JSON de Haiku) + heurística (2.5) |
| | **Filtrado en dos planos**: REST (SQL) y en vivo (cliente), que tienen que coincidir (2.6) |

La regla que atraviesa casi todo lo nuevo es la misma que ya conocés de la capa de costo: **una señal/tarea LLM no se paga dos veces, y lo que no necesita LLM no entra al pipeline LLM.** 2.1, 2.4 y 2.5 son tres aplicaciones distintas de ese principio.

---

## 1. Mapa del pipeline (dónde encaja cada hito)

```
 RSS (CoinDesk/Cointelegraph)            CoinGecko /simple/price
        │ app:sources:poll (cron 5')            │ app:market:poll (cron 2')   ← 2.1
        ▼                                        ▼
   IngestSourceMessage ──► cola ingest      MarketSnapshot (persist directo,
        │                                    SIN cola, SIN LLM)
        ▼ IngestSourceHandler
   NewsItem(status=pending) ──► cola enrich
        │
        ▼ EnrichItemHandler
   Haiku (AnthropicEnrichmentProvider): summary/sentiment/assetClass/tickers/
        │                                entities/**salience** ← 2.5
        │  ImpactScorer.score() = 0.6·salience + 0.4·heurística(snapshot) ← 2.5
        ▼
   Enrichment(status=enriched) ──► publish crypto/feed (Mercure) ← 1.5
        │                              │
        │ GET /api/feed  ← 1.6/2.6     │ SSE
        ▼                              ▼
   Frontend pulse.html/pulse.js ← 1.7 (feed) + 2.6 (filtros) + watchdog ← 1.8

 app:market:now (cron 10') ← 2.4
   ≤15 NewsItem enriquecidos + snapshots ──► Sonnet (una sola llamada)
        ──► MarketNowSummary ──► publish crypto/market-now (Mercure) + GET /api/market-now
```

---

# Parte A — Hitos 1.5–2.1 (auditoría de diseño)

## 1.5 — Publish a Mercure + NullEnrichmentProvider dev

**Qué problema resuelve.** Cierra el end-to-end: cuando un item se enriquece y persiste, el dashboard tiene que enterarse en vivo. Y en dev no debe gastarse un token de Anthropic.

**Código real.** `EnrichItemHandler::__invoke` (`backend/src/MessageHandler/EnrichItemHandler.php`) publica a `crypto/feed` tras el `flush()` (líneas 82-92). El provider dev es `NullEnrichmentProvider`, aliasado en `backend/config/services_dev.yaml`.

**Decisiones.**
- **Publish *después* del `flush()`** (no antes): garantiza que lo que se difunde es exactamente lo que quedó en la DB. Publicar antes podría difundir un item que después falla al persistir.
- **`MERCURE_URL=http://backend/...`** (no `localhost`): el worker corre en otro contenedor sin Caddy; el hub vive en el contenedor `backend`. El DNS de Docker resuelve `backend` desde todos, incluido el propio backend.
- **Archivo `services_dev.yaml`, no `services_development.yaml`**: Symfony carga `services_{APP_ENV}.yaml`, y tras el sync con `main` `APP_ENV=dev`. El nombre viejo dejaba de aplicar el alias Null → dev gastaba tokens. (Esto se rompió y se arregló en el sync 2026-07-02, no en 1.5 original.)

**Frontera.** Lo nuevo acá es `HubInterface` como salida del dominio. El resto (idempotencia, caché) ya lo tenías.

**Checkpoint.**
```bash
# Suscribirse al topic y ver eventos en vivo mientras el worker enriquece:
curl -N -H 'Accept: text/event-stream' \
  'http://localhost/.well-known/mercure?topic=crypto/feed'
# En otra terminal, forzar un enrich (dev, sin costo):
docker compose exec backend bin/console app:enrich:requeue-pending --min-age=0
```

---

## 1.6 — API REST del feed

**Qué problema resuelve.** El dashboard necesita carga inicial (histórico) además del stream en vivo. Y ambos canales tienen que devolver **la misma forma** o el front necesita dos parsers.

**Código real.** `NewsItemPayload::from()` (`backend/src/Api/NewsItemPayload.php`) es la única fuente de la forma pública (13 keys hoy, con `impactScore` agregado en 2.5). `FeedController::feed` (`GET /api/feed`) y `::item` (`GET /api/items/{id}`). El join sin N+1 vive en `NewsItemRepository::findFeedPage` (innerJoin + `addSelect('e')` = fetch-join; `OneToOne` no multiplica filas, así que `LIMIT/OFFSET` siguen correctos sin `Paginator`).

**Decisiones.**
- **`NewsItemPayload` compartido** por REST y Mercure (el handler de 1.5 se refactorizó para usarlo) → el test `NewsItemPayloadTest` bloquea las keys: si REST y Mercure divergen, rompe CI.
- **Solo `enriched` en el feed**; `/api/items/{id}` sí devuelve cualquier status (caso de uso = inspección).
- **Sin Serializer ni API Platform**: 2 endpoints read-only mapeados a mano = menos dependencia.
- **Sin CORS**: `/api` es same-origin por diseño (proxy de Vite en dev, `handle /api/*` en el Caddyfile en prod).

**Checkpoint.**
```bash
curl -s 'http://localhost/api/feed?limit=3' | jq '.meta, .data[0] | keys'
# Debe listar exactamente las mismas keys que llegan por Mercure (ver 1.5).
```

---

## 1.7 — Dashboard en vivo (`pulse.html`)

**Qué problema resuelve.** La vidriera: una página que carga por REST, se suscribe a Mercure y actualiza cards en vivo sin recargar.

**Código real.** `frontend/pulse.html` + `frontend/src/pulse.js`. Un único `card(item)` sirve tanto a la carga inicial como a los eventos SSE (posible porque 1.6 unificó la forma). `upsert()` reemplaza in-place si el id ya está (cubre "pending que se enriquece después") y prepende si es nuevo, con tope `MAX_CARDS=60`. Build multi-página en `vite.config.js` (`rollupOptions.input`).

**Decisiones.**
- **Página aparte, no SPA** (respeta anti-scope §7).
- **Escape HTML obligatorio** (`esc()`): títulos/resúmenes vienen de RSS + LLM = no confiables.

**⚠️ Observación de bajo nivel (pre-2.4, tier liviano — la anoto pero no es del alcance de bug-hunt de esta sesión):** `card()` arma `href="${esc(item.url)}"` sin validar el *esquema* de la URL. `esc()` neutraliza `<`, `>`, `&`, `"`, pero **no** el esquema: una `url` con `javascript:...` que viniera de una fuente comprometida quedaría como href ejecutable. El test de XSS de 1.7 cubrió inyección de `<img onerror>` en el cuerpo (probado, no pasa), no el esquema del href. Riesgo bajo (requiere una fuente RSS maliciosa y `target=_blank`+`rel=noopener` mitiga parcialmente), pero es un hueco real. Fix trivial cuando se toque: whitelist `http/https` antes de asignar el href.

**Checkpoint.** Abrir `http://localhost:3000/pulse.html` en dos pestañas; forzar un enrich (comando de 1.5); la card aparece/actualiza en ambas sin recargar. El indicador debe decir LIVE.

---

## 1.8 — Robustez del pipeline

**Qué problema resuelve.** Que matar el worker o cortar la API LLM no pierda datos, y que el front no se quede mostrando "LIVE" sobre una conexión muerta.

**Código real y decisiones (las tres que importan).**
1. **DLX del broker eliminado; el failure transport de Symfony es el único dead-letter** (`backend/config/packages/messenger.yaml`). El `x-dead-letter-exchange` de `ingest`/`enrich` duplicaba cada reject de retry → 4 copias por fallo. Es el mismo antipatrón "dos mecanismos para el mismo trabajo" que ya conocés. Además se destapó un **bug latente de 0.5**: el transport `failed` publicaba sin `default_publish_routing_key` a un exchange direct → *unroutable* → RabbitMQ lo descartaba en silencio (lo enmascaraban las copias del DLX). Fix: routing key `failed` + bindear las tres keys (`failed`, `ingest`, `enrich`) porque `AmqpSender` reusa la routing key original al redeliver.
2. **Timeouts + retry HTTP** (`backend/config/packages/framework.yaml`): `timeout: 10`, `max_duration: 60`, `retry_failed` (2 reintentos). Capa por **debajo** del retry de Messenger — cada capa absorbe una escala de fallo distinta (HTTP: 429/5xx/blips; Messenger: fallos más largos; failure transport: parking permanente).
3. **Watchdog anti-zombie en `pulse.js`**: un `EventSource` proxeado puede quedar "zombie" (el upstream muere pero el proxy mantiene abierto el lado browser → `onerror` nunca dispara). Sin actividad SSE por 300s → teardown + reconexión + resync REST. Este fue un **hallazgo de la verificación**, no del plan.

**`app:failed:inspect`** (`FailedInspectCommand`): peek NO destructivo de la cola `failed` (`basic.get` sin ack + nack-requeue), porque el failure transport AMQP no es listable (`messenger:failed:show` no funciona, solo `retry`).

**Frontera.** Casi todo esto es refinamiento de cosas que ya entendés (Messenger/DLX/idempotencia). Lo genuinamente nuevo es la **semántica AMQP de mensajes unroutable** y la **degradación del cliente SSE** (zombie/watchdog/resync).

**Checkpoint.**
```bash
docker compose exec backend bin/console app:failed:inspect   # no consume; correlo 2x, mismo contenido
# Ver las capas de retry en acción: apuntá un adapter a un host inexistente y mirá 1s/2s/4s en los logs del worker.
```

---

## 2.1 — CoinGecko / MarketSnapshot (datos fuera del pipeline LLM)

**Qué problema resuelve.** Sumar datos de mercado (precio, market cap, volumen, %24h) como **contexto** para el impact score (2.5) y Market Now (2.4), **sin** meterlos en el pipeline de noticias.

**Código real.** Entidad `MarketSnapshot` + `MarketSnapshotRepository` (`findLatestPerAsset()`, `deleteOlderThan()`). `MarketDataProviderInterface` + `CoinGeckoProvider` (endpoint `/simple/price`, sin key). `MarketPollCommand` (`app:market:poll`) persiste un snapshot por asset y purga >24h en la misma corrida. Mapa CoinGecko-id→ticker en `services.yaml` (`bitcoin→BTC`, `ethereum→ETH`).

**Decisiones (la clave del hito).**
- **`MarketSnapshot` NO es un `NewsItem` ni pasa por `SourceAdapterInterface`.** Forzar un precio dentro de `NewsItem` habría inventado campos y —peor— lo habría mandado a `EnrichMessage`→Haiku, gastando tokens en "resumir un número". `MarketDataProviderInterface` es un contrato **separado** de `SourceAdapterInterface` (noticias). Esta es la aplicación más limpia del principio "lo que no necesita LLM no entra al pipeline LLM".
- **Sin dedup, con retención por tiempo**: un snapshot es legítimamente distinto cada vez (no hay clave natural de dedup como el `contentHash` de una URL). Se purga >24h en vez de acumular.
- **Sin cola**: no hay LLM de por medio, así que el comando persiste directo. No agregar colas sin necesidad real.
- **(Post-review Opus)** Se quitó un `requestWithBackoff()` manual del provider: el `retry_failed` de `framework.yaml` (1.8) ya reintenta 429 → el retry manual se pisaba (hasta 9 requests/poll). Mismo antipatrón del DLX.

**Checkpoint.**
```bash
docker compose exec backend bin/console app:market:poll -v
docker compose exec database psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
  -c "SELECT asset, price_usd, change_pct24h, fetched_at FROM market_snapshot ORDER BY fetched_at DESC LIMIT 4;"
```

---

# Parte B — Hitos 2.4–2.6 (revisión de weak points + estudio)

## 2.4 — "Market Now": resumen agregado vía Sonnet

**Qué problema resuelve.** Un panel con un resumen del mercado ahora mismo (precios + noticias que lo mueven), refrescado cada N minutos, generado por **una sola** llamada Sonnet por corrida — no un enriquecimiento por-item.

**Código real.** `MarketNowCommand` (`app:market:now`, cron cada 10') arma el contexto (≤15 `NewsItem` enriquecidos vía `findRecentEnrichedForSummary` + `findLatestPerAsset`), calcula un `sourceHash`, y **salta la llamada LLM si no cambió desde la corrida anterior** (líneas 56-64). `AnthropicMarketNowProvider` llama a `claude-sonnet-5`, `max_tokens=700`, `thinking:{type:disabled}`, prompt acotado (≤15 items, ≤240 chars c/u). Persiste `MarketNowSummary`, purga >7 días, publica a `crypto/market-now` en `try/catch`. Front: segundo `EventSource` en `pulse.js` (`connectMarketNow`), sin watchdog (panel secundario).

**Cómo funciona, paso a paso** (`MarketNowCommand::execute`):
1. **Junta el contexto.** `findRecentEnrichedForSummary(15)` (fetch-join de `Enrichment`, más nuevos primero) + `findLatestPerAsset()` (último snapshot por asset, deduplicado en PHP).
2. **Corte temprano.** Si no hay items **ni** snapshots → `SUCCESS` sin llamar a nada (líneas 50-54). Evita summarizar el vacío.
3. **Huella de la ventana.** `computeSourceHash` ordena los item-ids + `asset:fetchedAt` de cada snapshot y saca un SHA-256. Es la "firma" de con qué datos se generaría este resumen.
4. **Compara contra la última fila** (`findLatest()->getSourceHash()`). Si coincide → skip + log "No change" (líneas 59-64). *(Acá vive el weak point — ver abajo.)*
5. **Si difiere → `provider->summarize()`**: la **única** llamada Sonnet del hito.
6. **Persiste** `MarketNowSummary` con el hash, model, tokens y costo; **purga** >7 días; **publica** a `crypto/market-now` envuelto en `try/catch`.

**El provider es distinto del de Haiku en un punto clave de contrato.** `AnthropicMarketNowProvider::buildUserContent` arma **texto plano** (líneas "- BTC: \$X (24h: Y%)" para snapshots, "- [sentiment] resumen (tickers: …)" para noticias) y el `SYSTEM_PROMPT` pide **prosa libre de 3-4 oraciones, sin markdown**. Haiku, en cambio, pide un **JSON estructurado** que se parsea campo por campo. La diferencia importa: la salida de Market Now es un `string` que se muestra tal cual (no se parsea), así que no hay validación de forma — solo el chequeo de "texto no vacío" (línea 69-71). Es correcto para el caso de uso (un resumen para leer), pero explica por qué no hay defaults seguros como en el enrichment.

**Decisiones bien tomadas.**
- **Sonnet y no Haiku, una sola vez**: síntesis/agregación, no clasificación de volumen. Reservar Haiku para el por-item.
- **`thinking:{type:disabled}` explícito**: en Sonnet 5 omitirlo corre *adaptive* y gasta tokens de razonamiento en un digest que debe ser barato. Correcto y no obvio.
- **Topic Mercure separado** (`crypto/market-now`): no mezclar la forma de un resumen con la de un `NewsItem`.
- **Publish en `try/catch`**: una caída de Mercure no tira el comando (mismo criterio que `EnrichItemHandler`).

**Frontera (lo que ya dominás vs. lo nuevo).**
- **Ya lo conocés:** comando de consola disparado por cron (igual que `app:sources:poll`), publish Mercure en `try/catch` (igual que `EnrichItemHandler`), payload compartido REST↔Mercure (igual que `NewsItemPayload`), retención por tiempo (igual que `MarketSnapshot`).
- **Genuinamente nuevo:** (a) una **segunda familia de llamada LLM** — Sonnet para síntesis, con parámetros propios (`thinking:disabled`, `max_tokens` bajo) que no aplican al Haiku por-item; (b) un LLM cuyo **contrato de salida es "texto libre"**, no un shape parseable — se muestra crudo, no se valida por campo; (c) el patrón de **skip por huella de contenido** (`sourceHash`) como control de costo **a nivel de comando/ventana**, distinto de la caché por `contentHash` que ya conocés (que es **por-item**); (d) un **segundo `EventSource`** en el front sobre otro topic, con su propio backoff.
- **El mapeo mental que conviene fijar:** la caché de Haiku (Symfony Cache) evita **recomputar el mismo item**; el `sourceHash` de Market Now evita **regenerar la misma ventana agregada**. Misma idea de fondo (no pagar dos veces por lo mismo), **dos mecanismos y dos granularidades distintas**. Y es justamente el de Market Now el que no funciona en prod (weak point de abajo) — por eso vale tener claro que son cosas separadas: la caché por-item **sí** anda; el skip por-ventana **no**.

### 🔴 Weak point principal: el skip por `sourceHash` está **efectivamente muerto en producción**

> **✅ Estado: RESUELTO en working tree (sin commitear), 2026-07-03.** Fix aplicado: `computeSourceHash` ahora mezcla el **precio bucketeado** (paso relativo ~3%, `PRICE_BUCKET_RATIO=1.03`) en vez de `fetchedAt`. El `changePct24h` se **quitó del hash** (se descubrió al verificar que flickea por su cuenta —deriva sobre sus propios bordes de bucket y es redundante con el precio— reintroduciendo el problema; sigue yendo al prompt del LLM vía `buildUserContent`). Tolerancia elegida con datos medidos: ~3% saltea ~83% del drift <0.5% y refresca ante movimientos de ~2-3% (sub-1% es ruido). Verificado end-to-end en el stack de dev: tras un `market:poll` sin cambio material de precio, la segunda `market:now` saltea la llamada. La descripción de abajo se conserva como registro del hallazgo original.

Este es el hallazgo importante del hito y toca directamente el control de costo de §3.7.

**La cadena de evidencia:**
1. `crontab`: `app:market:poll` corre **cada 2 min**, `app:market:now` **cada 10 min**.
2. `MarketPollCommand` (líneas 35-48) inserta un `MarketSnapshot` **nuevo por asset en cada corrida**, incondicionalmente — no hay upsert ni dedup. `CoinGeckoProvider:37` fija `fetchedAt = new \DateTimeImmutable()` (precisión de microsegundo, distinto cada corrida).
3. `MarketNowCommand::computeSourceHash` (líneas 116-128) mezcla, por cada snapshot más reciente, `asset . ':' . fetchedAt->format(ATOM)`.
4. `findLatestPerAsset` devuelve el snapshot más nuevo por asset → su `fetchedAt` **avanza cada 2 min**.
5. **⇒** Entre dos corridas de `market:now` (10 min de separación) el `fetchedAt` del último snapshot **siempre** cambió → el `sourceHash` **siempre** difiere → la rama de skip (líneas 59-64) **nunca se toma** bajo cron → **Sonnet se llama cada 10 min, haya o no noticias nuevas.**

**Por qué la verificación de 2.4 no lo detectó:** el check (documentado en `agent-commits.md` [PASO 2.4]) fue "segunda corrida **inmediata** → skip confirmado". Correr el comando dos veces seguidas *sin un `market:poll` en el medio* deja el `fetchedAt` igual → el skip funciona. Pero ese escenario no es el de producción, donde el poll de 2 min siempre intercala snapshots nuevos. Es un caso clásico de "anda en el test, no en prod".

**Severidad real:** acotada, no catastrófica. `max_tokens=700` + `thinking` off + ~6 llamadas/hora ⇒ costo bajo. Pero **el guardrail que el runbook §2.4 vende como el control de costo del hito ("una corrida sin noticias nuevas NO dispara la API") no se cumple en la config desplegada.** El código que existe para ahorrar no ahorra.

**La tensión de diseño subyacente** (por qué no es un typo): el runbook §2.4 pidió explícitamente "cachear por ventana (`contentHash` de item-ids + **timestamp del snapshot**)". Ese diseño asumía snapshots que solo cambian cuando cambia el precio; pero 2.1 los persiste incondicionalmente cada 2 min. Es una **interacción entre dos hitos** (el diseño de 2.4 vs. la implementación de 2.1), no un error aislado.

**Opciones de fix (para cuando se retome, no ahora):**
- **Recomendada:** en `computeSourceHash`, en vez de `fetchedAt`, mezclar los **valores redondeados** del snapshot (ej. `price` a una tolerancia del ~0.5% y/o `changePct24h` a 1 decimal). Así una ventana genuinamente quieta (precio estable + sin noticias nuevas) sí saltea, y un movimiento real refresca. Es lo más fiel a la intención "skip cuando nada relevante cambió".
- Alternativa mínima: sacar los snapshots del hash y saltear solo por item-ids nuevos. Más simple, pero un movimiento de precio sin noticias nuevas no refrescaría Market Now (subvende el componente de precios del panel).
- Alternativa de raíz: que `market:poll` haga upsert por asset solo cuando el precio cambió materialmente (cambia también la semántica de `MarketSnapshot`, más invasivo).

### Weak points menores del hito
- **`AnthropicMarketNowProvider::summarize`** asume `content[0].text`. Con `thinking` deshabilitado eso es correcto (no hay bloque de thinking). Si alguien reactivara thinking, `content[0]` sería el bloque de razonamiento y el parse fallaría — hoy no es un bug, sí una suposición acoplada al `thinking:disabled`. Un error HTTP de Anthropic (`toArray()` lanza en 4xx/5xx) propaga como excepción → el comando falla y el cron reintenta a los 10 min: aceptable.
- **La purga de 7 días corre solo en el camino no-skip** (línea 79). Como el skip está muerto (ver arriba), en la práctica purga siempre; si el skip se arreglara, las filas viejas solo se limpiarían al reanudar actividad. Inocuo.

**Checkpoint (ahora comprobá que el skip funciona, post-fix):**
```bash
# 1) genera un summary   2) poll (snapshots nuevos, precio ~igual)   3) debe SALTEAR
docker compose exec -T backend bin/console app:market:now
docker compose exec -T backend bin/console app:market:poll
docker compose exec -T backend bin/console app:market:now
# La 3ª corrida debe imprimir "No change since last summary — skipping the LLM call".
# Antes del fix, imprimía "summary generated" (fetchedAt había cambiado).
docker compose exec -T database psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
  -c "SELECT count(*) FROM market_now_summary;"   # no crece entre corrida 1 y 3
```

### Caso de estudio (2.4): un "skip por huella" no puede hashear algo que **siempre** cambia

El bug de este hito es el más instructivo del recorrido — vale estudiarlo como **patrón**, no como error puntual. Estos son los cuatro aprendizajes, en orden en que aparecieron.

**Patrón 1 — la huella tiene que ser invariante cuando "no hay nada que hacer".** El guard de costo decía "si la ventana no cambió, no llames a Sonnet", y estaba testeado y aprobado. Pero no ahorraba nada: el `sourceHash` mezclaba el `fetchedAt` de los snapshots, y `app:market:poll` escribe una fila nueva cada 2 min con `fetchedAt = now()` — un valor **monótono, que cambia siempre**. Meter en una huella de "¿cambió algo?" un valor que siempre cambia garantiza que la huella siempre difiera y que el skip **nunca** dispare. **Regla:** *lo que hasheás para decidir "¿hace falta rehacer esto?" tiene que ser estable cuando la respuesta correcta es "no".* Un timestamp de captura jamás cumple eso.

**Patrón 2 — testeá el timing que realmente ocurre.** La verificación original corrió el comando **dos veces seguidas**, sin un `market:poll` en el medio → los snapshots no cambiaron → el skip disparó → "pasa". Pero ese no es el timing de producción, donde el poll de 2 min siempre intercala snapshots entre dos corridas de 10 min. El fix se validó **reproduciendo el timing real** (poll intercalado) — el checkpoint de arriba. *Un test que no reproduce la secuencia temporal real puede dar verde sobre un bug vivo.*

**Patrón 3 — bucketear un valor continuo introduce flicker de borde, y el ancho se elige con datos.** El fix fue hashear el **precio** en vez del `fetchedAt`. Pero el precio también cambia siempre (centavos por poll), así que hay que **bucketearlo** (redondear para que la deriva normal caiga en el mismo bucket). Ojo: reemplazar un continuo por un bucket **no es gratis** — cerca del borde, un cambio mínimo lo cruza igual (*boundary flicker*). Con buckets de ~1% medí que un drift de 0.5% volteaba el bucket el **50%** de las veces → el skip seguía sin servir. Hubo que elegir el ancho con una **tabla de probabilidad de flip** (no a ojo): ~3% saltea ~83% del drift <0.5% y refresca ante movimientos de ~2-3% (sub-1% es ruido en cripto).

**Patrón 4 — cada valor extra en la clave es otra fuente de flicker.** El primer intento agregó también `changePct24h` "para más sensibilidad". Al verificar, ese campo **flickeaba por su cuenta** (deriva sobre sus propios bordes) y encima es **redundante** (se deriva del precio) → reintrodujo justo el problema que el bucketing acababa de resolver. Se lo sacó de la huella (sigue yendo al prompt del LLM, solo que no decide el skip). **Regla:** *cada señal que metés en una clave de dedup/skip es otra oportunidad de que flickee; incluí el mínimo que capture "cambió algo material".*

**Cómo conecta con lo que ya sabés.** Es la misma familia que la caché por `contentHash` del enrichment: no pagar dos veces por lo mismo. La diferencia clave es que la caché por-item hashea un contenido **naturalmente estable** (la URL), mientras que esta "huella de ventana" se arma sobre datos **que cambian solos** — y ahí está el trabajo: hacer que la huella sea estable bajo "nada relevante cambió". Cuando diseñes cualquier skip/dedup/caché, la pregunta de oro es: **¿qué exactamente tiene que ser igual para no rehacer el trabajo, y estoy hasheando exactamente eso y nada más?**

---

## 2.5 — Impact score (heurística + salience, sin llamada LLM extra)

**Qué problema resuelve.** Priorizar el feed: dar a cada item un score 0–1 de "cuánto mueve el mercado", para ordenar/filtrar (el filtro es 2.6).

**Código real.** Columna `impactScore` (float, default 0) en `Enrichment`. La señal `salience` (0–1) se pide **dentro del mismo JSON del prompt de Haiku** (`AnthropicEnrichmentProvider::SYSTEM_PROMPT`, key `"salience"`) — **cero llamadas LLM nuevas**. `ImpactScorer::score()` combina `0.6·salience + 0.4·heurística`, con clamp 0–1. La heurística (`ImpactScorer::heuristic`) suma: +0.3 sentiment no-neutral, +0.3 asset class de alto impacto, hasta +0.2 por cantidad de tickers, +0.2 si algún ticker tuvo volatilidad ≥5% en 24h (vía `MarketSnapshotRepository`). Invocado en `EnrichItemHandler` antes del `flush()`.

**Cómo funciona, paso a paso:**
1. **Se agrega una key al prompt que ya corría.** `AnthropicEnrichmentProvider::SYSTEM_PROMPT` pedía `summary/sentiment/asset_class/tickers/entities`; se le sumó `salience` (0–1, con la definición "1 = evento market-moving mayor; 0 = rutina"). **No es un call nuevo** — es un número más en el JSON que Haiku ya devolvía por cada item.
2. **Se parsea con default seguro.** `$salience = is_numeric($raw) ? clamp(0,1) : 0.0` (líneas 106-107). Si el LLM devuelve basura o lo omite → 0.0, **no** 0.5 (una señal ausente no debe inflar el score).
3. **El handler pide el score antes de persistir.** `EnrichItemHandler` inyecta `ImpactScorer` y hace `->setImpactScore($this->impactScorer->score($result))` en el mismo builder que arma el `Enrichment` (línea 67), antes del `flush()`.
4. **`score()` mezcla las dos señales:** `0.6·salience` (lectura de contenido del LLM) + `0.4·heuristic` (datos objetivos), clamp final [0,1].
5. **`heuristic()` suma señales deterministas** sobre datos ya en mano. Sentiment, asset class y tickers salen del propio `EnrichmentResult`; **solo la volatilidad toca la DB** (`hasVolatileTicker` → `findLatestPerAsset` → busca si algún ticker del item se movió ≥5% en 24h).
6. **Se persiste en `Enrichment.impactScore`** y viaja solo en `NewsItemPayload` (REST + Mercure) — sin código extra, porque el payload ya es la fuente única de forma. El **filtro/orden** por ese campo es 2.6; 2.5 solo lo hace viajar.

**Decisiones bien tomadas.**
- **Salience en el JSON que ya existe**, no un segundo round-trip: la aplicación exacta del principio de costo. Un número más en el output ≈ tokens despreciables, cero requests nuevas.
- **Default 0.0 (no 0.5) cuando falta salience** (`AnthropicEnrichmentProvider:106-107`): una señal ausente no debe empujar el score al medio (sesgaría el ranking hacia arriba justo cuando el LLM falló). Mismo criterio que el default `neutral` de sentiment. Bien pensado.
- **Combinar salience + heurística**: salience puro no sabe si BTC se movió 12% hoy; la heurística pura ignora la lectura cualitativa. 60/40 (salience pesa más) da un ranking que ninguna sola daría.

**Frontera (lo que ya dominás vs. lo nuevo).**
- **Ya lo conocés:** la idempotencia (el score se computa **una vez**, en el enrich, no por request — mismo criterio que todo lo persistido en `Enrichment`), el DTO `EnrichmentResult`, y el patrón de **default seguro al parsear** el JSON del LLM (idéntico al que ya usabas con `sentiment`).
- **Genuinamente nuevo:** (a) el patrón de **piggyback de una señal LLM** — pedir un campo más "gratis" dentro de un call que ya pagás, en vez de un segundo round-trip (la aplicación más pura del control de costo aplicada a una *señal*, no a un dato); (b) **fusionar una señal subjetiva** (juicio del LLM) **con una objetiva** (heurística determinista sobre datos de mercado) en un score ponderado — un patrón de "modelo híbrido" barato; (c) una feature que **consume datos de otro subsistema** (`MarketSnapshot`, de 2.1) sin acoplarse a su pipeline, solo leyendo su repositorio.
- **El mapeo mental que conviene fijar:** 2.5 es la **contracara exacta** de 2.1/2.4. En 2.1 sacaste *datos* del pipeline LLM (un precio no se enriquece). En 2.5 agregás una *señal* **sin** sumar pipeline LLM (la salience viaja en el call que ya existía). Los tres hitos son el mismo principio —"no pagar Haiku/Sonnet de más"— aplicado a tres cosas distintas: un dato (2.1), un agregado (2.4), una señal (2.5).

### 🟡 Weak point 1: el bump de asset class es un acoplamiento frágil texto-libre ↔ lista exacta

`HIGH_IMPACT_ASSET_CLASSES = ['Regulation', 'Exchange']` y la comparación es `in_array($result->assetClass, ..., true)` — **estricta** (case-sensitive, match exacto). El valor viene del campo `asset_class` que **el LLM escribe libremente**; el `SYSTEM_PROMPT` de Haiku lo *sugiere* con ejemplos ("BTC", "ETH", "DeFi", "Regulation", "Stablecoin", "Layer2", "Exchange", "Market", "Altcoin"), pero no hay enum ni validación que lo garantice.

- En el **happy path** matchea: si Haiku devuelve exactamente `"Regulation"` o `"Exchange"`, suma +0.3.
- **Falla silenciosa** si Haiku devuelve `"regulation"` (minúscula), `"Regulatory"`, `"Regulations"`, `"Crypto Regulation"`, etc. → el `in_array` estricto no matchea → el +0.3 nunca se aplica y el score queda más bajo de lo que la heurística pretendía. No hay crash ni log: la señal simplemente no se dispara.
- **Choca con la propia verificación del runbook §2.5**, que espera que "regulación/hack de BTC en día volátil" ranquee alto. Un **hack** difícilmente se clasifica como `"Regulation"`; podría caer en `"Exchange"` (hack de exchange) y sumar, o en `"DeFi"`/`"Market"`/`"Security"` y **no** sumar. O sea: que un hack ranquee alto depende más de que el `salience` del LLM lo cargue que de la heurística de asset class. La heurística de clase es un bonus frágil, no la columna vertebral que el ejemplo sugiere.
- **Fix cuando se toque:** normalizar antes de comparar (`strtolower` en ambos lados) y/o hacer match por `str_contains` sobre un set de keywords (`regulat`, `exchange`, `hack`, `sec`), aceptando el ruido; o —más robusto— convertir `asset_class` en un enum cerrado validado al parsear (como ya se hace con `sentiment`). Hoy `sentiment` sí se valida contra una lista; `asset_class` no.

### 🟡 Weak point 2 (eficiencia): `findLatestPerAsset` se recarga entera por cada item enriquecido

`ImpactScorer::hasVolatileTicker` llama `snapshotRepo->findLatestPerAsset()` **una vez por cada `score()`**, es decir **una vez por cada item que se enriquece**. Y `findLatestPerAsset` (`MarketSnapshotRepository:25-41`) hace `SELECT` de **toda** la tabla `market_snapshot` ordenada y deduplica en PHP (no usa `DISTINCT ON (asset)` ni un `LIMIT`). Con retención de 24h y poll cada 2 min sobre 2 assets, la tabla ronda ~1.440 filas; en un burst de N noticias se cargan ~1.440 filas × N veces.

No es un bug (la tabla es chica) ni rompe nada, pero es trabajo O(todos los snapshots) por item, repetido. **Fix barato:** un método `findLatestPerAssetFor(array $tickers)` con `DISTINCT ON (asset) ... WHERE asset IN (:tickers) ORDER BY asset, fetched_at DESC`, o memoizar el resultado por corrida de worker. Anotado por si el volumen de assets crece (hoy solo BTC/ETH se pollean, así que la volatilidad *solo* puede dispararse para esos dos tickers — otra limitación implícita: un ticker que no sea BTC/ETH nunca suma el +0.2 de volatilidad porque no hay snapshot suyo).

### Nota de calibración (no bug, pero miralo)
Los pesos (0.6/0.4) y los incrementos (0.3/0.3/0.2/0.2) son razonables pero **no calibrados contra datos** — son un juicio de diseño. Está bien para el MVP y está documentado en el código; solo tené presente que "regulación en día volátil ≫ nota de color" es una hipótesis, no algo medido. Un item neutro sin tickers ni asset class de alto impacto y con salience 0 cae a **exactamente 0.0** (definido, no null/crash) — ese caso borde sí está bien cubierto y testeado (`ImpactScorerTest`).

**Checkpoint.**
```bash
# Distribución real de impact score y si el bump de asset class se está disparando:
docker compose exec database psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "
  SELECT asset_class, count(*), round(avg(impact_score)::numeric,3) AS avg_impact
  FROM enrichment GROUP BY asset_class ORDER BY avg_impact DESC;"
# Si ves 'Regulation'/'Exchange' con avg parecido al resto, el bump quizá no está matcheando (weak point 1).
```

---

## 2.6 — Filtros del dashboard

**Qué problema resuelve.** Filtrar el feed por fuente, clase de activo, sentiment, impacto mínimo y ticker — **sobre la carga REST y sobre el stream en vivo por igual**.

**Código real.** Backend: `findFeedPage` suma `minImpact` (`e.impactScore >= :minImpact`) y `ticker`; `FeedController` parsea y valida (`minImpact` en [0,1] → 400). Frontend: `feedUrl()` arma la query string; `matchesFilters()` aplica los mismos criterios a los eventos Mercure (que llegan **sin filtrar** del backend); `ensureOption()` puebla los selects desde los valores que el feed ya mostró; clic en un tag de ticker filtra por él.

**Cómo funciona, paso a paso** (y por qué el hito vive en dos lados):
1. **El backend filtra la carga inicial.** `feedUrl()` (front) traduce el estado `filters` a query params; `FeedController` los parsea y valida; `findFeedPage` los aplica como `andWhere` condicionales (uno por filtro presente). Este es el camino de la **carga REST** y del **resync** tras reconectar.
2. **El cliente filtra el stream en vivo.** Los eventos Mercure llegan **sin filtrar** — el `EnrichItemHandler` publica a `crypto/feed` para todos los suscriptores, sin saber qué filtro tiene cada uno. Por eso `upsert()` pasa cada evento por `matchesFilters()` antes de meterlo al DOM (y **saca** una card que ya estaba si dejó de matchear).
3. **El punto conceptual del hito:** el mismo criterio de filtrado está implementado **dos veces, en dos lenguajes** (SQL en el repo, JS en el cliente). Eso es exactamente donde nacen las divergencias sutiles — de ahí que la sección "Consistencia REST↔cliente" de abajo verifique filtro por filtro que coinciden.
4. **Detalles de UX que no necesitan endpoint nuevo:** `ensureOption()` puebla los selects de `source`/`assetClass` con lo que el feed ya mostró (no hay endpoint de "valores distintos"); el click en un tag de ticker setea el filtro. Todo derivado de datos que ya están en pantalla.

**Decisiones bien tomadas.**
- **Filtrar también el stream en vivo** (`matchesFilters` en `upsert`): el publish de Mercure no sabe qué filtro tiene cada cliente, manda todo. Sin esto, con un filtro activo verías aparecer items que no matchean apenas se enriquece una noticia. `upsert` también saca del DOM un item que ya estaba y dejó de matchear (re-enriquecido). Consistencia REST↔vivo bien cuidada.
- **Selects poblados desde el feed** (`ensureOption`), no un endpoint de "valores distintos": `source`/`assetClass` son valores abiertos (el prompt de Haiku no los fija). Costo aceptado: un valor que nunca apareció en el feed cargado no está como opción (y filtrar por él no mostraría nada de todos modos).

### Detalle correcto que vale entender: el filtro de ticker en SQL nativo
`tickers` es una columna `json` **plana** (no `jsonb`), así que Postgres no tiene `@>` ni `LIKE` directo sobre ella (`operator does not exist: json ~~ unknown`). En vez de registrar una función DQL `CAST` custom para un solo filtro, `findFeedPage` resuelve los ids que matchean con una query nativa acotada (`SELECT news_item_id FROM enrichment WHERE tickers::text LIKE '%"BTC"%'`) y filtra el DQL por `n.id IN (:ids)`, con **corte temprano** (`total=0`) si no hay matches para no mandar un `IN ()` vacío. Las comillas en el patrón (`%"BTC"%`) anclan el match para que `BTC` no matchee `BTCUP`. Bien resuelto.

### Consistencia REST ↔ cliente (la verifiqué, coincide)
| Filtro | Backend (SQL) | Cliente (`matchesFilters`) | ¿Coincide? |
|---|---|---|---|
| source | `n.source = :source` (exacto) | `item.source !== filters.source` | ✅ |
| assetClass | `e.assetClass = :assetClass` (exacto) | `item.assetClass !== ...` | ✅ |
| sentiment | `e.sentiment = :sentiment` | exacto | ✅ |
| minImpact | `e.impactScore >= :minImpact` | `(item.impactScore ?? 0) < Number(...)` → descarta | ✅ (mismo `>=`) |
| ticker | `tickers::text LIKE '%"BTC"%'` (substring anclado) | `(item.tickers ?? []).includes(filters.ticker)` (exacto) | ✅ en la práctica (el ancla de comillas ≈ match exacto de elemento) |

**Frontera (lo que ya dominás vs. lo nuevo).**
- **Ya lo conocés:** el `QueryBuilder` con `andWhere` condicionales, la paginación con `COUNT` separado, y el payload compartido (`NewsItemPayload`) que hace que la card se renderice igual venga de REST o de Mercure.
- **Genuinamente nuevo:** (a) el problema de **consistencia entre dos planos de filtrado** — server-side para la carga/resync, client-side para el push en vivo — donde el mismo criterio se codifica dos veces y cualquier desalineación es un bug silencioso (por eso la tabla de arriba); (b) **filtrar sobre una columna `json` plana** (no `jsonb`), que no soporta `@>` ni `LIKE` directo, resuelto con una query nativa acotada + `IN (:ids)` en vez de una función DQL custom; (c) **poblar la UI desde datos ya vistos** (`ensureOption`) en lugar de un endpoint de metadata, aceptando el límite de que un valor nunca visto no aparece como opción.
- **El mapeo mental que conviene fijar:** en Fase 1 el front tenía **un solo** origen de verdad renderizable (todo lo que llegaba se mostraba). 2.6 introduce un **filtro que el front tiene que hacer respetar sobre dos flujos que no comparten el mismo punto de filtrado** — el backend filtra lo que le pedís, pero el hub difunde todo. Ese desajuste (el productor no conoce el filtro del consumidor) es el mismo que verás en cualquier sistema pub/sub con vistas filtradas, y la solución acá (filtrar en el borde del cliente) es el patrón estándar.

### Weak points menores del hito
- **Metacaracteres de `LIKE` sin escapar en el ticker**: el input va parametrizado (`:ticker`), así que **no hay inyección SQL**, pero un `%` o `_` en el input del usuario funcionaría como comodín de `LIKE` (`_` matchea cualquier char). Como los tickers son alfanuméricos cortos (y el front los uppercasea), es un caso borde inofensivo. Si molesta: `addcslashes($ticker, '%_\\')`.
- **`minImpact` con `?minImpact=0`**: en `FeedController:38`, `$request->query->get('minImpact') ?: null` trata `"0"` como *ausente* (`"0"` es falsy en PHP) → un filtro `minImpact=0` se ignora. Semánticamente `>=0` es "todo", así que el resultado es el mismo; no es un bug observable, pero es la clase de coalescencia `?:` que sí mordería si el umbral fuera un valor donde "0" importa. Anotado como patrón a vigilar, no como defecto activo. Mismo patrón (`?:`) en `source`/`sentiment`/`assetClass`/`ticker`, donde `"0"` no es un valor válido, así que ahí es inocuo.
- **El feed filtrado está capado a 30** (`FEED_BASE='/api/feed?limit=30'`) y no hay paginación en la UI: si un filtro matchea >30 items solo ves los 30 más nuevos. Correcto para un dashboard en vivo, pero tenelo presente.

**Checkpoint.**
```bash
curl -s 'http://localhost/api/feed?minImpact=0.5&limit=5' | jq '.meta.total'
curl -s 'http://localhost/api/feed?sentiment=positive' | jq '.meta.total'   # 0 en dev: NullEnrichmentProvider solo da neutral
curl -s 'http://localhost/api/feed?minImpact=2'         | jq .              # 400: fuera de [0,1]
```

---

# Parte C — Auditoría transversal

## §3.7 — Controles de costo LLM: ¿sobrevivieron?

| Control (§3.7) | Estado | Nota |
|---|---|---|
| (a) Enriquecer **una sola vez** (idempotencia) | ✅ intacto | `EnrichItemHandler` guard por `status` + caché por `contentHash`. `MarketSnapshot`/Market Now nunca tocan el pipeline por-item. |
| (b) **Caché** prompt→respuesta | ✅ intacto | `enrichmentCache` filesystem 24h; evita re-llamar en retries. |
| (c) **Prompt caching** de Anthropic | 🟡 no-op (documentado) | System prompt de Haiku (~250 tok) < mínimo cacheable (2048). El header `anthropic-beta: prompt-caching-2024-07-31` sigue en `AnthropicEnrichmentProvider:61` aunque ya es GA — ruido inofensivo. El ahorro real lo da (b). |
| (d) **Límite de gasto/rate configurable** | ❌ **no implementado** | No hay tope de gasto ni kill-switch global. `max_tokens` acota el output por llamada, pero nada frena el gasto acumulado si el volumen se dispara. El runbook lo lista como *obligatorio*; en la práctica quedó diferido sin anotarlo. Ver "Qué sigue sin cerrarse". |
| (e) **Métrica de costo** (Grafana) | ⏳ Fase 3 | El `costUsd` se **loguea** por llamada (Haiku y Sonnet) y se persiste (`Enrichment.costUsd`, `MarketNowSummary.costUsd`), pero no hay dashboard todavía. |

**Lo nuevo de 2.4/2.5 respetó el espíritu de costo:** 2.5 no agregó ninguna llamada (salience va en el JSON de Haiku); 2.4 usa una sola llamada Sonnet por corrida con `thinking` off y `max_tokens=700`. El único agujero de costo real es que **el skip de 2.4 no funciona** (ver weak point de 2.4): no dispara un gasto grande, pero convierte "llamamos solo si cambió algo" en "llamamos siempre cada 10 min".

## §7 — Anti-scope: ¿se coló algo?

**Limpio.** Nada fuera de scope. No hay estrategias de trading, ni knowledge graph, ni SPA (el dashboard sigue siendo Vanilla JS + una página estática más), ni k8s, ni auth compleja. Los filtros, el impact score y Market Now son features previstas en Fase 2. `MarketSnapshot` explícitamente **no** se sobre-modeló como serie histórica (retención 24h). Buen control de alcance.

## §12 / §4 — Checklist maestro y tracking de fases

- El **§12** ("listo para producción") es casi todo Fase 3 y sus casilleros sin tildar reflejan bien la realidad (deploy, observabilidad, backups, secrets, CI/CD — nada de eso existe aún). No requiere corrección.
- El único casillero de §12 que **conviene matizar** es el de **"Control de costo LLM (caché, prompt caching, límite, métrica)"**: está sin tildar (correcto), pero vale explicitar que la parte de *límite de gasto* (§3.7d) no existe ni siquiera embrionaria, y la de *prompt caching* es un no-op.
- El **§4** (runbook por fases) **no tiene checkboxes para Fase 2**: 2.1/2.4/2.5/2.6 figuran como texto plano, sin `[x]`. El tracking de "qué está hecho" vive en `CLAUDE.md` → "Estado del proyecto" y en `agent-commits.md`, que **sí** reflejan el estado real (2.4/2.5/2.6 done, 2.2/2.3 bloqueados). Recomendación (cuando quieras, no en esta sesión read-only): marcar 2.1/2.4/2.5/2.6 como ✅ en §4 y dejar 2.2/2.3 explícitamente como ⛔ bloqueados, para que el runbook no dependa de dos docs externos para saber dónde se está.

---

# Qué sigue sin cerrarse

**Bloqueantes de construcción (requieren decisión/estudio de Marcos antes de codear):**

1. **2.2 — Búsqueda semántica: NO construida.** Confirmado por inspección: no existe ruta `/api/search`, ni query kNN, ni uso del operador `<=>`. Las únicas menciones a "semantic search" son dos comentarios (`EmbeddingProviderInterface`, `Enrichment.embedding`). No hay nada que auditar. **Prerrequisito:** el estudio de pgvector/HNSW que tenés pendiente — diseño del índice (parámetros `m`/`ef_construction`), operador de distancia (`vector_cosine_ops`), tuning, y degradación con inserciones incrementales. Además hay un **gap de re-embedding**: los items enriquecidos sin `VOYAGE_API_KEY` quedan con `embedding=null` permanente; la búsqueda los ignoraría. Hará falta un comando de re-embed antes de 2.2.
2. **2.3 — Clustering/dedupe por tema: NO construido.** Ídem: nada en el código. Depende del mismo estudio de embeddings que 2.2.

**Deudas/hallazgos abiertos del recorrido 1.5–2.6 (no bloquean, pero conviene registrarlos):**

3. **[2.4] El skip por `sourceHash` de Market Now está muerto en producción. ✅ RESUELTO Y COMMITEADO (`cc75b24`, registrado en `agent-commits.md` por `a4d7fef`).** Era: `market:poll` (cada 2') escribe snapshots con `fetchedAt` nuevo, `computeSourceHash` lo incluía ⇒ Sonnet cada 10' sí o sí. Fix aplicado: hash sobre precio bucketeado (~3% relativo), `changePct24h` fuera del hash (flickea solo), verificado end-to-end. (Detalle en el hito 2.4.)
4. **[2.5] El bump de asset class es un match exacto contra texto libre del LLM.** `['Regulation','Exchange']` con `in_array(...,true)` falla en silencio si Haiku devuelve otra variante de casing/etiqueta. Fix: normalizar o validar `asset_class` como enum. (Detalle en 2.5.)
5. **[2.5] `findLatestPerAsset` se recarga entera por cada item enriquecido** (ineficiencia O(snapshots)×items, hoy inocua). Fix: query acotada por tickers o memoización.
6. **[§3.7d] No existe límite de gasto/rate configurable.** El runbook lo marca obligatorio; quedó diferido sin anotar. Definir dónde vive (config + kill-switch, o tope por ventana) antes de un deploy con `ANTHROPIC_API_KEY` real y volumen.
7. **[CI/deuda conocida] `doctrine:schema:validate` en rojo** por el tipo `vector` (no round-trippea `length`) + índice HNSW en SQL crudo. Ligado al mismo estudio pgvector. Romperá el CI cuando el schema de CMP llegue a `push:main`. No tocar hasta cerrar el estudio.
8. **[1.7, tier liviano] `href` sin validar esquema en `card()`** (`pulse.js`): potencial `javascript:` URL desde una fuente comprometida. Riesgo bajo; fix trivial (whitelist http/https) cuando se toque el front.
9. **[c] Prompt caching de Anthropic es no-op** (system prompt < 2048 tok) y el header beta ya es GA. Deuda cosmética; el ahorro real lo da la Symfony Cache.

**Nada de lo anterior es un crash en el happy path.** Los tres hitos nuevos (2.4/2.5/2.6) funcionan y están testeados; los weak points son de robustez, calibración y —en el caso del skip de 2.4— de un control de costo que existe pero no se activa. El sistema está sano para seguir; estos son los bordes a mirar antes de v3 y antes de encender la key real en el VPS.

---

# Anexo — Auditoría de reanudación (2026-10-07, tras ~3 meses de pausa)

Sesión de diagnóstico sin construir nada. Se levantó el stack de dev tal cual quedó y se corrieron los checkpoints de este documento contra el sistema vivo.

## El sistema sobrevivió intacto

6/6 containers healthy **sin rebuild** (imágenes de julio arrancaron tal cual), migraciones 5/5 al día (0 nuevas), y el pipeline completo fluyó end-to-end: `app:sources:poll` → cola → worker → `EnrichItemHandler: enriched` → `POST /.well-known/mercure` `200` → `/api/feed`. Entraron **54 noticias reales nuevas** de CoinDesk/Cointelegraph en la corrida. CoinGecko respondió con precios reales. Las purgas por retención funcionaron solas (snapshots >24h; `market_now_summary` pasó de 8 filas de julio a 1 nueva). Gasto de tokens: **cero** — `services_dev.yaml` tiene aliasados `NullEnrichmentProvider` y `NullMarketNowProvider`.

También se verificó en vivo la validación de 2.6 (`minImpact=2` → `400`) y las 13 keys de `NewsItemPayload`.

## Hallazgos nuevos (no estaban en el recorrido original)

**A. 53 `news_item` huérfanos con `status='enriched'` y sin fila en `enrichment`.** Todos del **2026-06-01** (día uno del proyecto). El feed no los expone porque `findFeedPage` usa `innerJoin` (por eso `/api/feed` reporta `total=223` sobre 276 items). No rompe nada hoy, pero es un `status` que miente sobre el estado real, y esos items serían invisibles para la búsqueda semántica de 2.2. Casi con certeza un artefacto de los primeros pasos, anterior al pipeline completo. **Decisión pendiente:** backfillearlos (re-encolar enrichment) o corregirles el `status`.

**B. El gap de embeddings es TOTAL, no parcial.** `VOYAGE_API_KEY` está **vacía** (longitud 0) y **169 de 169** enrichments tienen `embedding = NULL`; los 54 nuevos también. El texto de arriba decía "los items sin key quedan con embedding null"; la medición dice que es el **100% del corpus**. Para 2.2 no existe ni un solo vector. El comando de re-embed no es un paso previo menor: es **prerrequisito duro**, y antes hay que decidir si se paga Voyage o se cambia de proveedor de embeddings.

**C. El índice HNSW ya existe y es PARCIAL.** En el schema vivo:
```
"hnsw_enrichment_embedding" hnsw (embedding vector_cosine_ops) WHERE embedding IS NOT NULL
```
El estudio de pgvector **no arranca de cero**: ya hay dos decisiones de diseño tomadas (distancia coseno + índice parcial sobre los no-nulos) que conviene entender y validar antes de re-decidir. Es además el objeto exacto que mantiene `doctrine:schema:validate` en rojo (ítem 7 de arriba).

**D. Cuello de botella confirmado: el estudio pgvector/HNSW bloquea más de lo documentado.** No solo 2.2 y 2.3. El hito **3.4** del runbook pide "habilitar **todos** los pasos del `ci.yml`" y **3.5** monta el CI/CD encima; con `schema:validate` en rojo, 3.4 no se puede cerrar con honestidad. O sea que el estudio es el chokepoint de 2.2 + 2.3 + 3.4 + 3.5 + la deuda del diff espurio recurrente.

**E. Erratas de checkpoints.** El checkpoint de 2.1 decía `change_pct_24h`; la columna real es `change_pct24h`. Corregido en este commit. Al correr checkpoints, verificar nombres contra `\d <tabla>` antes de asumir.

## Conteo real de hitos

Fase 0: 8/8 ✅ · Fase 1: 8/8 ✅ · Fase 2: 4/7 (2.1 parcial —CryptoPanic en espera indefinida—, 2.4, 2.5, 2.6 ✅; 2.2/2.3 ⛔ bloqueados; 2.7 opcional sin construir) · Fase 3: 0/8. **Total completado: 20 de 31 hitos.**

Nota de tracking: §4 del runbook sigue sin checkboxes para Fase 2 — el estado real vive en `CLAUDE.md` y `agent-commits.md`. Conviene marcar 2.1/2.4/2.5/2.6 como ✅ y 2.2/2.3 como ⛔ para que el runbook se baste solo.
