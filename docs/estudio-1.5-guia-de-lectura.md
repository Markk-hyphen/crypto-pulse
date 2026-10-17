# Hito 1.5 — guía de lectura en el IDE

> **Qué es esto.** No explica el hito (eso está en `estudio-y-auditoria-1.5-2.6.md` §1.5).
> Es el **orden en que conviene abrir los archivos** para recorrer 1.5 de punta a punta
> siguiendo el flujo de datos, con las preguntas que valen contestar leyendo el código.
> Las respuestas están todas en los archivos de cada estación: no hace falta buscar afuera.

**Perímetro de 1.5:** desde que un item queda `pending` en la DB hasta que el browser
pinta la card sin recargar. 9 archivos, ~700 líneas en total (la mitad es `pulse.js`).

---

## Estación 0 — re-anclar el comportamiento (terminal del IDE, 1 min)

```bash
docker compose up -d                         # 6/6 healthy
# Terminal A — suscribirse al topic:
curl -N -H 'Accept: text/event-stream' 'http://localhost/.well-known/mercure?topic=crypto/feed'
# Terminal B — generar items nuevos de verdad:
docker compose exec backend bin/console app:sources:poll
docker compose logs -f worker                # ver los enriched pasar
```
Tenés que ver eventos `data: {...}` con `"model":"null-provider"` y `"costUsd":"0.000000"`.
Ese JSON es el artefacto que produce todo lo que sigue: tenelo a la vista mientras leés.

---

## Estación 1 — ¿quién dispara el enrich?
**`backend/src/MessageHandler/IngestSourceHandler.php`** (78 líneas) — mirar `:58`.

- ¿En qué orden pasan el `flush()` del `NewsItem` y el `dispatch(new EnrichItemMessage(...))`?
- El mensaje viaja con **el id**, no con la entidad. ¿Qué gana eso cuando el worker lo
  consume 30 segundos después, en otro proceso?
- Si RabbitMQ está caído justo después del flush: el item queda `pending` y el mensaje
  se perdió. ¿Quién lo rescata? (pista: `NewsItemRepository.php:109`, y de ahí a
  `src/Command/EnrichRequeueCommand.php` — es el "dual-write" del comentario)

## Estación 2 — el transporte
**`backend/config/packages/messenger.yaml`** — leer el bloque `enrich:` (`:27-40`).

- Dos transportes separados (`ingest`, `enrich`), dos exchanges, dos retry_strategy
  distintas. ¿Por qué el enrich tiene `delay: 2000` y el ingest `1000`?
- El comentario de `:13-18` explica por qué **no** hay `x-dead-letter-exchange` a nivel
  cola. Es decisión del 1.8, pero leelo acá: condiciona qué pasa si el handler tira.

## Estación 3 — el corazón del hito
**`backend/src/MessageHandler/EnrichItemHandler.php`** (102 líneas) — leer entero, es el hito.

Orden de lectura dentro del archivo: constructor (`:22-30`) → guard (`:41-47`) →
providers (`:49-57`) → persist/flush (`:59-75`) → publish (`:82-92`).

- **El guard de `:41`:** ¿qué pasa exactamente si el mismo `EnrichItemMessage` se consume
  dos veces? Seguí la rama: `return` temprano, sin enrichment y **sin publish**.
- **`:74-75` antes de `:82-92`:** el publish va después del flush. Armá el contrafáctico:
  si publicaras antes y el flush fallara, ¿qué vería el browser que no está en la DB?
- **El try/catch de `:82-92`:** leé el comentario de `:77-81` *después* de intentar
  responderte solo por qué no se deja propagar la excepción. La clave es que el retry
  chocaría contra el guard de la Estación 3 — el evento se pierde igual, pero además
  ensuciás la cola `failed` por un dato que está a salvo.
- `HubInterface` (`:28`) es **lo único genuinamente nuevo** de 1.5 según la auditoría:
  el hub entra por constructor como una salida más del dominio, igual que el `EntityManager`.
  ¿Qué te permite eso en un test unitario del handler?
- `:99` loguea `embedding: null` en cada corrida. Eso **no** es un bug de 1.5 —
  es el gap que bloquea la etapa C (pgvector). Anotalo y seguí.

