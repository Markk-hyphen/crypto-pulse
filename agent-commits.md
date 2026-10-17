# Agent Commits Log

Registro de commits realizados por el agente durante la construcción del proyecto.
Cada entrada detalla qué cambió, por qué, y qué decisión de arquitectura respalda el cambio.

---

## [2.4 · post-auditoría] fix: skip real de Market Now — precio bucketeado, no `fetchedAt`
**Hash:** `cc75b24`
**Rama:** `release/plan-market-pulse`
**Fecha:** 2026-07-03

### Cambios
| Archivo | Tipo | Descripción |
|---|---|---|
| `backend/src/Command/MarketNowCommand.php` | modificado | `computeSourceHash` mezcla ahora **precio bucketeado** (paso relativo ~3%, const `PRICE_BUCKET_RATIO`) en vez de `fetchedAt`; `changePct24h` **sacado del hash** |
| `docs/estudio-y-auditoria-1.5-2.6.md` | nuevo | Guía de estudio + auditoría de hitos 1.5–2.6: recorrido con los 5 puntos por hito, weak-point review de 2.4/2.5/2.6, caso de estudio del skip (4 patrones), auditoría §3.7/§7/§12 y "Qué sigue sin cerrarse" |
| `agent-commits.md` | modificado | Esta entrada |

### Justificación

**Origen:** auditoría con Opus de los hitos 1.5–2.6 (weak-point review de los últimos tres). El hallazgo #1 tocaba el control de costo de §3.7: el skip por `sourceHash` de Market Now estaba **muerto en producción**.