## Estación 4 — la forma del payload
**`backend/src/Api/NewsItemPayload.php`** (54 líneas) + **`backend/tests/Unit/Api/NewsItemPayloadTest.php`** (71).

- `NewsItemPayload::from()` es la **única** fuente de la forma pública: la usan el publish
  de Mercure (`EnrichItemHandler:85`) y el REST (`FeedController`). ¿Qué se rompe si alguien
  agrega una key en un camino y no en el otro? Corré el test y mirá qué assertea.
- Comparalo con el JSON que capturaste en la Estación 0, key por key. Son 13.

## Estación 5 — el provider que no gasta tokens
**`backend/config/services_dev.yaml`** (4 líneas) + **`backend/src/Provider/NullEnrichmentProvider.php`** (26).

- El alias de interfaz → implementación. ¿Por qué el archivo se llama `services_dev.yaml`
  y no `services_development.yaml`? (Symfony carga `services_{APP_ENV}.yaml`; el nombre
  viejo dejó de aplicar en el sync del 2026-07-02 y dev volvió a gastar tokens.)
- Mirá qué devuelve el Null provider y de dónde sale el prefijo `[DEV]` que viste en el SSE.
- Compará la firma con `AnthropicEnrichmentProvider.php`: misma interfaz, cero cambios
  en el handler para pasar de uno a otro.

## Estación 6 — el hub, y el gotcha de las env
**`backend/config/packages/mercure.yaml`** + **`backend/frankenphp/Caddyfile:33-38`**.

- El hub **no** es un servicio aparte: es el módulo `mercure` de Caddy embebido en el
  contenedor `backend` (`Caddyfile:34`), con `anonymous` (los subscribers no necesitan JWT)
  y `publisher_jwt` (el backend sí firma para publicar).
- **El gotcha.** `backend/.env:34` dice `MERCURE_URL=http://localhost/...`, pero el worker
  corre en **otro contenedor, sin Caddy** — `localhost` ahí no tiene hub. Lo que realmente
  aplica es `.env.backend:39` → `http://backend/.well-known/mercure`, porque el worker carga
  `env_file: [.env, .env.backend]` (`docker-compose.override.yml:21-23`) y **el último gana**.
  Verificalo vos: `docker compose exec worker printenv | grep MERCURE_URL`.
- ¿Por qué `MERCURE_PUBLIC_URL` sí es `localhost`? Pensá quién consume cada una:
  una la usa PHP server-side, la otra termina en el browser.

## Estación 7 — el consumidor
**`frontend/src/pulse.js`** (330 líneas) — leer solo `:160-215`.

> ⚠️ **No abras `frontend/src/js/live.js`.** Es la demo de Oliva (topic `oliva.dev/live`),
> no tiene nada que ver con CMP. Confunde porque también habla Mercure.

- `:162-164` arma la URL y abre el `EventSource` contra `crypto/feed`. Notá que el topic
  es un string plano, no una URL — tiene que matchear **exacto** el de `EnrichItemHandler:84`.
- `:12-13` documenta el `EventSource` "zombie": el proxy mantiene abierta la conexión del
  browser aunque el upstream muera, así que `onerror` nunca dispara. Seguí cómo se detecta
  eso (`lastActivity`, `:25`) — es la razón de que el indicador LIVE sea confiable.
- `:186-209` es un **segundo** `EventSource` en su propio topic (market-now, hito 2.6).
  Leé el comentario de `:186`: por qué no reusar el stream del feed.

---

## Cerrar el recorrido

Si podés responder estas tres sin volver al código, 1.5 está cerrado:

1. El worker enriquece un item, lo flushea OK, y el hub está caído. ¿Qué queda en la DB,
   qué queda en la cola `failed`, y qué ve el browser al recargar?
2. ¿Por qué el publish manda `NewsItemPayload::from(...)` y no el `Enrichment` serializado?
3. ¿Qué cambia en `EnrichItemHandler` si mañana querés enrichment real en dev? (respuesta
   correcta: nada en el handler.)

**Lo que quedó anotado como deuda, no como duda:** `embedding=NULL` en todos los
enrichments (gap de la etapa C) y los 53 `news_item` huérfanos del 2026-06-01.
Ver `estudio-y-auditoria-1.5-2.6.md` y la memoria del proyecto.