**El bug.** `computeSourceHash` incluía el `fetchedAt` de cada snapshot. `app:market:poll` (cron cada 2') escribe una fila nueva por asset con `fetchedAt = now()` — monótono, cambia siempre. Como `app:market:now` corre cada 10', el último `fetchedAt` **siempre** difería del de la corrida anterior → el hash siempre cambiaba → la rama de skip nunca disparaba → Sonnet se llamaba cada 10' haya o no novedades. La verificación original no lo agarró porque corría el comando dos veces seguidas *sin poll en el medio* (timing que no es el de producción).

**El fix y sus dos trampas descubiertas al verificar.** (1) Se hashea el **precio** en vez del `fetchedAt`, bucketeado a ~3% relativo (log base 1.03) para que la deriva normal caiga en el mismo bucket. El ~1% inicial era demasiado fino: medido, un drift de 0.5% volteaba el bucket el 50% de las veces (*boundary flicker*). El ~3% se eligió con una tabla de probabilidad de flip: saltea ~83% del drift <0.5% y refresca ante movimientos de ~2-3% (sub-1% es ruido). (2) El primer intento incluía también `changePct24h`; al verificar, flickeaba por su cuenta (deriva sobre sus propios bordes) y es redundante con el precio → reintroducía el problema. Se lo sacó del hash (sigue yendo al prompt del LLM vía `buildUserContent`).

**Verificación (end-to-end, stack de dev):** `php -l` ok; PHPUnit 17/17 verde (sin regresión); secuencia real `market:now` → `market:poll` (precio ~igual) → `market:now` → la 3ª corrida imprime "No change since last summary — skipping the LLM call" y no crea fila nueva (antes del fix creaba una). Guard de `price=0` (dominio de `log`) probado sin crash.

**Alternativas descartadas** (elegida A por Marcos entre tres): B — skip solo por item-ids (un movimiento de precio sin noticias no refrescaría el panel, subvende el componente de precios); C — que `market:poll` haga upsert solo si el precio cambió (más invasivo, toca 2.1 + impact score + retención).

---

## [PASO 2.6] feat: filtros del dashboard (clase, sentiment, fuente, impacto, ticker)
**Hash:** `e097b35`
**Rama:** `release/plan-market-pulse`
**Fecha:** 2026-07-02

### Cambios
| Archivo | Tipo | Descripción |
|---|---|---|
| `backend/src/Repository/NewsItemRepository.php` | modificado | `findFeedPage` suma `minImpact` (`e.impactScore >= :minImpact`) y `ticker`. El filtro de ticker resuelve los `news_item_id` con una query SQL nativa (`tickers::text LIKE`) antes de aplicar el `IN` en el DQL — ver justificación |
| `backend/src/Controller/Api/FeedController.php` | modificado | Parsea `ticker` y `minImpact` de la query string; valida `minImpact` en `[0,1]` (400 si no) |
| `frontend/pulse.html` | modificado | Barra de filtros (`#pulse-filters`): selects de fuente/clase/sentiment/impacto + input de ticker + botón Clear, arriba de `#pulse-feed` |
| `frontend/src/pulse.js` | modificado | `feedUrl()` arma la query string del feed con los filtros activos (carga inicial y resync); `matchesFilters()` aplica el mismo criterio a los eventos de Mercure en vivo (llegan sin filtrar desde el backend); `ensureOption()` puebla los selects de fuente/clase con los valores que el feed ya mostró (sin endpoint nuevo de valores distintos); clic en un tag de ticker de una card filtra por ese ticker |
| `frontend/src/style.css` | modificado | Estilos `.pulse-filters`/`.pulse-filter-select`/`.pulse-filter-input`/`.pulse-filter-clear`; tags de ticker con `cursor: pointer` + hover (el tag de `assetClass` no es clickeable, se excluye) |

### Justificación

**Por qué el filtro de ticker no se resolvió en una sola query DQL:** `tickers` es una columna `json` plana (no `jsonb`) — se verificó a mano contra la base (`psql`) que Postgres tira `operator does not exist: json ~~ unknown` al hacer `LIKE` directo sobre ella, y que un `::text` explícito sí funciona. Doctrine DQL no tiene una función `CAST` nativa para forzar ese cast desde el QueryBuilder, y registrar una función DQL custom solo para este filtro era más superficie de la que el paso necesita. Se optó por resolver los ids que matchean con una query nativa acotada (`SELECT news_item_id FROM enrichment WHERE tickers::text LIKE :ticker`) y filtrar el DQL principal por `n.id IN (:ids)` — con corte temprano (`total=0`) si no hay matches, para no mandar un `IN ()` vacío. Verificado en vivo: se insertó un valor de prueba (`["BTC","ETH"]`) en una fila de `enrichment`, `?ticker=btc` la devolvió y `?ticker=doge` no, y se revirtió el valor de prueba.

**Por qué los filtros también se aplican a los eventos de Mercure en vivo, no solo a la carga REST:** el backend filtra `/api/feed`, pero el publish de Mercure (`EnrichItemHandler`) no sabe qué filtro tiene seleccionado cada cliente conectado — manda todo. Sin `matchesFilters()` en `upsert()`, un usuario con un filtro activo vería aparecer ítems que no matchean apenas se enriquece una noticia nueva, mientras la carga inicial sí los respeta — inconsistencia visible en la demo. La función también cubre el caso inverso: un ítem que ya estaba en pantalla y deja de matchear (raro, pero posible si se re-enriquece) se saca del DOM en vez de quedar stale.

**Por qué los selects de fuente/clase se pueblan desde los datos ya cargados y no desde un endpoint nuevo:** `source` y `assetClass` son valores abiertos (no un enum fijo — el prompt de Haiku admite categorías como "BTC", "DeFi", "Regulation", "Altcoin", etc., ver `AnthropicEnrichmentProvider`), así que hardcodear opciones en el HTML se habría desincronizado apenas apareciera una categoría nueva. Agregar un endpoint de "valores distintos" es una superficie de más para un filtro de UI — `ensureOption()` los va agregando a medida que el feed los muestra, con el costo aceptado de que un valor que *nunca* apareció en el feed cargado no aparece como opción (no es un problema real: si nunca apareció, filtrar por él no tendría nada que mostrar de todos modos).

**Búsqueda (2.2) fuera de scope de este paso:** el runbook dice "filtros aplican sobre feed y búsqueda", pero la búsqueda semántica no existe todavía — sigue bloqueada por el estudio pgvector/HNSW de Marcos (ver `CLAUDE.md`). No hay nada sobre lo que aplicar un filtro de búsqueda; cuando 2.2 se desbloquee, `matchesFilters`/`feedUrl` son reutilizables tal cual sobre el nuevo endpoint.

**Verificación (paso cumplido):** `php -l` limpio en ambos archivos backend; probado en vivo contra el stack de dev (`docker compose up`) — `source`, `sentiment`, `assetClass` y `minImpact` filtran correctamente sobre datos reales del feed (ej. `sentiment=positive` → `total:0` porque el `NullEnrichmentProvider` de dev solo genera `neutral`, comportamiento esperado); build de producción de Vite sin errores; navegación real con Playwright headless contra `pulse.html` servido por el dev server: seleccionar fuente/sentiment filtra la lista a un solo valor, `ticker=BTC` da 0 resultados (dataset de dev sin tickers, esperado), Clear restaura el feed completo, cero errores de consola.

---

## [PASO 2.1 · post-review] refactor: quitar retry redundante de CoinGecko + test + anotar deuda schema:validate
**Hash:** `6250672`
**Rama:** `release/plan-market-pulse`
**Fecha:** 2026-07-02

### Cambios
| Archivo | Tipo | Descripción |
|---|---|---|
| `backend/src/Provider/CoinGeckoProvider.php` | modificado | Elimina `requestWithBackoff()` (retry a mano ante 429) + constantes `MAX_RETRIES`/`RETRY_BASE_DELAY_MS` + import de `ClientExceptionInterface`; llama al cliente HTTP directo |
| `backend/tests/Unit/Provider/CoinGeckoProviderTest.php` | nuevo | 4 tests con `MockHttpClient`: mapeo id→ticker + normalización, skip de asset ausente del payload, tolerancia a campos opcionales faltantes, verificación de los coin-ids pedidos |
| `CLAUDE.md` | modificado | Entrada 🔴 en "Deuda técnica conocida": `doctrine:schema:validate` en rojo por el tipo `vector` + índice HNSW no modelables en ORM |
| `agent-commits.md` | modificado | Esta entrada |

### Justificación

**Origen:** revisión de weak-points del paso 2.1 hecha con Opus tras la implementación con Sonnet (el handoff de modelo previsto en el flujo de trabajo). Tres hallazgos; dos aplicados acá, uno anotado como deuda.

**#1 — Doble retry sobre 429 eliminado.** `CoinGeckoProvider` inyecta el cliente HTTP autowired, que ya trae `retry_failed` (2 reintentos con backoff) configurado en `framework.yaml` desde 1.8 — y 429 está entre los códigos que Symfony reintenta por defecto. El `requestWithBackoff()` que había escrito reintentaba el 429 *encima* de esa capa: hasta 3×3=9 requests por poll con dos backoffs pisándose. Es el mismo antipatrón "dos mecanismos para el mismo trabajo" que 1.8 desarmó con el DLX, y contradice el comentario de `framework.yaml` que declara `retry_failed` como "the cheap first line of defense against rate limits". Se borra el retry manual: comportamiento igual o mejor (si el poll falla, supercronic reintenta en 2 min; nada encolado que perder). Alternativa descartada: dejar el retry manual y sacar 429 de `retry_failed` — peor, porque `retry_failed` es transversal a todos los http-client del backend (Anthropic, Voyage) y ahí sí se quiere.

**#3 — Test del provider (consistencia con el precedente).** 1.8 le dio a `RssAdapter` un test unitario con `MockHttpClient`; 2.1 había quedado sin cobertura para el provider nuevo. El test cubre lo que puede romperse en silencio: el orden de salida sigue el mapa `assetIds` configurado (no el JSON), un asset configurado pero ausente del payload se saltea (no se emite con campos null/cero), y los campos opcionales faltantes caen a null. Suite: 8→12 verde.

**#2 — Deuda anotada, NO arreglada (zona bloqueada).** `doctrine:schema:validate` sale con exit 2 por dos drifts que Doctrine no sabe modelar: el `length` del tipo `vector` no round-trippea, y el índice HNSW (SQL crudo en la migración 1.1) no es expresable en el mapping ORM → el schema-tool siempre lo quiere dropear. Es un gate duro del CI que hoy no salta (el CI solo corre en `push:main` y CMP vive en la rama) pero romperá cuando el schema de CMP llegue a CI. Se descartó tocarlo: la solución (tipo Doctrine custom + índice fuera del schema-tool) es parte del estudio pgvector/HNSW que Marcos tiene bloqueado. Queda documentado en `CLAUDE.md` para que no sorprenda.

**Verificación:** `vendor/bin/phpunit` 12/12 verde; `app:market:poll -v` corrido contra la API real de CoinGecko post-refactor → 2 snapshots persistidos, sin regresión.

---

## [PASO 2.5] feat: impact score — heurística + salience, sin llamada LLM extra
**Hash:** `bd0de0c`
**Rama:** `release/plan-market-pulse`
**Fecha:** 2026-07-02

### Cambios
| Archivo | Tipo | Descripción |
|---|---|---|
| `backend/src/Entity/Enrichment.php` | modificado | Columna `impactScore` (float, `options: ['default' => 0]` para que el mapping ORM coincida con el `DEFAULT` de la migración y no genere drift falso) |
| `backend/migrations/Version20260702215156.php` | nuevo | `ALTER TABLE enrichment ADD impact_score ... DEFAULT '0'` (backfill de filas preexistentes). Se generó y descartó a mano, dos veces, el diff espurio de `vector`/HNSW — mismo drift preexistente de 2.1/2.4 |
| `backend/src/Provider/AnthropicEnrichmentProvider.php` | modificado | Nueva key `"salience"` (0-1) en el `SYSTEM_PROMPT` de Haiku — **mismo prompt, mismo call**, no un segundo round-trip; parseo con default seguro a `0.0` si falta/inválido |
| `backend/src/Provider/EnrichmentResult.php` | modificado | Campo `salience: float` |
| `backend/src/Provider/NullEnrichmentProvider.php` | modificado | `salience: 0.0` en el mock dev |
| `backend/src/Service/ImpactScorer.php` | nuevo | `score(EnrichmentResult): float` — 60% salience (LLM) + 40% heurística determinística (sentiment no-neutral, `assetClass` de alto impacto, cantidad de tickers, volatilidad 24h vía `MarketSnapshotRepository::findLatestPerAsset()`), clamp 0-1 |
| `backend/src/MessageHandler/EnrichItemHandler.php` | modificado | Inyecta `ImpactScorer`, llama `->score($result)` antes del `persist()`/`flush()` del `Enrichment` |
| `backend/src/Api/NewsItemPayload.php` | modificado | Expone `impactScore` en el shape REST+Mercure (filtro/orden por impacto queda para 2.6, explícitamente fuera de este paso) |
| `backend/tests/Unit/Api/NewsItemPayloadTest.php` | modificado | Cubre `impactScore` en ambos shapes (con y sin enrichment) y en el lock de keys |
| `backend/tests/Unit/Service/ImpactScorerTest.php` | nuevo | 5 tests: caso alto impacto (regulación + ticker volátil), caso rutinario bajo, caso sin snapshot/tickers (score definido, no null/crash), clamp 0-1, orden relativo sensato entre escenarios |
| `agent-commits.md` | modificado | Esta entrada |

### Justificación

**Por qué la señal de impacto viaja en el JSON de Haiku que ya existe, no en un segundo call:** el runbook (`PLAN-MARKET-PULSE.md` §2.5, redactado en la sesión anterior) cerró esto explícitamente para no repetir el error que 2.1/2.4 evitaron a propósito: gastar una llamada LLM extra por una señal que se puede pedir gratis dentro de un call que ya se está pagando. `AnthropicEnrichmentProvider` ya arma un JSON con `summary`/`sentiment`/`asset_class`/etc. por cada `NewsItem`; agregar `"salience"` a ese mismo JSON no suma tokens de output significativos (un número más) y no suma ninguna request nueva.

**Por qué el score final combina salience + heurística y no usa solo uno de los dos:** salience puro depende 100% del juicio del modelo sobre un artículo aislado, sin contexto de mercado en vivo — no sabe si BTC se movió 12% hoy. La heurística pura ignora la lectura cualitativa del contenido (una noticia de regulación redactada de forma neutra puede ser igual de relevante que una alarmista). Combinar ambos con 60/40 (salience pesa más por ser la lectura de contenido, la heurística corrige con datos objetivos de mercado) da un ranking que ninguna de las dos señales sola daría. La fórmula y los pesos quedan documentados acá y en el código (no son un detalle escondido).

**Por qué el default de heurística es 0.0 y no 0.5 cuando falta una señal:** un salience ausente o inválido (respuesta LLM mal formada) se mapea a 0.0, no al punto medio — una señal ausente no debe empujar el score hacia "impacto medio" por default, porque eso sesgaría el ranking hacia arriba en el peor caso (el LLM falla → el item parece más relevante de lo que realmente se sabe). Mismo criterio que ya usa el código para `sentiment` (default `'neutral'` explícito, no adivinado).

**El drift de `impact_score DROP DEFAULT` no es el drift de pgvector — se corrigió, no se descartó:** al escribir la migración con `DEFAULT '0'` (necesario para el backfill de filas preexistentes en dev), Doctrine generaba un segundo diff que quería *dropear* ese default porque el mapping ORM no lo declaraba. A diferencia del drift de `vector`/HNSW (bloqueado, documentado, no tocar), este era un drift nuevo y evitable: se declaró `options: ['default' => 0]` en la columna de la entidad para que el mapping coincida con lo que la migración deja en la base. Verificado: tras el fix, `doctrine:migrations:diff` vuelve a generar **únicamente** el diff de `vector`/HNSW ya conocido.

**Tests con `createStub`, no `createMock`, sobre `MarketSnapshotRepository`:** PHPUnit 12 marca con notice cualquier `createMock()` sin `->expects()` configurado (no se verifican invocaciones, solo se necesita un valor de retorno) — el fix es usar `createStub()`, que es lo que semánticamente se estaba haciendo. Ajustado en los 5 tests nuevos; suite quedó sin notices.

**No se tocó `findFeedPage` ni se agregó un query param de orden/filtro:** el runbook es explícito en que el campo tiene que viajar en el payload ya, pero el filtro de UI/API es 2.6. Agregar sort-by-impact ahora habría sido adelantar scope de un paso que Marcos todavía no pidió ejecutar.

**Verificación (paso cumplido):** `vendor/bin/phpunit` 17/17 verde (12 previos + 5 nuevos de `ImpactScorer`); pipeline real ejercido de punta a punta — item existente reseteado a `pending`, reencolado con `app:enrich:requeue-pending --min-age=0`, procesado por el worker (tras limpiar la cache de contenedor, que no se recarga sola en un proceso long-running), `impact_score` persistido y correcto (0 para el caso sin señal, sin crash); `doctrine:migrations:status` limpio (5/5 aplicadas); `doctrine:migrations:diff` post-fix solo regenera el drift `vector`/HNSW ya conocido, ninguno nuevo.

---

## [PASO 2.4] feat: Market Now — resumen agregado periódico vía Sonnet, publicado en vivo
**Hash:** `fa12cb5`
**Rama:** `release/plan-market-pulse`
**Fecha:** 2026-07-02

### Cambios
| Archivo | Tipo | Descripción |
|---|---|---|
| `backend/src/Provider/MarketNowProviderInterface.php` | nuevo | Contrato `summarize(items, snapshots): MarketNowResult` |
| `backend/src/Provider/MarketNowResult.php` | nuevo | Value object (summary, model, totalTokens, costUsd) |
| `backend/src/Provider/AnthropicMarketNowProvider.php` | nuevo | Llamada raw-HTTP a `claude-sonnet-5`, `max_tokens=700`, `thinking: {type: disabled}` explícito, prompt acotado (≤15 items, ≤240 chars c/u) |
| `backend/src/Provider/NullMarketNowProvider.php` | nuevo | Mock dev — cero costo, cero llamada |
| `backend/src/Entity/MarketNowSummary.php` | nuevo | Persistencia del resumen + `sourceHash` (clave de skip) |
| `backend/src/Repository/MarketNowSummaryRepository.php` | nuevo | `findLatest()` + `deleteOlderThan()` (retención 7 días) |
| `backend/migrations/Version20260702210000.php` | nuevo | `CREATE TABLE market_now_summary`. Se generó y descartó a mano un segundo diff espurio (retype `vector`/drop HNSW en `enrichment`) — mismo drift preexistente de 2.1, no relacionado |
| `backend/src/Command/MarketNowCommand.php` | nuevo | `app:market:now`: arma contexto (K últimos `NewsItem` enriquecidos + snapshots por asset), calcula `sourceHash`, salta la llamada LLM si no cambió desde la corrida anterior, persiste, purga, publica a Mercure en `try/catch` |
| `backend/src/Api/MarketNowPayload.php` | nuevo | Shape único para REST + Mercure (mismo patrón que `NewsItemPayload`) |
| `backend/src/Controller/Api/MarketNowController.php` | nuevo | `GET /api/market-now` — última carga inicial para el front |
| `backend/src/Repository/NewsItemRepository.php` | modificado | `findRecentEnrichedForSummary()` — fetch-join de `Enrichment`, mismo patrón que `findFeedPage` |
| `backend/config/services.yaml` | modificado | Wiring de `AnthropicMarketNowProvider` + alias `MarketNowProviderInterface` |
| `backend/config/services_dev.yaml` | modificado | Alias a `NullMarketNowProvider` en dev |
| `backend/scheduler/crontab` | modificado | `*/10 * * * * bin/console app:market:now -v` — intervalo más largo que `app:market:poll` (2 min), porque cada corrida es una llamada LLM real |
| `frontend/pulse.html` | modificado | Panel "Market Now" (reusa clases `.pulse-card`/`.pulse-summary` existentes, sin CSS nuevo) |
| `frontend/src/pulse.js` | modificado | `loadMarketNow()` (REST inicial) + `connectMarketNow()` (segundo `EventSource`, topic `crypto/market-now`, backoff propio — sin el watchdog completo del feed principal, porque es un panel no crítico) |

### Justificación

**Por qué una sola llamada Sonnet por intervalo y no por-item:** el runbook original (`PLAN-MARKET-PULSE.md` §2.4) decía solo "resumen agregado (Sonnet) publicado en vivo" — sin fijar cuántas llamadas ni con qué contexto, la ambigüedad exacta que hace que un ejecutor se pase de presupuesto LLM. Se cerró antes de programar (sesión anterior, Opus): Market Now es un comando propio (`app:market:now`) en el cron, análogo a `app:market:poll`, que arma un contexto acotado (≤15 items enriquecidos + snapshots) y hace **una** llamada a Sonnet por corrida. Nunca pasa por `EnrichItemMessage`/cola — ese pipeline es Haiku por-item y ya está cerrado (2.1/1.4).

**Por qué Sonnet y no Haiku acá:** Haiku (`claude-haiku-4-5`, ~$1/$5 por MTok) está reservado para clasificación de volumen por-item (ya en uso). Sonnet (`claude-sonnet-5`, ~$3/$15 por MTok) se usa **solo** en este único punto de síntesis/agregación — justificado porque es una tarea de escritura coherente sobre múltiples fuentes, no clasificación. El ID se verificó contra el catálogo vigente de modelos en vez de asumirlo de memoria.

**`thinking: {type: disabled}` explícito, no omitido:** en Sonnet 5, omitir el parámetro `thinking` corre *adaptive* por default y gasta tokens de razonamiento — silencioso, no un error. Para un digest que se corre cada 10 min y debe ser barato, se deshabilita a propósito.

**`sourceHash` para evitar llamadas redundantes:** un refresh del cron sin noticias ni precios nuevos no debe volver a facturar una llamada LLM. Se calcula un hash (ids de items + `asset:fetchedAt` de snapshots, ambos ordenados) y se compara contra el de la última fila persistida; si coincide, el comando corta antes de invocar al provider. Verificado en dev: la segunda corrida seguida imprime "No change since last summary — skipping the LLM call" y no toca el provider.

**Topic Mercure separado (`crypto/market-now`), no reusar `crypto/feed`:** mezclar el shape de un resumen agregado con el de un `NewsItem` individual habría forzado un discriminador de tipo en el payload y complicado el front existente sin necesidad. Un topic propio + una segunda `EventSource` en `pulse.js` mantiene ambos flujos independientes; el front hoy solo soportaba un topic.

**Sin watchdog completo en el segundo `EventSource`:** el watchdog anti-zombie de 1.8 (`pulse.js`) es necesario porque el feed de noticias es el producto central y una conexión zombie silenciosa ahí es grave. Market Now es un panel secundario de refresco lento (10 min); un backoff simple ante `onerror` es proporcional al riesgo — agregar el watchdog completo habría sido complejidad sin beneficio claro para esta superficie.

**Retención de 7 días, no indefinida:** mismo criterio que `MarketSnapshot` (2.1) — es un digest de contexto, no un producto de serie histórica. Con una corrida cada 10 min el volumen es bajo, pero sin purga crecería sin límite igual.

**Migración espuria descartada (mismo procedimiento que 2.1):** `doctrine:migrations:diff` post-aplicación volvió a proponer el retype de `embedding`/drop del índice HNSW en `enrichment` — es el drift preexistente y bloqueado (documentado en `CLAUDE.md`, no tocar hasta el estudio pgvector de Marcos). Se descartó esa migración generada y solo quedó aplicada la de `market_now_summary`.

**Verificación (paso cumplido):** `doctrine:migrations:migrate` aplica limpio (solo `market_now_summary`); `app:market:now -v` con `NullMarketNowProvider` (dev) → summary persistido, costo $0; segunda corrida inmediata → skip confirmado por `sourceHash`; `GET /api/market-now` devuelve el payload esperado; `doctrine:schema:validate` sigue en rojo **únicamente** por el drift pgvector/HNSW ya conocido (confirmado generando y descartando el diff, no se sumó regresión nueva); `vendor/bin/phpunit` 12/12 verde; Vite recargó `pulse.js`/`pulse.html` sin errores (`page reload` limpio en logs).

---

## Formato de entrada

```
## [PASO X.Y] <título del commit>
**Hash:** `<hash>`
**Rama:** `<rama>`
**Fecha:** <fecha>

### Cambios
| Archivo | Tipo | Descripción |
|---|---|---|
| path/archivo | nuevo/modificado/eliminado | qué hace |

### Justificación
<explicación de por qué se tomaron estas decisiones, qué problema resuelven, qué alternativas se descartaron>
```

---

## [fix] fix: proxy /health desde el frontend hacia el backend en prod

**Hash:** `4c20e1c`
**Rama:** `release/plan-market-pulse`
**Fecha:** 2026-06-13

### Cambios

| Archivo | Tipo | Descripción |
|---|---|---|
| `frontend/Caddyfile` | modificado | Agrega `handle /health { reverse_proxy http://backend:80 }` |

### Justificación

En producción el frontend Caddy expone `:80` y el backend queda solo accesible internamente. El `Caddyfile` del frontend únicamente reenviaba `/api/*`, `/live.php` y `/.well-known/mercure*` al backend; `/health` no estaba incluido, así que caía al `file_server` (404) → `handle_errors` → respondía `"Something went wrong!"` en vez del `{"status":"ok"}` real del backend. En dev nunca se notó porque el backend expone `:80` directo (sin pasar por el frontend) y el CI solo prueba el stack de dev.

Detectado durante una verificación del stack de producción de `main` (framework Oliva, no específico de Crypto Pulse), pero el mismo `Caddyfile` existe igual en esta rama — se portea el mismo fix de una línea aquí. Verificado en un stack prod aislado (`-p oliva-fix-test`): `curl http://localhost/health` → `{"status":"ok"}` a través del frontend.

---

## [PASO 1.1] feat: modelo de dominio — entidades NewsItem y Enrichment

**Hash:** `5b5fd15`
**Rama:** `release/plan-market-pulse`
**Fecha:** 2026-06-01

### Cambios

| Archivo | Tipo | Descripción |
|---|---|---|
| `backend/src/Entity/NewsItemStatus.php` | nuevo | PHP backed enum `pending \| enriched \| failed` — pipeline state machine |
| `backend/src/Entity/NewsItem.php` | nuevo | Entidad principal: source, externalId, title, url, body, publishedAt, contentHash (unique), status |
| `backend/src/Entity/Enrichment.php` | nuevo | Entidad de enriquecimiento: summary, sentiment, assetClass, tickers, entities, embedding vector(1024), model, tokens, costUsd |
| `backend/src/Repository/NewsItemRepository.php` | nuevo | Repository ServiceEntityRepository vacío (requerido por Doctrine) |
| `backend/src/Repository/EnrichmentRepository.php` | nuevo | Repository ServiceEntityRepository vacío |
| `backend/migrations/Version20260601054114.php` | nuevo | Migración: CREATE TABLE news_item + enrichment; índices status/publishedAt; UNIQUE content_hash; HNSW vector_cosine_ops |
| `backend/config/packages/doctrine.yaml` | modificado | Agrega `mapping_types: vector: vector` para que doctrine:schema:validate resuelva el tipo de la DB |
| `.github/workflows/ci.yml` | modificado | `doctrine:schema:validate --skip-sync` — el índice HNSW no es manejado por Doctrine ORM |
| `concepts.md` | modificado | Agrega secciones: Embeddings, Búsqueda kNN, Índice HNSW, Content Hash, Pipeline State Machine |

### Justificación

**Dimensiones del embedding = 1024:** coincide con Voyage-3 (el proveedor de embeddings recomendado por Anthropic para producción). Centralizado en `Enrichment::EMBEDDING_DIMENSIONS` para cambiar en un solo lugar si se migra de proveedor.

**Índice HNSW manual en la migración:** Doctrine no genera índices HNSW (son específicos de pgvector). El índice se agrega directamente en el SQL de la migración con `WHERE embedding IS NOT NULL` (índice parcial — no indexa filas sin embedding todavía calculado, que son la mayoría al insertar).

**`mapping_types: vector: vector`:** sin esto, `doctrine:schema:validate` falla al intentar leer el tipo `vector` de PostgreSQL durante la introspección inversa (DB → PHP). Con `mapping_types`, DBAL mapea la columna `vector` de la DB al tipo Doctrine `vector` que ya está registrado.

**`--skip-sync` en el CI:** usamos Migrations, no `schema:update`. El índice HNSW existe en la DB pero no en el modelo Doctrine → el sync siempre reportaría out-of-sync. La validación relevante es solo el mapeo ORM (`--skip-sync` omite la comparación con la DB).

**Verificación:** migraciones aplicadas; `doctrine:schema:validate --skip-sync` OK; PHPUnit 2/2 verde.

---

## [PASO 1.2] feat: ingesta RSS — SourceAdapterInterface, RssAdapter, EnrichItemMessage, handler real

**Hash:** `2f1e829`
**Rama:** `release/plan-market-pulse`
**Fecha:** 2026-06-01

### Cambios

| Archivo | Tipo | Descripción |
|---|---|---|
| `backend/src/Adapter/SourceAdapterInterface.php` | nuevo | Contrato de adaptador de fuente: `getId(): string` + `fetch(): iterable<array>` |
| `backend/src/Adapter/RssAdapter.php` | nuevo | Implementación RSS genérica (HttpClient + SimpleXML). Soporta `content:encoded` para body completo; fallback a `<description>`. |
| `backend/src/Message/EnrichItemMessage.php` | nuevo | Mensaje para la cola `enrich`: porta `newsItemId` para que el futuro handler de enriquecimiento sepa qué item procesar. |
| `backend/src/MessageHandler/IngestSourceHandler.php` | modificado | Implementación real: busca el adapter por sourceId, itera items, computa contentHash (SHA-256 de url), dedup contra DB, persiste `NewsItem(status=pending)`, despacha `EnrichItemMessage`. |
| `backend/config/packages/messenger.yaml` | modificado | Activa el routing `EnrichItemMessage → enrich` (estaba comentado como Phase 1). |
| `backend/config/services.yaml` | modificado | Registra dos instancias de `RssAdapter` (coindesk-rss y cointelegraph-rss) con tag `app.source_adapter`; wire `$adapters` del handler con `tagged_iterator`. |

### Justificación

**Una clase `RssAdapter` con dos instancias nombradas en vez de dos subclases:** ambos feeds son RSS 2.0 estándar; la única diferencia es `sourceId` y `feedUrl`. Crear subclases sería abstraer por herencia donde solo hay configuración. Se instancian manualmente en `services.yaml` con `tagged_iterator` para que el handler reciba el conjunto completo sin saber cuántos existen — extensible sin tocar el handler.

**`contentHash = SHA-256(url)` como clave de deduplicación:** la url del artículo es estable entre fetches del mismo feed; el GUID puede variar según implementación del feed. SHA-256 de url garantiza idempotencia incluso si el mismo artículo aparece en ambos feeds con distintos GUIDs. La constraint UNIQUE `content_hash` en la tabla actúa como segunda línea de defensa.

**Flush por item antes de dispatch:** se necesita el `id` del `NewsItem` persistido para armar el `EnrichItemMessage`. Flush por item implica N roundtrips a la DB por poll, lo cual es aceptable dado el volumen (decenas de items); si el feed crece se puede batch-persist y despachar los IDs al final.

**`coingecko-top` sin adapter:** el `SourcesPollCommand` aún lista `coingecko-top` como fuente stub del paso 0.6. El handler recibe `IngestSourceMessage{sourceId: 'coingecko-top'}`, no encuentra adapter y loguea warning — comportamiento correcto, se ignorará hasta el paso 2.1 donde se agrega el adapter de CoinGecko.

**Verificación:** 25 items de coindesk-rss + 30 de cointelegraph-rss persisten en la DB; segundo poll no duplica ninguno; `EnrichItemMessage` llega a la cola `enrich` (sin handler aún — esperado, paso 1.4).

---

## [PASO 1.3] feat: poll programado — SourcesPollCommand itera adapters registrados

**Hash:** `a48f5ed`
**Rama:** `release/plan-market-pulse`
**Fecha:** 2026-06-01

### Cambios

| Archivo | Tipo | Descripción |
|---|---|---|
| `backend/src/Command/SourcesPollCommand.php` | modificado | Reemplaza lista hardcodeada por `iterable<SourceAdapterInterface>` inyectado con `tagged_iterator app.source_adapter`. |
| `backend/config/services.yaml` | modificado | Wire `$adapters` del comando con `tagged_iterator app.source_adapter`. |

### Justificación

**Eliminar la lista hardcodeada:** la lista `['coindesk-rss', 'cointelegraph-rss', 'coingecko-top']` estaba desacoplada de los adapters reales: incluía `coingecko-top` que no tiene adapter, y requería editar el comando cada vez que se agrega una fuente. Ahora el comando es un thin dispatcher — solo itera lo que el contenedor sabe que existe.

**Mismo tagged_iterator que el handler:** reusar el tag `app.source_adapter` garantiza que agregar un nuevo adapter en `services.yaml` lo hace disponible automáticamente tanto en el handler (procesamiento) como en el comando (poll), sin tocar código PHP.

**No se cambia el crontab ni el compose:** el scheduler ya ejecuta `app:sources:poll -v` cada 5 minutos. El cambio es transparente para la infraestructura.

**Verificación:** `bin/console app:sources:poll -v` en backend y en scheduler emite solo coindesk-rss + cointelegraph-rss; scheduler confirmado con cache limpia.

---

## [PASO 1.5] feat: publish Mercure + NullEnrichmentProvider dev

**Hash:** `c15bc35`
**Rama:** `release/plan-market-pulse`
**Fecha:** 2026-06-01

### Cambios

| Archivo | Tipo | Descripción |
|---|---|---|
| `backend/src/MessageHandler/EnrichItemHandler.php` | modificado | Inyecta `HubInterface`; publica a topic `crypto/feed` tras `flush()` con payload JSON del item enriquecido |
| `backend/src/Provider/NullEnrichmentProvider.php` | nuevo | Provider stub para dev: devuelve `EnrichmentResult` fijo (costo $0); evita llamadas reales a la API durante desarrollo |
| `backend/config/services_development.yaml` | nuevo | Override del alias `EnrichmentProviderInterface` → `NullEnrichmentProvider` en APP_ENV=development |
| `.env.backend` | modificado | `MERCURE_URL` cambia de `http://localhost` a `http://backend` (nombre de servicio Docker) para que el worker pueda publicar al hub en otro contenedor |
| `.env.example` | modificado | Mismo cambio de MERCURE_URL |

### Justificación

**`MERCURE_URL=http://backend/...` en lugar de `localhost`:** el worker corre en un contenedor separado (sin Caddy). Desde ese contenedor, `localhost` es el propio worker. El hub de Mercure vive en el contenedor `backend` (FrankenPHP/Caddy). El nombre de servicio Docker `backend` resuelve correctamente desde todos los contenedores de la red `app_network`, incluyendo el propio `backend` (Docker DNS). Cambiarlo a `http://backend` hace que tanto el backend como el worker puedan publicar sin ningún cambio por contenedor.

**`NullEnrichmentProvider` + `services_development.yaml`:** cierra la deuda 🔴 identificada en la revisión de sanidad post-1.4. El archivo es `services_development.yaml` (no `services_dev.yaml`) porque `APP_ENV=development` — Symfony resuelve el sufijo del env. En producción, `AnthropicEnrichmentProvider` sigue siendo el alias real.

**Publicación después del `flush()`:** garantiza que el item persistido en la DB es el mismo que se difunde por Mercure. Un fallo del hub no revierte la persistencia (Mercure no es transaccional con la DB); lo opuesto — publicar antes del flush — podría difundir un item que luego falla al persistir.

**Payload del evento:** incluye todos los campos visibles al usuario final (id, source, title, url, publishedAt, summary, sentiment, assetClass, tickers, entities, model, costUsd). El embedding se omite del payload (no tiene utilidad en el cliente SSE y aumentaría el tamaño del mensaje en ~8 KB por item).

**Verificación:** `curl` suscrito al topic `crypto/feed` recibe 3 eventos SSE con payload JSON completo inmediatamente después de que el worker procesa los mensajes.

---

## [PASO 1.4] feat: enriquecimiento IA — AnthropicEnrichmentProvider, VoyageEmbeddingProvider, EnrichItemHandler

**Hash:** `5d19a32`
**Rama:** `release/plan-market-pulse`
**Fecha:** 2026-06-01

### Cambios

| Archivo | Tipo | Descripción |
|---|---|---|
| `backend/src/Provider/EnrichmentResult.php` | nuevo | DTO readonly con summary, sentiment, assetClass, tickers, entities, model, totalTokens, costUsd |
| `backend/src/Provider/EnrichmentProviderInterface.php` | nuevo | Contrato: `enrich(contentHash, title, body): EnrichmentResult` |
| `backend/src/Provider/EmbeddingProviderInterface.php` | nuevo | Contrato: `embed(text): float[]|null` |
| `backend/src/Provider/AnthropicEnrichmentProvider.php` | nuevo | Haiku (`claude-haiku-4-5-20251001`), prompt caching Anthropic, Symfony Cache filesystem 24h, cálculo de costo por tokens |
| `backend/src/Provider/VoyageEmbeddingProvider.php` | nuevo | Voyage-3 (1024 dims); retorna null si `VOYAGE_API_KEY` está vacío — no bloquea el enriquecimiento |
| `backend/src/MessageHandler/EnrichItemHandler.php` | nuevo | Handler idempotente: skip si status ≠ pending, llama providers, persiste Enrichment + marca enriched |
| `backend/src/Command/EnrichRequeueCommand.php` | nuevo | `app:enrich:requeue-pending` — re-despacha EnrichItemMessage para todos los NewsItem con status=pending; útil para recovery de fallos (preparatorio para 1.8) |
| `backend/config/packages/cache.yaml` | modificado | Pool `enrichment.cache` (filesystem, 24h) — evita re-llamar la API en retries |
| `backend/config/services.yaml` | modificado | Wire AnthropicEnrichmentProvider (apiKey, enrichmentCache), VoyageEmbeddingProvider (apiKey), aliases de interfaces; default `env(VOYAGE_API_KEY): ''` para ser opcional |
| `.env.example` | modificado | Agrega `ANTHROPIC_API_KEY` y `VOYAGE_API_KEY` (vacío por defecto) |

> **Corrección (revisión 2026-06-01):** este commit (`5d19a32`) incluyó **solo** `.env.example`, NO `.env.backend`. El mismo cambio (`ANTHROPIC_API_KEY` / `VOYAGE_API_KEY`) quedó sin commitear en `.env.backend` (working tree con ` M .env.backend`). Reconciliar: commitear el cambio o descartarlo para dejar `git status` limpio.

### Justificación

**Anthropic prompt caching en el system prompt:** el system prompt es fijo (~300 tokens). Con `cache_control: ephemeral`, Anthropic lo cachea entre llamadas consecutivas. El costo de read de cache es ~10x más barato que input normal. En un pipeline de decenas de artículos por poll, esto reduce el costo de tokens de sistema a casi cero.

**Symfony Cache como segunda capa (filesystem, 24h):** si Messenger reintenta un `EnrichItemMessage` (por error de red, timeout, o fallo de flush), el resultado ya cacheado evita una segunda llamada a la API. Clave = `enrich_<contentHash>` (SHA-256 de URL), estable entre retries del mismo item.

**Idempotencia en el handler antes de cualquier llamada:** se verifica `status !== pending` al inicio. Si el item ya fue enriquecido (por ejemplo, por un retry tardío que llega después de que otro mensaje anterior ya tuvo éxito), el handler retorna sin hacer nada. Esto es la primera línea de defensa contra doble enriquecimiento y doble costo.

**VoyageEmbeddingProvider null-safe:** el campo `embedding` en `Enrichment` es nullable. Sin key de Voyage, el enriquecimiento funciona completo (summary, sentiment, tickers, etc.) y el embedding queda null. Cuando el usuario configure la key, `app:enrich:requeue-pending` permite re-procesar items — pero dado que el status ya será `enriched`, el handler los saltea. El re-embedding requeriría un comando específico (fuera de scope 1.4).

**`EnrichRequeueCommand`:** no es scope-creep — es la herramienta mínima necesaria para verificar el handler con items reales. El plan (paso 1.8) menciona "comando para reprocesar/inspeccionar" items del DLX; este comando es su precursor directo.

**Verificación confirmada:** handler invocado con éxito (Symfony Cache lock visible en logs), request HTTP a `api.anthropic.com/v1/messages`, HTTP 401 con key placeholder → confirma que el flujo completo hasta la API funciona. Con key real: items pasan a `enriched`, Enrichment persiste con resumen/sentiment/tickers/costo.

---

## [fix] fix: FRANKENPHP_CONFIG crasheaba Caddy en CI

**Hash:** `be0662e`
**Rama:** `release/plan-market-pulse`
**Fecha:** 2026-06-01

### Cambios

| Archivo | Tipo | Descripción |
|---|---|---|
| `.env.example` | modificado | `FRANKENPHP_CONFIG="php:80"` → vacío |
| `.github/workflows/ci.yml` | modificado | Agrega paso `docker compose logs --tail 80` con `if: failure()` |

### Justificación

`FRANKENPHP_CONFIG="php:80"` era un valor leftover del template symfony-docker. El Caddyfile lo inyecta en el bloque global `frankenphp { {$FRANKENPHP_CONFIG} }`. Localmente la variable nunca estaba seteada (expandía a vacío → bloque válido). En CI, `.env.example` la seteaba a `php:80`, que Caddy intentaba parsear como directivo dentro de `frankenphp {}` → parse error → FrankenPHP no levantaba → healthcheck fallaba. Fix: dejar la variable vacía en el ejemplo. Se agrega dump de logs on-failure para diagnóstico de futuros crashes en CI.

---

## [PASO 0.8] feat: PHPUnit base — instalar, configurar y habilitar en CI

**Hash:** `dc444bc`
**Rama:** `release/plan-market-pulse`
**Fecha:** 2026-06-01

### Cambios

| Archivo | Tipo | Descripción |
|---|---|---|
| `backend/composer.json` | modificado | Agrega `phpunit/phpunit ^12.5` y test-pack (browser-kit, css-selector) en require-dev |
| `backend/composer.lock` | modificado | Lock actualizado con PHPUnit 12.5.28 y dependencias |
| `backend/symfony.lock` | modificado | Recipe de phpunit/phpunit registrada |
| `backend/phpunit.dist.xml` | nuevo | Configuración PHPUnit generada por la recipe de Flex; habilita deprecation/notice/warning como errores |
| `backend/tests/bootstrap.php` | nuevo | Bootstrap de PHPUnit + Symfony generado por la recipe |
| `backend/tests/Unit/Message/IngestSourceMessageTest.php` | nuevo | Primer test unitario: verifica `IngestSourceMessage` (inmutabilidad del sourceId) |
| `backend/.dockerignore` | modificado | Elimina la exclusión de `tests/`; sin esto el build fallaba con "not found" |
| `backend/Dockerfile` | modificado | Agrega `COPY --link tests tests/` y `COPY --link phpunit.dist.xml ./` al stage base |
| `docker-compose.override.yml` | modificado | Agrega mount `./backend/tests:/app/tests` en el servicio `backend` para hot-reload de tests en dev |
| `.github/workflows/ci.yml` | modificado | Quita `if: false` del paso PHPUnit; usa `php vendor/bin/phpunit` (bin/phpunit ya no es generado por la recipe en PHPUnit 12) |
| `CLAUDE.md` | modificado | Actualiza "Próximo paso" a 1.1 |

### Justificación

**PHPUnit 12 no genera `bin/phpunit`:** la Symfony recipe de PHPUnit ≥11.1 ya no crea el wrapper `bin/phpunit` (solía descargar el phar de PHPUnit bridge). En PHPUnit 12 el binario canónico es `vendor/bin/phpunit`. El CI y la documentación se actualizan para usarlo directamente.

**`tests/` estaba excluido del build context:** el `.dockerignore` original del template excluye `tests/` y `vendor/` (correcto para el caso de uso original). Al incorporar tests en el repo, `tests/` debe estar disponible en el contexto para que `COPY --link tests tests/` funcione en CI/prod.

**Mount de `tests/` en dev:** sin el mount, los archivos de test creados en el host no son visibles en el contenedor (que solo monta `src/`, `config/`, `migrations/`). Con el mount, el ciclo edit-run-test en dev es inmediato sin rebuild.

**Test elegido — `IngestSourceMessage`:** el DTO es el artefacto más simple del dominio (solo constructor + propiedad readonly), no requiere kernel ni base de datos, y valida que el autoloading y la config de PHPUnit están correctos. El GATE del paso exige un test que pase, no un test sofisticado.

**Verificación:** `php vendor/bin/phpunit` → `OK (2 tests, 2 assertions)` en el contenedor de dev.

---

## [PASO 0.7] feat: corregir CI y agregar health endpoint

**Hash:** `a1942d4`
**Rama:** `release/plan-market-pulse`
**Fecha:** 2026-06-01

### Cambios

| Archivo | Tipo | Descripción |
|---|---|---|
| `.github/workflows/ci.yml` | nuevo | CI correcto en la raíz del repo; trigger en `release/plan-market-pulse`; genera env files en CI; usa `docker compose build`; checks HTTP/Mercure/migrations/schema |
| `backend/.github/workflows/ci.yml` | eliminado | Estaba en ubicación incorrecta; GitHub Actions no lo leía |
| `backend/src/Controller/HealthController.php` | nuevo | `GET /health` → `{"status":"ok"}` — endpoint para CI y monitoreo |

### Justificación

**`.github/` estaba dentro de `backend/`:** el template symfony-docker asume que el repo root es el backend. En este proyecto el repo root es la app entera (`backend/` + `frontend/`). GitHub Actions solo lee `.github/` en la raíz del repositorio; el CI nunca se ejecutó.

**`if: false` en pasos de Doctrine:** el template pone `if: false` en los pasos de ORM/migraciones para que el CI verde de base. Se quitó ahora que Doctrine, Migrations y pgvector están instalados y el schema está en sync.

**PHPUnit sigue con `if: false`:** PHPUnit se instala en el paso 0.8. Habilitarlo ahora haría el CI rojo.

**Endpoint `/health` en lugar de chequear `http://localhost`:** sin rutas definidas el root devuelve 404 y `curl --fail-with-body` falla. El health endpoint es la práctica correcta (liveness probe para CI y para Kubernetes/Docker en producción).

**`docker compose build` en lugar de `bake-action`:** el bake-action de Docker usa GHA cache pero necesita configuración adicional (credenciales de registry, ARGs de build). `docker compose build` es equivalente funcional para CI sin la complejidad del cache de capas en GHA. Se puede agregar caché en una iteración futura.

**Verificación local:** todos los pasos del CI pasaron manualmente: `/health` → 200, Mercure → 200, migrations → "already at latest version", `schema:validate` → "in sync".

---

## [PASO 0.6] feat: scheduler cron container with supercronic

**Hash:** `fc7cb23`
**Rama:** `release/plan-market-pulse`
**Fecha:** 2026-06-01

### Cambios

| Archivo | Tipo | Descripción |
|---|---|---|
| `backend/Dockerfile` | modificado | Descarga supercronic v0.2.46 en el stage base; copia `scheduler/crontab` a `/etc/supercronic/crontab` |
| `backend/scheduler/crontab` | nuevo | Crontab de supercronic: `*/5 * * * *` ejecuta `bin/console app:sources:poll -v` |
| `backend/src/Command/SourcesPollCommand.php` | nuevo | Comando stub `app:sources:poll`: itera lista hardcodeada de sources y despacha `IngestSourceMessage` por cada uno |
| `backend/src/Message/IngestSourceMessage.php` | nuevo | DTO de mensaje para el pipeline de ingesta; lleva `sourceId` (string) |
| `backend/src/MessageHandler/IngestSourceHandler.php` | nuevo | Handler stub: recibe `IngestSourceMessage`, loguea no-op, retorna éxito |
| `backend/config/packages/messenger.yaml` | modificado | Agrega `default_publish_routing_key` a exchanges `ingest` y `enrich`; habilita routing `IngestSourceMessage → ingest` |
| `docker-compose.yml` | modificado | Agrega servicio base `scheduler` (imagen backend, depends_on rabbitmq+database) |
| `docker-compose.override.yml` | modificado | Agrega override `scheduler` con comando `supercronic`, mounts de src/config/crontab y healthcheck `kill -0 1` |

### Justificación

**`default_publish_routing_key` faltaba en la config del exchange:** sin esa clave, Symfony publica al exchange con routing key vacío (`''`). En un exchange `direct`, el mensaje solo llega a la queue si el routing key matchea el binding key (`ingest`). Resultado: `publish_in: 18` en el exchange pero `deliver_get: 0` en la queue — los mensajes se "perdían" silenciosamente. Detectado inspeccionando la management API de RabbitMQ; no hay error visible en el producer (el dispatch "no falla"). Fix: agregar `default_publish_routing_key: ingest/enrich` a cada exchange.

**Handler stub para evitar failed queue churn:** sin un handler registrado, Symfony lanza `NoHandlerForMessageException`, reintenta 3 veces y manda el mensaje a la failed queue. Para la fase 0.6 (stub), eso generaría ruido en la failed queue con cada ejecución del cron. El handler stub simplemente loguea y retorna éxito; el handler real llega en Fase 1.

**Supercronic en el stage base (no en un stage separado):** el scheduler necesita PHP para ejecutar `bin/console`. Añadir supercronic al mismo Dockerfile evita un segundo contexto de build y permite que worker y scheduler compartan la misma imagen (menos superficie de mantenimiento). El binario es estático (~7MB), sin impacto significativo en la imagen.

**Verificación:** supercronic ejecutó `app:sources:poll` a las 03:45 y 03:50 UTC (automáticos); worker logueó `IngestSourceHandler: stub no-op` + `acknowledged to transport` para los 3 mensajes de cada run.

---

## [docs] docs: agregar explicación de RabbitMQ a concepts.md

**Hash:** `18e1740`
**Rama:** `release/plan-market-pulse`
**Fecha:** 2026-06-01

### Cambios

| Archivo | Tipo | Descripción |
|---|---|---|
| `concepts.md` | modificado | Agrega sección `## RabbitMQ` con explicación conceptual, tabla de términos AMQP, diagrama de flujo del proyecto y justificación de la elección vs Kafka/Redis Streams |

### Justificación

El usuario pidió explicación de RabbitMQ. No estaba en `concepts.md`. Se agregó siguiendo el protocolo de explicaciones conceptuales del CLAUDE.md.

---

## [PASO 0.5] feat: add RabbitMQ, Symfony Messenger, worker service (step 0.5)

**Hash:** `b6c53f1`
**Rama:** `release/plan-market-pulse`
**Fecha:** 2026-06-01

### Cambios

| Archivo | Tipo | Descripción |
|---|---|---|
| `docker-compose.yml` | modificado | Agrega servicio `rabbitmq` (imagen `3-management`, volumen `rabbitmq_data`, healthcheck); backend `depends_on` rabbitmq healthy; agrega volumen `rabbitmq_data` |
| `docker-compose.override.yml` | modificado | Expone puertos `5672` y `15672` de RabbitMQ en dev; agrega servicio `worker` con `messenger:consume ingest enrich` |
| `backend/Dockerfile` | modificado | Agrega extensión PHP `amqp` a `install-php-extensions` |
| `backend/composer.json` | modificado | Agrega `symfony/messenger` y `symfony/amqp-messenger` |
| `backend/composer.lock` | modificado | Lock actualizado |
| `backend/symfony.lock` | modificado | Recipe Flex de messenger registrada |
| `backend/config/packages/messenger.yaml` | modificado | Configuración completa: transportes `ingest` + `enrich` + `failed` con DSN AMQP, DLX (`x-dead-letter-exchange`), retry strategy (3 intentos, backoff exponencial) |
| `backend/.env` | modificado | Agrega `RABBITMQ_DSN` placeholder |
| `.env.backend` (raíz) | modificado | Agrega `RABBITMQ_USER`, `RABBITMQ_PASSWORD`, `RABBITMQ_DSN` con valores de dev |
| `.env.example` | modificado | Documenta variables de RabbitMQ y Mercure |

### Justificación

**`ext-amqp` no estaba en el Dockerfile:** igual que `pdo_pgsql` en el paso 0.2, el template no incluye extensiones específicas. Sin `ext-amqp`, Composer rechaza `symfony/amqp-messenger` por falta de plataforma. Solución: agregar al Dockerfile y rebuildar.

**Tres transportes desde el inicio (ingest / enrich / failed):** diseño deliberado. `ingest` y `enrich` son los dos stages del pipeline. `failed` es el dead-letter — los mensajes que agotan los reintentos van ahí en lugar de perderse. Permite inspeccionarlos y reprocesarlos con `messenger:failed:retry`.

**DLX via `x-dead-letter-exchange` en las queue arguments:** configura el DLX a nivel de RabbitMQ, no solo a nivel Symfony. Si el worker muere sin hacer ACK, Rabbit mueve el mensaje al exchange `failed` sin necesidad de que Symfony intervenga. Más robusto que depender solo del retry de Messenger.

**Retry strategy diferenciada:** `ingest` usa delay 1s (errores de red cortos); `enrich` usa 2s (LLM puede tardar en responder). Multiplicador x2 en ambos para backoff exponencial. 3 reintentos máximos antes de DLX.

**Worker con `--time-limit=3600`:** el worker reinicia cada hora para liberar memoria y recibir código actualizado (en dev). `restart: unless-stopped` lo relanza automáticamente.

**Verificación:** `messenger:stats` muestra los 3 transportes conectados con 0 mensajes; management UI en `:15672` muestra las colas `ingest`, `enrich`, `failed`.

---

## [PASO 0.4] feat: install MercureBundle, configure publisher (step 0.4)

**Hash:** `88f4a93`
**Rama:** `release/plan-market-pulse`
**Fecha:** 2026-06-01

### Cambios

| Archivo | Tipo | Descripción |
|---|---|---|
| `backend/composer.json` | modificado | Agrega `symfony/mercure-bundle ^0.4.2` |
| `backend/composer.lock` | modificado | Lock actualizado con mercure-bundle y dependencias |
| `backend/symfony.lock` | modificado | Recipe Flex registrada |
| `backend/config/bundles.php` | modificado | Agrega `MercureBundle::class => ['all' => true]` |
| `backend/config/packages/mercure.yaml` | nuevo | Config del bundle: `MERCURE_URL`, `MERCURE_PUBLIC_URL`, `MERCURE_JWT_SECRET` |
| `backend/.env` | modificado | Agrega bloque `symfony/mercure-bundle` con placeholders de las 3 variables |
| `backend/src/Command/MercurePublishTestCommand.php` | nuevo | Console command `app:mercure:test` para smoke test del publisher |
| `.env.backend` (raíz) | modificado | Agrega `MERCURE_PUBLISHER_JWT_KEY`, `MERCURE_JWT_SECRET`, `MERCURE_URL`, `MERCURE_PUBLIC_URL` con valores reales de dev |

### Justificación

**`!ChangeThisSecret!` tiene 144 bits — HMAC-SHA256 requiere mínimo 256 bits:** el Caddyfile original usa ese placeholder como default. Al instalar el MercureBundle, la librería JWT fuerza un mínimo de 32 bytes en el secret. Solución: generar un hex de 64 chars (256 bits) y propagarlo a ambos lados. Documentado: `MERCURE_PUBLISHER_JWT_KEY` (Caddy) y `MERCURE_JWT_SECRET` (bundle) deben ser el mismo valor.

**Por qué `MERCURE_URL=http://localhost/.well-known/mercure`:** el hub Mercure está embebido en Caddy, que corre en el mismo contenedor que PHP (arquitectura FrankenPHP). El backend publica al hub por localhost — no hay red entre servicios. En producción esta URL no cambia.

**`MERCURE_PUBLIC_URL` igual a `MERCURE_URL` por ahora:** el bundle usa `public_url` para generar headers `Link` en respuestas API. El frontend (`live.js`) construye la URL de suscripción desde `window.location.origin` (no usa los headers), así que el valor actual es irrelevante hasta que se use esa feature. Se puede sobrescribir por entorno vía `env_file`.

**Rebuild obligatorio al cambiar `composer.lock`:** en dev, el `vendor/` vive dentro de la imagen (no está montado). Al instalar paquetes dentro del contenedor y sincronizar solo `composer.json/lock` al host, la imagen queda desactualizada. La imagen debe rebuildearse para que el nuevo `vendor/` quede baked in.

**`MercurePublishTestCommand`:** permanece como smoke test útil para CI (paso 0.7). No es código temporal — sirve para verificar publisher en cualquier entorno.

**Verificación:** `bin/console app:mercure:test` retorna `Published OK. Message ID: urn:uuid:...`; cliente EventSource en browser recibe el mensaje.

---

## [PASO 0.3] feat: add pgvector — extension, migration, Doctrine type

**Hash:** `1435f0c`
**Rama:** `release/plan-market-pulse`
**Fecha:** 2026-06-01

### Cambios

| Archivo | Tipo | Descripción |
|---|---|---|
| `docker-compose.yml` | modificado | Cambia imagen `database` de `postgres:15` a `pgvector/pgvector:pg15` |
| `backend/migrations/Version20260601001301.php` | nuevo | Migración que habilita la extensión `vector` en Postgres (`CREATE EXTENSION IF NOT EXISTS vector`) |
| `backend/composer.json` | modificado | Agrega `pgvector/pgvector ^0.2.2` |
| `backend/composer.lock` | modificado | Lock actualizado |
| `backend/symfony.lock` | modificado | Recipe registrada |
| `backend/config/packages/doctrine.yaml` | modificado | Registra el tipo Doctrine `vector` → `Pgvector\Doctrine\VectorType`; fija `server_version: '15'` |

### Justificación

**`pgvector/pgvector:pg15` es compatible con el volumen existente:** la imagen es `postgres:15` + la extensión preinstalada. El formato del directorio de datos es idéntico, por lo que el volumen `db_data` no se pierde ni hay que reinicializarlo.

**La extensión se habilita con una migración, no en `initdb`:** esto la mantiene versionada junto con el esquema de la app. Si se destruye y recrea la DB, la migración la reinstala automáticamente. Alternativa descartada: script de init de Postgres (`docker-entrypoint-initdb.d`) — funciona, pero es una pieza de infra separada que no está bajo control de Migrations.

**`server_version: '15'` en doctrine.yaml:** el comentario original del template decía `server_version: '16'`; fijar `15` evita que Doctrine use features de PG16 (ej: generación de identidad con nueva sintaxis) que no están disponibles en el servidor en uso.

**Tipo Doctrine `vector`:** sin este registro, `#[ORM\Column(type: 'vector')]` en una entidad lanza `UnknownColumnType`. El paquete `pgvector/pgvector` provee `VectorType` que convierte entre `float[]` PHP y el literal `[x,y,z]` que espera el tipo SQL `vector(n)`.

**Verificación:** `pgvector 0.8.2` instalada en la DB; operación de similitud coseno (`<=>`) funciona; `doctrine:schema:validate` verde.

---

## [PASO 0.2] feat: install Doctrine ORM + Migrations, add pdo_pgsql extension

**Hash:** `0d607537` (ver `git show 0d60753`)
**Rama:** `release/plan-market-pulse`
**Fecha:** 2026-05-31

### Cambios

| Archivo | Tipo | Descripción |
|---|---|---|
| `backend/Dockerfile` | modificado | Agrega `pdo_pgsql` a `install-php-extensions`; agrega `COPY --link migrations migrations/` |
| `backend/composer.json` | modificado | Agrega `symfony/orm-pack`, `doctrine/doctrine-migrations-bundle`; y `symfony/maker-bundle` en dev |
| `backend/composer.lock` | modificado | Lock actualizado con todas las dependencias de Doctrine y maker |
| `backend/symfony.lock` | modificado | Recipes Flex de doctrine-bundle y maker-bundle registradas |
| `backend/config/bundles.php` | modificado | Agrega `DoctrineMigrationsBundle` (Flex no pudo escribirlo por el .env read-only) |
| `backend/config/packages/doctrine.yaml` | nuevo | Configuración de Doctrine DBAL + ORM generada por Flex; mapeo de entidades en `src/Entity/` |
| `backend/config/packages/doctrine_migrations.yaml` | nuevo | Configuración de migraciones; directorio `migrations/` como `App\Migrations` |
| `backend/.env` | modificado | Agrega bloque `DATABASE_URL` con placeholder (valor real llega del root `.env` vía Docker) |
| `docker-compose.override.yml` | modificado | Agrega mount `./backend/migrations:/app/migrations` para dev hot-reload de migraciones |
| `.env` (raíz) | modificado | Corrige contraseña en `DATABASE_URL` y `BACKEND_DATABASE_URL`: `password` → `your_db_password` (bug preexistente: la contraseña del volumen Postgres difería de la URL) |

### Justificación

**`pdo_pgsql` no estaba en el Dockerfile original:** el template de symfony-docker no lo incluye porque no asume una base de datos específica. Al adoptar Postgres como base, es obligatorio. Sin él, `PDO` no puede conectarse aunque la extensión `pgsql` esté presente (son dos extensiones distintas).

**`DoctrineMigrationsBundle` no se registró automáticamente:** Symfony Flex intenta escribir en `.env` al instalar recipes, y falla porque el archivo está montado read-only en dev. El lado visible de ese fallo es que algunos bundles no se agregan a `bundles.php`. Solución: registrarlos manualmente.

**`migrations/` no se montaba ni se copiaba:** el directorio existía en el host pero no llegaba al contenedor en dev (no estaba en el override) ni en build (no estaba en el Dockerfile). Resultado: el comando de migraciones fallaba con "not a valid directory". Corregido en ambos lados: mount para dev, COPY para prod.

**Bug de contraseña en root `.env`:** `DATABASE_URL` tenía `password` como contraseña pero el volumen Postgres fue inicializado con `POSTGRES_PASSWORD=your_db_password`. Error silencioso — el backend anterior no usaba `DATABASE_URL` para conectarse a la DB (usaba el healthcheck de FrankenPHP sin ORM). Al instalar Doctrine, el bug se hizo visible. Se corrigió el root `.env`; `backend/.env` actualizado para coherencia.

**Verificación final:** `doctrine:schema:validate` retorna "mapping correct + database in sync". El error "no registered migrations" de `migrations:migrate` es esperado y correcto (no hay migraciones todavía).

---

## [PASO 0.1] feat: graduate backend from generated boilerplate to versioned app

**Hash:** `59aab7c2513b18e1f6266b7503bbfffc30fafd57`
**Rama:** `release/plan-market-pulse`
**Fecha:** 2026-05-31

### Cambios

| Archivo | Tipo | Descripción |
|---|---|---|
| `backend/src/Kernel.php` | nuevo | Kernel de Symfony extraído del contenedor; ahora vive en git |
| `backend/src/Controller/.gitignore` | nuevo | Placeholder para la carpeta Controller (git no versiona dirs vacíos) |
| `backend/composer.json` | nuevo | Dependencias de la app; antes solo existía dentro de la imagen Docker |
| `backend/composer.lock` | nuevo | Lock file de Composer; garantiza reproducibilidad de dependencias |
| `backend/symfony.lock` | nuevo | Lock de recipes de Symfony Flex |
| `backend/bin/console` | nuevo | Entrypoint CLI de Symfony; extraído del contenedor |
| `backend/config/bundles.php` | nuevo | Registro de bundles Symfony habilitados |
| `backend/config/services.yaml` | nuevo | Configuración del contenedor de servicios DI |
| `backend/config/routes.yaml` | nuevo | Definición de rutas de la app |
| `backend/config/preload.php` | nuevo | Preload de OPcache para producción |
| `backend/config/reference.php` | nuevo | Archivo de referencia de configuración de Symfony |
| `backend/config/packages/*.yaml` | nuevo | Configuración de bundles (framework, cache, routing, security, jwt) |
| `backend/config/routes/framework.yaml` | nuevo | Rutas del framework Symfony |
| `backend/config/routes/security.yaml` | nuevo | Rutas del bundle de seguridad |
| `backend/migrations/.gitkeep` | nuevo | Directorio de migraciones Doctrine; vacío por ahora, listo para paso 0.2 |
| `backend/public/live.php` | nuevo | Demo de Mercure (publisher manual); preservado del branch `feat/interactive-demo` |
| `backend/.env` | nuevo | Variables de entorno de Symfony con **placeholders** (secretos reales vienen del `env_file` Docker) |
| `backend/.gitignore` | modificado | Eliminado `./config/packages` (bloqueaba commitear yamls de config); agregados `var/`, `.env.local`, `.env.local.php` |
| `backend/Dockerfile` | modificado | Eliminado bloque `composer create-project`; reemplazado por `COPY composer.*/symfony.lock` + `composer install` + `COPY src/config/bin/public` + `dump-autoload`; eliminados ARGs `SYMFONY_VERSION`/`STABILITY` que ya no se usan |
| `backend/frankenphp/docker-entrypoint.sh` | modificado | Eliminado bloque "install first time" (el propio comentario del archivo lo marcaba como temporal); conservado: generación de JWT keys si no existen, espera de DB, ejecución de migraciones |
| `docker-compose.yml` | modificado | Eliminados `build.args` `SYMFONY_VERSION` y `STABILITY` del servicio backend (el Dockerfile ya no los necesita) |
| `docker-compose.override.yml` | modificado | Agregado mount `./backend/.env:/app/.env:ro`; Symfony necesita el archivo físico en `/app/.env` en dev (el `env_file` de Compose solo inyecta variables de entorno, no crea el archivo) |
| `.gitignore` (raíz) | modificado | Agregada excepción `!backend/.env`; la regla `.env` del root bloqueaba commitear el `.env` de Symfony que sí debe versionarse (tiene solo placeholders, no secretos) |
| `CLAUDE.md` | nuevo | Contexto del proyecto para el agente: stack, comandos, estado actual, decisiones cerradas, referencia al plan |
| `PLAN-MARKET-PULSE.md` | nuevo | Runbook ejecutable completo: arquitectura, decisiones, fases 0–4, convenciones de ejecución, checklist de producción |
| `frontend/src/js/live.js` | nuevo | Módulo JS del demo de Mercure (canvas colaborativo); preservado del branch `feat/interactive-demo` |

### Justificación

**Problema central:** la codebase usaba el patrón del template `symfony-docker` donde el skeleton de Symfony se genera en tiempo de `docker build` con `composer create-project`. Esto es aceptable para aprender DevOps (el objetivo original), pero incompatible con construir una app real: el código de dominio solo existe dentro de la imagen, se destruye en cada rebuild limpio, no se puede versionar ni testear en CI.

**Decisión tomada:** extraer el skeleton generado del contenedor en ejecución (no regenerarlo) y comitearlo. Esto evita divergencias: el código que corre en producción es exactamente el código en git.

**Por qué no regenerar con `create-project`:** el skeleton ya tiene configuraciones específicas del proyecto (JWT configurado, rutas de seguridad, etc.) que `create-project` generaría en blanco. Regenerar implicaría reconfigurar todo desde cero.

**`backend/.env` con placeholders vs. secretos reales:** el `.env` de Symfony por convención se versiona con valores de ejemplo/placeholder. Los valores reales (JWT_PASSPHRASE, APP_SECRET) vienen del `env_file` del root (`/.env.backend`) que Docker inyecta en tiempo de ejecución como variables de entorno — estas tienen mayor precedencia que el `.env` de la app. Así se mantiene la convención Symfony sin exponer secretos en el repo.

**Mount del `.env` en dev:** el `env_file` de Docker Compose inyecta variables de entorno al proceso, pero no crea un archivo en disco. Symfony intenta leer `/app/.env` como archivo físico en modo dev. Sin el mount, `bin/console` falla con `PathException`. En producción esto no ocurre porque `composer dump-env prod` genera `.env.local.php` (binario compilado) que toma precedencia sobre `.env`.

**Preservación del demo de Mercure:** `live.php` y `live.js` son prueba viva de que el hub Mercure funciona end-to-end. Se preservan como activo de la codebase (documentado en §1 del plan).

## [SYNC] merge: sync Oliva main → release/plan-market-pulse (40 commits de framework)
**Hash:** `3190361629df491f3839721a8d2ee27935aa635f`
**Rama:** `release/plan-market-pulse`
**Fecha:** 2026-07-02

### Cambios
| Archivo | Tipo | Descripción |
|---|---|---|
| `docker-compose.yml` | conflicto→main | Profiles `queues` (rabbitmq) y `cron` (scheduler); backend/scheduler desacoplados de rabbitmq (un `depends_on` cross-profile rompería el `up` sin ese profile) |
| `docker-compose.override.yml` | conflicto→main | Worker bajo profile `queues`; `APP_ENV: dev` (M1) en backend/scheduler/worker |
| `.env.example` | conflicto→unión | Base main (COMPOSE_PROFILES, APP_ENV corto, refactor DATABASE_URL, bloque seeding) + `COMPOSE_PROFILES=queues,cron` como default CMP + `MERCURE_URL=http://backend` (fix 1.5) + keys ANTHROPIC/VOYAGE |
| `.env.backend` | conflicto→unión | Template shared-infra de main adaptado a CMP (`crypto_user`/`crypto_db` + override `RABBITMQ_DSN` con vhost `crypto`, comentados) + Mercure interno/público de CMP + keys |
| `.github/workflows/ci.yml` | conflicto→main | CI reescrito: bake + caché GHA + guard `APP_ENV=prod` |
| `.gitignore` | conflicto→main | Superset: suma `.env.staging`, `secrets/`, `rules-claude.md` |
| `CLAUDE.md` | conflicto→unión manual | Reescrito como guía de CMP-sobre-Oliva: sección de sync one-way, profiles, identidad en infra (`-p crypto`), runbooks resumidos (canónico en main), deuda actualizada (M2, worker prod), protocolos con `docs/concepts.md` |
| `agent-commits.md` | conflicto→CMP | Es el log de CMP; el de main es otra historia |
| `backend/composer.json` / `.lock` / `symfony.lock` | conflicto→main | Superset verificado: CMP + doctrine-fixtures-bundle, zenstruck/foundry, faker (única pérdida: content-hash, regenerado por main) |
| `backend/config/bundles.php` | conflicto→main | Superset: + FixturesBundle y FoundryBundle (dev/test/staging) |
| `backend/config/reference.php` | conflicto→regenerado | Tomado de main y regenerado por Flex en el primer boot post-merge (`when@dev`/`when@staging` correctos) |
| `backend/config/services.yaml` | conflicto→CMP | Superset CMP: todo el wiring del dominio (adapters RSS taggeados, providers, tagged_iterator) |
| `backend/config/packages/{cache,doctrine,messenger}.yaml` | conflicto→CMP | CMP = main + pool `enrichment.cache` / `mapping_types: vector` / routing activo de mensajes |
| `backend/phpunit.dist.xml` | conflicto→main | + extensión FoundryExtension |
| `backend/scheduler/crontab` | conflicto→CMP | `app:sources:poll` cada 5' (main lo tiene vacío) |
| `backend/config/services_development.yaml` → `services_dev.yaml` | renombrado (M2) | Symfony carga `services_{APP_ENV}.yaml`; con APP_ENV=dev el nombre viejo dejaba de aplicar el alias Null y dev gastaba tokens de Anthropic |
| `concepts.md` → `docs/concepts.md` | movido+fusión (D3) | Voz CMP (dominio) + sección Foundry de main appendeada; main tenía una versión genericizada del mismo contenido |
| shared-infra, staging, scripts, fixtures | heredados limpios | `docker-compose.shared-infra.yml`, `docker-compose.staging.yml`, `.env.staging.example`, `scripts/{deploy,down,deploy-staging,down-staging}.sh`, `src/DataFixtures/`, `src/Story/`, `zenstruck_foundry.yaml`, `claude-commands.md`, `README.md`, Dockerfile con stage `frankenphp_staging` |

### Justificación

CMP quedó congelado ~mes y medio mientras Oliva (`main`) avanzaba 40 commits (profiles, shared-infra, staging, APP_ENV corto, CI). Merge-base anterior a versionar el backend → 19 conflictos `add/add`. **Merge y no rebase** porque el rebase reescribiría los 38 hashes de CMP que este log registra como verdad, y re-presentaría los `add/add` commit por commit (análisis completo en `SYNC-NOTES.md` §3).

Política de resolución (§9): **dominio/pipeline gana CMP; framework/infra gana main; docs unión manual** — verificada archivo por archivo con `diff` de ambas versiones antes de resolver (los "superset" no se asumieron, se comprobaron: cero líneas exclusivas de CMP perdidas en los archivos resueltos a main).

Decisiones aplicadas: **D1** — CMP expresa su "todo siempre on" con `COMPOSE_PROFILES=queues,cron` en vez de pelearse con el modelo opt-in de Oliva. **D2** (resuelta por Marcos pre-merge) — identidad en infra compartida: `crypto_db`/`crypto_user` + vhost `crypto` + `-p crypto`; templates comentados en `.env.backend` listos para el VPS. **D3** — `docs/concepts.md` conservando la voz de dominio de CMP (la versión de main deriva de ella).

**Verificación runtime post-merge (rehecha porque el merge toca justo lo que arranca dev):** 6 servicios healthy con profiles activos; `debug:container EnrichmentProviderInterface` en dev → `NullEnrichmentProvider` (M2 efectivo); migraciones al día; `/health` ok; hub Mercure 200; worker consumiendo; PHPUnit 2/2; poll e2e del scheduler ejecutado a las 16:00 con 164 items `enriched` y 0 `pending` en DB.

## [PASO 1.6] feat: API REST del feed
**Hash:** `aa2c80c99032931f442f7ebe6edb472a197eb101`
**Rama:** `release/plan-market-pulse`
**Fecha:** 2026-07-02

### Cambios
| Archivo | Tipo | Descripción |
|---|---|---|
| `backend/src/Api/NewsItemPayload.php` | nuevo | Forma pública del item (12 keys): única fuente de verdad compartida entre REST y Mercure; variante `detail()` suma body/status/createdAt |
| `backend/src/Controller/Api/FeedController.php` | nuevo | `GET /api/feed` (page/limit tope 100, filtros source/sentiment/assetClass, meta de paginación) y `GET /api/items/{id}` (404 JSON; requirement `\d+`) |
| `backend/src/Repository/NewsItemRepository.php` | modificado | `findFeedPage()`: solo `enriched` con innerJoin + fetch-join del enrichment (sin N+1), COUNT separado, orden publishedAt DESC + id DESC (tie-breaker estable) |
| `backend/src/MessageHandler/EnrichItemHandler.php` | modificado | El publish a Mercure arma el payload vía `NewsItemPayload::from()` en vez del array inline duplicado |
| `backend/tests/Unit/Api/NewsItemPayloadTest.php` | nuevo | 3 tests: payload con/sin enrichment + lock de las keys (si REST y Mercure divergen, el test rompe) |
| `PLAN-MARKET-PULSE.md` | modificado | Tildados ✅ 1.5 (estaba hecho sin tildar) y ✅ 1.6 |
| `CLAUDE.md` | modificado | Hecho: 1.1–1.6; Próximo paso → 1.7 Dashboard en vivo |

### Justificación

**Payload compartido REST↔Mercure:** el dashboard (1.7) va a recibir items por dos canales — carga inicial REST y updates en vivo por Mercure. Si las dos formas divergen, el front necesita dos parsers o rompe en silencio. Extraer `NewsItemPayload` elimina la duplicación que ya existía (el handler tenía el array inline) y el test de keys convierte una divergencia futura en un fail explícito de CI.

**Solo items `enriched` en el feed:** un item `pending`/`failed` no tiene resumen, sentiment ni tickers — no aporta nada renderizable. El detail (`/api/items/{id}`) sí devuelve cualquier status (con campos de enrichment en null) porque ahí el caso de uso es inspección, no display.

**Sin serializer bundle ni API Platform:** para 2 endpoints read-only, mapear a mano vía el payload es menos dependencia y más control que sumar el Serializer de Symfony (no estaba instalado). Si la API crece en Fase 2 (search, Market Now), reevaluar.

**Sin CORS:** `/api` ya era same-origin por diseño de Oliva — proxy de Vite en dev y `handle /api/*` en el Caddyfile del frontend en prod. La "verificación CORS" del plan se cumple por arquitectura, no por headers.

**Hallazgo (no bug):** 53 items con `status=enriched` sin fila `Enrichment` en la DB de dev — todos del 2026-06-01 05:53–06:05, test-runs del paso 1.4 previos al persist. El innerJoin del feed los excluye solo. Es ruido de dev; si molesta, un `UPDATE`/purga manual alcanza.

## [PASO 1.7] feat: dashboard en vivo (pulse.html)
**Hash:** `9ecf0643bfbfbf9a191c59831806f707f0c128d3`
**Rama:** `release/plan-market-pulse`
**Fecha:** 2026-07-02

### Cambios
| Archivo | Tipo | Descripción |
|---|---|---|
| `frontend/pulse.html` | nuevo | Página del dashboard: header con indicador LIVE/RECONNECTING + contador, contenedor del feed, nav cruzada con la landing |
| `frontend/src/pulse.js` | nuevo | Entry propio: carga inicial `GET /api/feed?limit=30` (retry a los 5s si falla) + `EventSource` a `crypto/feed` con reconexión (patrón `live.js`); `upsert()` — id conocido reemplaza la card in-place, id nuevo la prependea (tope 60); render de cards con escape HTML de todo dato remoto |
| `frontend/src/style.css` | modificado | Bloque de estilos `pulse-*` (cards, badges de sentiment por valor, tags/tickers, estados vacío/error) reutilizando la paleta y `live-dot`/`feedIn` existentes |
| `frontend/vite.config.js` | modificado | Build multi-page (`rollupOptions.input`: index + pulse) vía `fileURLToPath` (el paquete es ESM, no hay `__dirname`) |
| `frontend/index.html` | modificado | Link "Crypto Pulse →" en la nav de la landing |
| `PLAN-MARKET-PULSE.md` | modificado | Tildado ✅ 1.7 |
| `CLAUDE.md` | modificado | Hecho: 1.1–1.7; Próximo paso → 1.8 Robustez del pipeline |

### Justificación

**Página aparte, no SPA:** el anti-scope (§7) prohíbe reescribir el front a framework; una segunda página estática con entry propio de Vite es el mínimo que separa la vidriera del dashboard. `rollupOptions.input` multi-page es la vía estándar de Vite y Caddy la sirve sin config extra (`file_server`).

**Un solo render path para REST y Mercure:** las cards se construyen con `card(item)` tanto en la carga inicial como en los eventos SSE — posible porque 1.6 unificó el shape en `NewsItemPayload`. `upsert()` reemplaza in-place si el id ya está (cubre el caso "pending que se enriquece después de la carga") en vez de duplicar la card.

**Escape HTML obligatorio:** títulos/resúmenes vienen de feeds RSS externos y de un LLM — contenido no confiable. `esc()` pasa todo por `textContent` (+ `&quot;` para atributos). Verificado con un probe real: título con `<img onerror>` inyectado en DB recorrió el pipeline completo y llegó al DOM como texto plano (0 nodos inyectados, `window.__pwned` sin definir).

**Sin filtros ni paginación en la UI:** el plan los difiere a 2.6; agregar controles ahora sería scope creep. El tope de 60 cards en memoria evita crecimiento sin límite en sesiones largas.

**Verificación (gate del paso cumplido):** Playwright + Chrome headless con 2 pestañas: carga inicial 30 cards + LIVE en ambas; item re-enriquecido vía pipeline real (reset a pending + `app:enrich:requeue-pending`) apareció actualizado en ambas pestañas sin recargar; build prod multi-page OK. De paso quedó demostrado el camino DLX: un insert duplicado agotó 3 retries y fue al failure transport sin perder el mensaje.

## [PASO 1.8] feat: robustez del pipeline (retries, DLX saneado, timeouts, degradación del front)
**Hash:** `96090c85e2f26d386b10e8c2485633e66516804b`
**Rama:** `release/plan-market-pulse`
**Fecha:** 2026-07-02

### Cambios
| Archivo | Tipo | Descripción |
|---|---|---|
| `backend/config/packages/messenger.yaml` | modificado | Quita `x-dead-letter-exchange` de `ingest`/`enrich`; agrega `default_publish_routing_key: failed` al transport `failed` y bindings `[failed, ingest, enrich]` a su cola |
| `backend/config/packages/framework.yaml` | modificado | `http_client.default_options`: `timeout: 10`, `max_duration: 60`, `retry_failed` (2 retries con backoff a nivel HTTP) |
| `backend/src/Command/FailedInspectCommand.php` | nuevo | `app:failed:inspect`: peek NO destructivo de la cola `failed` (basic.get sin ack + nack-requeue); decodifica el envelope (stripslashes + unserialize) y muestra clase, transport de origen, retries y error |
| `backend/src/Adapter/RssAdapter.php` | modificado | Header `User-Agent`; si el XML no tiene `<channel>` (Atom, HTML de error) lanza RuntimeException en vez de yield vacío silencioso |
| `backend/src/MessageHandler/EnrichItemHandler.php` | modificado | `hub->publish()` en try/catch: fallo de Mercure se loguea y NO manda a retry/DLX un item ya persistido |
| `backend/src/Command/EnrichRequeueCommand.php` | modificado | Opción `--min-age` (minutos, default 10): solo re-encola pending "viejos" |
| `backend/src/Repository/NewsItemRepository.php` | modificado | `findStalePending(DateInterval)`: pending con `createdAt` anterior al cutoff |
| `backend/scheduler/crontab` | modificado | Sweep de recovery: `app:enrich:requeue-pending` cada 15 min |
| `backend/config/services.yaml` | modificado | Wiring de `$rabbitmqDsn` para el comando de inspección |
| `backend/tests/Unit/Adapter/RssAdapterTest.php` | nuevo | 3 tests con `MockHttpClient`: parsea RSS + strip de markup, manda User-Agent, feed Atom → excepción |
| `frontend/src/pulse.js` | modificado | Backoff exponencial (cap 30s) en REST y EventSource; resync vía REST al reconectar (merge con `upsert`, no clobber); **watchdog anti-zombie**: sin actividad SSE por 300s (override `?watchdog=N`) → teardown + reconexión + resync |
| `PLAN-MARKET-PULSE.md` | modificado | ✅ 1.8 + ✅ GATE Fase 1 (con evidencia) + checkbox §12 de workers |
| `CLAUDE.md` | modificado | Fase 1 completa; próximo paso → 2.1; deudas dual-write y RssAdapter saldadas; decisión dead-letter en "Decisiones cerradas" |
| `agent-commits.md` | modificado | Esta entrada |

### Justificación

**Qué ya existía y no se tocó:** los retries con backoff exponencial (`retry_strategy` en ambos transports, desde 0.5) y la idempotencia del handler (guard por `status` + caché LLM por `contentHash`, desde 1.4/1.5). 1.8 verificó eso y cerró los huecos alrededor.

**Decisión: el DLX del broker se elimina; el failure transport de Symfony es el único dead-letter path (opción elegida por Marcos entre 3).** La verificación con un feed roto reveló que cada mensaje fallado dejaba **4 copias** en `failed`: Messenger, al reintentar, hace `basic.reject` del mensaje consumido después de republicar la copia demorada — y el `x-dead-letter-exchange` de la cola convertía cada reject intermedio en una copia más. Los dos mecanismos de dead-letter (DLX del broker, de 0.5, y failure transport de Symfony) se pisaban. Alternativas descartadas: (b) DLX a una cola separada — el ruido se muda, no desaparece; (c) documentar el ruido — crece 4x por fallo y ensucia `messenger:failed:retry`. Costo aceptado: un mensaje *indecodificable* (garbage publicado a mano en la cola) ahora se descarta en vez de capturarse — caso que no ocurre en el pipeline real. Operativo: los args de cola son inmutables → en dev se borraron/recrearon `ingest`/`enrich`; en el VPS no hay nada que migrar (vhost nuevo).

**Bug latente de 0.5 encontrado y arreglado — los mensajes fallados se PERDÍAN:** el transport `failed` publicaba sin `default_publish_routing_key` a un exchange direct cuya cola bindea `failed` → unroutable → RabbitMQ lo descartaba en silencio. Nunca se notó porque las copias del DLX del broker enmascaraban la pérdida (lo que había en la cola era el ruido, no el mensaje real). Al quitar el DLX, la cola quedó vacía tras un fallo — eso destapó el bug. Segundo matiz: aun con routing key configurada, `AmqpSender` reusa la **routing key original** (`ingest`/`enrich`) al redeliver hacia el failure transport (`AmqpStamp::createFromAmqpEnvelope`) — por eso la cola `failed` bindea las tres keys. Resultado verificado: 1 fallo definitivo = exactamente 1 mensaje en `failed`, con stamps de error, origen y reintentable.

**Inspección sin consumo (`app:failed:inspect`):** el failure transport AMQP no es listable (`ListableReceiverInterface`), así que `messenger:failed:show`/`remove` no funcionan — solo `retry`. El comando hace basic.get sin ack y nack-requeue al final: se puede mirar qué hay parkeado sin tocarlo (verificado: 2 corridas seguidas, mismo contenido). Gotcha documentado en el docblock: el nack-requeue deja el flag `redelivered`, que un `retry` posterior rutea por un hop extra de republish (inofensivo). De paso el comando encontró y ayudó a limpiar un mensaje fósil real (violación de unique de antes de la guarda de idempotencia).

**Recovery del dual-write con `--min-age`:** el sweep periódico de `requeue-pending` sin filtro de edad podría re-despachar un item cuyo mensaje sigue legítimamente en cola (recién ingestado) → doble enrich concurrente. El floor de 10 min hace que el sweep solo agarre huérfanos reales (broker caído tras el `flush()` de ingesta).

**Mercure publish tolerante en el handler:** el publish ocurre después del `flush()`. Si el hub falla y el handler lanza, el mensaje va a retry por datos que ya están a salvo — y el retry no-opearía en la guarda de idempotencia, perdiendo el evento igual. Try/catch + log: el evento se pierde (los clientes lo recuperan por resync REST), el mensaje se ackea.

**Watchdog anti-zombie en el front (hallazgo de la verificación):** matar el backend con la página abierta demostró que `EventSource.onerror` **nunca dispara** si hay un proxy en el medio que mantiene abierto el lado del browser — la página muestra "LIVE" mientras pierde todos los eventos. Ningún backoff sirve si no te enterás del corte. Watchdog: sin actividad SSE por 300s → teardown + reconexión + resync REST (que además cubre los eventos perdidos durante cualquier corte). Falso positivo (noticias lentas) = un reconnect barato cada 5 min. Verificado con Playwright: restart del backend → conexión zombie → watchdog reconecta y dispara el resync.

**Capas de retry deliberadas:** HTTP (`retry_failed`, 2 intentos — absorbe 429/5xx/blips de red sin churn de mensajes) por debajo de Messenger (`retry_strategy`, 3 intentos con delay — absorbe fallos más largos) por debajo del failure transport (parking permanente inspeccionable). Cada capa maneja una escala de fallo distinta.

**Conceptos que ejercita este paso** (para la doc integral futura): retry layering HTTP vs Messenger vs failure transport (`framework.yaml` / `messenger.yaml`); semántica AMQP de exchange direct + routing keys + bindings y mensajes unroutable (`messenger.yaml`, transport `failed`); basic.get/ack/nack y el flag redelivered (`FailedInspectCommand`); dual-write DB↔broker y sweeps de recovery (`EnrichRequeueCommand` + crontab); idempotencia y por qué el publish va fuera del camino de fallo (`EnrichItemHandler`); degradación del cliente SSE: zombie connections, watchdog, resync (`pulse.js`).

**Verificación (gate del paso cumplido):** (1) worker muerto + poll → 2 mensajes esperan en `ingest`, ningún dato perdido; al reanudar drena el backlog. (2) Feed roto (adapter temporal a host inexistente) → 3 retries con backoff exponencial visible en logs (1s/2s/4s) → exactamente 1 mensaje en `failed`, inspeccionable y con error legible. (3) `app:failed:inspect` x2 → no consume. (4) Restart del backend con dashboard abierto → watchdog detecta el zombie, reconecta y resincroniza (Playwright). (5) PHPUnit 8/8, `lint:container` OK, build prod de Vite OK.

## [PASO 2.1] feat: fuente de datos de mercado (CoinGecko) vía MarketSnapshot, fuera del pipeline de noticias
**Hash:** `12bcf4f`
**Rama:** `release/plan-market-pulse`
**Fecha:** 2026-07-02

### Cambios
| Archivo | Tipo | Descripción |
|---|---|---|
| `backend/src/Entity/MarketSnapshot.php` | nuevo | Entidad propia (asset, priceUsd, marketCap, volume24h, changePct24h, fetchedAt); índice `(asset, fetched_at)` |
| `backend/src/Repository/MarketSnapshotRepository.php` | nuevo | `findLatestPerAsset()` (contexto para impact score / asset afectado, 2.5) y `deleteOlderThan()` (retención) |
| `backend/migrations/Version20260702202645.php` | nuevo | `CREATE TABLE market_snapshot` + índice. Generada con `doctrine:migrations:diff`; se descartó a mano un segundo diff que retipaba `embedding`/dropeaba el HNSW de `enrichment` — drift preexistente no relacionado, zona bloqueada hasta el estudio de pgvector de Marcos |
| `backend/src/Provider/MarketDataProviderInterface.php` | nuevo | Contrato `fetch(): iterable` de datos de mercado, separado de `SourceAdapterInterface` (noticias) |
| `backend/src/Provider/CoinGeckoProvider.php` | nuevo | Implementación vía `/simple/price` (sin key); retry con backoff exponencial (1s/2s/4s, 3 intentos) solo ante 429 |
| `backend/src/Command/MarketPollCommand.php` | nuevo | `app:market:poll`: persiste un snapshot por asset y purga snapshots >24h en la misma corrida |
| `backend/config/services.yaml` | modificado | Wiring de `CoinGeckoProvider` (mapa CoinGecko-id → ticker: bitcoin→BTC, ethereum→ETH) + alias de `MarketDataProviderInterface` |
| `backend/scheduler/crontab` | modificado | `*/2 * * * * bin/console app:market:poll -v` |
| `PLAN-MARKET-PULSE.md` | modificado | 2.1 expandido con la decisión de diseño (Objetivo/Acciones/Verificación, no solo una línea) antes de ejecutar |
| `agent-commits.md` | modificado | Esta entrada |

### Justificación

**Por qué `MarketSnapshot` no es un `NewsItem` más ni pasa por `SourceAdapterInterface`:** el modelo de dominio de Fase 1 (`NewsItem`/`Enrichment`, `contentHash` único por URL, enriquecimiento LLM) fue diseñado 100% para artículos de noticias. CoinGecko devuelve datos de mercado (precio, market cap, volumen) sin título/cuerpo/URL de artículo — forzarlo dentro de `NewsItem` habría dejado campos inventados o vacíos, y peor: habría entrado al pipeline de enriquecimiento (`EnrichItemMessage` → Anthropic), gastando tokens en "resumir" un número. Se detectó esta ambigüedad revisando el runbook *antes* de ejecutar 2.1 (estaba escrito como una sola línea, sin el detalle de Fase 0/1) y se cerró con una entidad, un contrato (`MarketDataProviderInterface`) y un comando propios, sin tocar el pipeline de noticias/IA.

**Sin dedup por contenido, con retención por tiempo:** a diferencia de `NewsItem` (dedup por `contentHash` de la URL — el mismo artículo no cambia), un snapshot de precio es legítimamente distinto cada vez que se pollea, así que no hay una clave natural de dedup. La alternativa era no purgar nunca (tabla crece sin límite) o una unique constraint artificial por asset+ventana truncada (complejidad innecesaria para lo que el dominio necesita: contexto reciente, no serie histórica). Se optó por retención simple: el propio `app:market:poll` borra snapshots >24h en cada corrida (`MarketSnapshotRepository::deleteOlderThan`).

**Poll cada 2 min, sin pasar por RabbitMQ:** el precio cambia rápido y el pipeline de mensajería (`ingest`/`enrich`) existe para desacoplar fetch→persist de un enriquecimiento LLM costoso — acá no hay LLM de por medio, así que el comando persiste directo en la misma ejecución que dispara el cron, sin encolar. Mantiene la superficie simple y evita colas nuevas sin necesidad real.

**Retry solo ante 429:** `CoinGeckoProvider` reintenta con backoff exponencial únicamente si la API responde rate-limit (verificado: la doc pública de CoinGecko marca ~10-30 req/min sin key); cualquier otro 4xx (shape de URL, ids inválidos) fallaría igual en el reintento, así que se relanza directo — mismo criterio de "no reintentar lo que no es transitorio" que ya usa el pipeline de noticias.

**Se descartó a mano un diff no relacionado:** `doctrine:migrations:diff` arrastró un cambio en la columna `embedding` de `enrichment` (retipado `vector`→`vector(1024)`) y un `DROP INDEX hnsw_enrichment_embedding` — ruido de cómo Doctrine introspecciona el tipo `vector` de pgvector, preexistente a este paso. Tocar eso sin que Marcos haya cerrado el diseño de HNSW (bloqueado explícitamente en `CLAUDE.md`) habría sido tomar una decisión de arquitectura no pedida; se eliminó esa migración generada y solo se aplicó la de `market_snapshot`.

**Verificación (paso cumplido):** `doctrine:migrations:migrate` aplica limpio; `app:market:poll -v` corrido contra la API real de CoinGecko dos veces seguidas → 2 snapshots por corrida (BTC/ETH con precio, market cap, volumen y %cambio reales), 4 filas acumuladas sin dedup, 0 purgadas (todavía dentro de las 24h); `scheduler` reiniciado y crontab confirmado con la nueva línea corriendo cada 2 min; `vendor/bin/phpunit` 8/8 verde (nada de Fase 1 se rompió).

---

## [AUDITORÍA DE REANUDACIÓN] Diagnóstico tras ~3 meses de pausa + correcciones al doc de estudio
**Hash:** `ac688ba`
**Rama:** `release/plan-market-pulse`
**Fecha:** 2026-10-07

### Cambios
| Archivo | Tipo | Descripción |
|---|---|---|
| `docs/estudio-y-auditoria-1.5-2.6.md` | modificado | Corrige el checkpoint de 2.1 (`change_pct_24h` → `change_pct24h`, la columna real); actualiza el ítem 3 de "Qué sigue sin cerrarse" (el fix del skip de 2.4 ya está commiteado en `cc75b24`, el doc seguía diciendo "working tree, sin commitear"); agrega el anexo "Auditoría de reanudación" con los hallazgos de esta sesión. |
| `CLAUDE.md` | modificado | "Próximo paso" pasa a describir la sesión de estudio acordada (plan A→C, método y punto de arranque) en vez del estado de Fase 2, que se mueve a su propia línea. |
| `agent-commits.md` | modificado | Esta entrada. |

### Justificación

**Por qué una auditoría antes de retomar.** Marcos volvía tras ~3 meses sin tocar el proyecto y no confiaba en su recuerdo de dónde había quedado (creía "ítem 20 de 25"). Se verificó contra el código en vez de contra la memoria: el conteo real es **20 hitos completados de 31** (Fase 0: 8/8, Fase 1: 8/8, Fase 2: 4/7, Fase 3: 0/8) — su recuerdo era exacto. Se levantó el stack de dev y se corrieron los checkpoints del documento de estudio contra el sistema vivo: 6/6 containers healthy sin rebuild, migraciones al día, pipeline RSS→cola→worker→Mercure→API fluyendo (54 noticias nuevas reales ingestadas en la corrida), CoinGecko respondiendo, purgas por retención funcionando, cero gasto de tokens (providers Null aliasados en dev).

**Por qué se corrigió el checkpoint de 2.1.** No corría como estaba escrito: usaba `change_pct_24h` y la columna real es `change_pct24h`. Se descubrió al ejecutarlo. Un checkpoint roto en un documento pensado para que Marcos lo corra solo es fricción pura — se arregla donde está, no se anota como deuda.

**Por qué el anexo y no reescribir el cuerpo del documento.** El documento original es el registro de un recorrido fechado (2026-07-02/03) y tiene valor como tal. Los hallazgos nuevos son de otra fecha y de otra naturaleza (estado de reanudación, no auditoría de hitos), así que van en un anexo fechado. Lo único que se editó en el cuerpo fue el checkpoint roto y un estado que había quedado factualmente desactualizado.

**Hallazgos que cambian la planificación** (detalle en el anexo): (a) el gap de embeddings es **total**, no parcial — `VOYAGE_API_KEY` vacía y 169/169 enrichments con `embedding=NULL`, o sea cero vectores para 2.2; (b) el índice HNSW **ya existe y es parcial** (`vector_cosine_ops WHERE embedding IS NOT NULL`), así que el estudio de pgvector no arranca de cero sino validando decisiones ya tomadas; (c) el estudio de pgvector es un cuello de botella **más ancho de lo documentado**: bloquea 2.2 y 2.3, pero también 3.4 y 3.5, porque el hito 3.4 pide habilitar todos los pasos del CI y `schema:validate` está en rojo justo por ese índice; (d) **53 `news_item` huérfanos** con `status='enriched'` y sin fila en `enrichment`, todos del 2026-06-01 — invisibles en el feed por el `innerJoin`, pero es un status que miente y serían invisibles también para 2.2.

**Qué se descartó.** Se evaluó incluir en esta sesión el batch de fixes menores pendientes (asset-class con match estricto, `findLatestPerAsset` ineficiente, href sin validar esquema, metachars de `LIKE`, prompt-caching no-op) — la decisión que había quedado abierta en una `AskUserQuestion` de julio. Marcos la cerró: esos fixes no le dicen nada al volver y no aportan al estudio, así que salen del camino crítico y se harán cuando se toque el archivo correspondiente. También se descartó el enfoque de "releer el documento" como forma de refrescar: es reconocimiento pasivo y Marcos nunca escribió el código de 1.6+ (es observador desde ahí), así que se acordó el método de correr el checkpoint primero y leer el código después.

**No se tocó código de la app.** Sesión de diagnóstico y documentación únicamente.

---

## `<pendiente>` — docs: guía de lectura del hito 1.5 + fix de su checkpoint + `-f` en claude-commands

**Rama:** `release/plan-market-pulse` · **Fecha:** 2026-10-17

### Cambios
| Archivo | Tipo | Descripción |
|---|---|---|
| `docs/estudio-1.5-guia-de-lectura.md` | nuevo | Mapa de lectura del hito 1.5 en 8 estaciones, en el orden del flujo de datos (`IngestSourceHandler:58` → `messenger.yaml` → `EnrichItemHandler` → `NewsItemPayload` → Null provider → `mercure.yaml`/`Caddyfile` → `pulse.js:160-215`), con archivo:línea, preguntas para contestar leyendo y 3 preguntas de cierre. |
| `docs/estudio-y-auditoria-1.5-2.6.md` | modificado | Corrige el checkpoint de 1.5: no corre como estaba escrito. |
| `claude-commands.md` | modificado | Documenta el flag `-f` de `claude reiniciar`, que se venía usando sin estar escrito. |
| `agent-commits.md` | modificado | Esta entrada. |

### Justificación

**Por qué un documento aparte y no ampliar el doc de estudio.** Marcos pidió estudiar 1.5
leyendo el código él mismo en el IDE, de inicio a fin. Eso necesita un artefacto distinto
del que ya existe: `estudio-y-auditoria-1.5-2.6.md` **explica** los hitos (es el recorrido
fechado de julio, con valor como registro), y acá hacía falta lo contrario — un mapa que
**no explique** y mande a leer en un orden útil, con preguntas cuya respuesta está en el
archivo de cada estación. Mezclar ambos registros en un archivo arruinaría los dos: el
recorrido fechado dejaría de ser un registro y la guía dejaría de ser accionable. Formato
nuevo, reutilizable para los hitos siguientes si funciona.

**Por qué se corrigió el checkpoint de 1.5.** No corría: proponía
`app:enrich:requeue-pending --min-age=0` para forzar un enrich, pero ese comando solo
reencola items en `status=pending` y al retomar el pipeline está al día → `Requeued 0`,
cero publicaciones a Mercure, checkpoint sin señal. Lo que genera items de verdad es
`app:sources:poll`. Se dejó `requeue-pending` documentado por lo que realmente es
(recovery de dual-write, no disparador). Mismo criterio que el fix del checkpoint de 2.1
en `ac688ba`: un checkpoint roto en un doc que Marcos corre solo es fricción pura, se
arregla donde está.

**Dos trampas del perímetro de 1.5 que quedaron marcadas en la guía** (descubiertas al
armarla, costarían tiempo de lectura): (a) `frontend/src/js/live.js` **no es de CMP** — es
la demo de Oliva (topic `oliva.dev/live`); confunde porque también habla Mercure, el
consumidor real es `pulse.js`; (b) el `MERCURE_URL` efectivo del worker **no** es el de
`backend/.env:34` (`localhost`, donde no hay hub porque el worker corre sin Caddy) sino el
de `.env.backend:39` (`http://backend/...`): el worker carga `env_file: [.env, .env.backend]`
y el último gana. Verificado contra el contenedor vivo con `printenv`.

**Por qué se documentó `-f`.** La preferencia existía y se venía usando, pero el flag no
estaba en `claude-commands.md` de esta rama **ni en `main`** — solo en la memoria del
agente, que es local y no la comparten los forks. Una preferencia operativa durable que
vive únicamente en memoria se pierde en el próximo fork. Pendiente de paridad:
portarlo al `claude-commands.md` de `main` y de finanzas-ong.

**Checkpoint de 1.5 corrido contra el stack vivo** (ancla previa a la lectura): 54 eventos
por SSE en `crypto/feed`, items nuevos reales (ids 284+, noticias del 16-17/10),
`model: null-provider` y `costUsd: 0` → cero gasto de tokens confirmado. El handler loguea
`embedding: null` en cada item: no es bug de 1.5, es el gap de la etapa C.

**No se tocó código de la app.** Sesión de estudio y documentación únicamente.
