# Conceptos técnicos

Explicaciones teóricas de tecnologías y conceptos usados en el proyecto.
Este archivo es acumulativo: nunca se borra contenido, solo se agrega — ver el
protocolo de explicaciones conceptuales en `AGENTS.md`.

---

## pgvector

### Qué es

`pgvector` es una extensión de PostgreSQL que agrega un tipo de dato nativo llamado `vector` y operadores para hacer **búsqueda por similitud** entre vectores. En términos simples: te permite guardar y comparar listas de números flotantes directamente en tu base de datos Postgres existente, sin necesidad de una base de datos vectorial separada (Pinecone, Weaviate, Qdrant, etc.).

### Para qué sirve en este proyecto

Cuando un modelo de IA procesa una noticia cripto, genera un **embedding**: una lista de ~1500 números flotantes que representan el *significado semántico* del texto. Dos noticias sobre el mismo tema tienen embeddings parecidos (vectorialmente cercanos); dos noticias sin relación tienen embeddings lejanos.

`pgvector` permite hacer consultas como:
> *"Dame las 5 noticias más similares semánticamente a esta query del usuario"*

sin mover los datos fuera de Postgres.

### Cómo funciona por dentro

Un embedding es un punto en un espacio de alta dimensión (por ejemplo, 1536 dimensiones si usás `text-embedding-3-small` de OpenAI). La "distancia" entre dos puntos mide qué tan parecidos son semánticamente.

`pgvector` soporta tres métricas de distancia:

| Operador | Métrica | Cuándo usarla |
|---|---|---|
| `<->` | L2 (distancia euclidiana) | cuando la magnitud importa |
| `<=>` | Cosine similarity | **la más común para texto** — mide ángulo, ignora magnitud |
| `<#>` | Inner product | embeddings normalizados |

Para texto casi siempre se usa **cosine similarity** (`<=>`).

### Índices: HNSW vs IVFFlat

Sin índice, una búsqueda de similitud es un *full scan* (compara el vector query contra todos los vectores de la tabla). Escala mal. `pgvector` ofrece dos índices aproximados (ANN - Approximate Nearest Neighbor):

**IVFFlat** (Inverted File with Flat quantization):
- Divide los vectores en `lists` clusters (centroides).
- Para buscar, primero encuentra los clusters más cercanos y solo escanea esos.
- Más rápido de construir, menos memoria.
- Necesita datos cargados *antes* de crear el índice para que los clusters sean buenos.
- Parámetro clave: `lists` (típicamente `sqrt(n_rows)`).

**HNSW** (Hierarchical Navigable Small World):
- Construye un grafo de navegación multinivel.
- Más lento de construir y más memoria, pero **mayor recall** (encuentra los vecinos correctos más seguido) y mejor latencia de query.
- Se puede construir antes de tener datos (crece dinámicamente).
- **Recomendado para producción** salvo que el índice sea muy grande.

En este proyecto usaremos **HNSW** para el campo `embedding` de la entidad `Enrichment`.

### Cómo se usa en Symfony/Doctrine

`pgvector` no tiene soporte nativo en Doctrine. Se necesita declarar un tipo custom que mapea el tipo SQL `vector(n)` a un array PHP de floats. El flujo es:

```
PHP array de floats → Doctrine Type custom → SQL vector(1536) en Postgres
```

En una entidad se declara así:

```php
#[ORM\Column(type: 'vector', length: 1536)]
private array $embedding = [];
```

Y en la migración se genera:

```sql
ALTER TABLE enrichment ADD COLUMN embedding vector(1536);
CREATE INDEX ON enrichment USING hnsw (embedding vector_cosine_ops);
```

Para queries de similitud se usa SQL nativo o DQL con funciones custom:

```php
$em->createNativeQuery(
    'SELECT * FROM enrichment ORDER BY embedding <=> :query_vec LIMIT 5',
    $rsm
)->setParameter('query_vec', $queryEmbedding);
```

### Por qué en Postgres y no en una DB vectorial dedicada

Para la escala de este proyecto (miles/decenas de miles de noticias), `pgvector` es más que suficiente y tiene ventajas reales:

- **Un solo servicio menos** en Docker Compose.
- **Transacciones** — el embedding y los metadatos de la noticia se guardan atómicamente.
- **SQL estándar** — podés filtrar por fecha, source, sentiment *y* ordenar por similitud en una sola query.
- **Backup unificado** — un `pg_dump` y tenés todo.

Una DB vectorial dedicada tiene sentido a partir de decenas de millones de vectores o cuando necesitás features muy específicas (multi-tenancy vectorial, filtros complejos a escala masiva). No es el caso acá.

---

## RabbitMQ

### Qué es

RabbitMQ es un **message broker**: un proceso intermediario que recibe mensajes de un productor, los guarda en colas, y los entrega a uno o más consumidores. Es el equivalente a una oficina de correo: el que manda la carta (productor) no necesita saber quién la va a leer ni cuándo; solo la deposita, y el broker se ocupa de la entrega.

El protocolo que usa RabbitMQ se llama **AMQP** (Advanced Message Queuing Protocol).

### Conceptos clave

| Concepto | Qué es |
|---|---|
| **Producer** | Quien publica el mensaje (ej: el scheduler que encontró una noticia nueva) |
| **Exchange** | Punto de entrada. Recibe el mensaje y decide a qué colas mandarlo según reglas de routing |
| **Queue** | Buffer persistente donde esperan los mensajes hasta ser consumidos |
| **Consumer** | Quien procesa los mensajes (ej: el worker de Symfony que enriquece con IA) |
| **Binding** | Regla que conecta un exchange con una queue |
| **Routing key** | Etiqueta en el mensaje que usa el exchange para decidir el destino |

El flujo es siempre: `Producer → Exchange → Queue → Consumer`.

### Por qué no llamar directamente al worker

La alternativa "simple" sería que el scheduler llame al worker por HTTP o ejecute la lógica directamente. El problema:

- Si el worker se cae, el trabajo se pierde.
- Si llegan 50 noticias a la vez, el scheduler se bloquea esperando respuesta.
- No podés escalar consumidores sin cambiar el productor.

Con un broker en el medio:
- El mensaje **persiste en la cola** aunque el worker esté caído. Cuando vuelve, lo procesa.
- El scheduler termina en microsegundos (solo publica). El procesamiento es **asíncrono**.
- Podés levantar 5 workers en paralelo sin tocar el scheduler.

### Cómo se usa en este proyecto

El flujo de Crypto Pulse es:

```
[cron/scheduler]
     │ publica mensaje con URL/datos de la noticia
     ▼
[RabbitMQ - exchange "articles"]
     │ routing → queue "ingestion"
     ▼
[Symfony Worker - bin/console messenger:consume]
     │ consume el mensaje
     │ llama a Anthropic para enriquecer
     │ guarda en Postgres (con embedding en pgvector)
     ▼
[Mercure Hub]
     │ push SSE al frontend
     ▼
[Dashboard en vivo]
```

Symfony usa su componente **Messenger** para abstraer RabbitMQ: en el código PHP se hace `$bus->dispatch(new IngestArticleMessage(...))` y Messenger se encarga del transporte AMQP. No hay llamadas manuales a la librería de RabbitMQ.

### Por qué RabbitMQ y no Kafka o Redis Streams

Para este proyecto la elección es pragmática:

- **Kafka** es correcto para millones de mensajes/segundo y retención larga. Overkill para miles de noticias/día y agrega complejidad operativa real.
- **Redis Streams** es válido y más liviano, pero RabbitMQ tiene mejor integración nativa con **Symfony Messenger** (transport oficial, reintentos, dead-letter queues out of the box).
- **RabbitMQ** tiene UI de management (`localhost:15672`) que facilita debug en desarrollo.

La decisión está cerrada; RabbitMQ es el broker del proyecto.

---

## AMQP Routing y el bug de `default_publish_routing_key`

### El problema en una línea

Publicamos 18 mensajes al exchange `ingest`. La queue `ingest` quedó en 0. Los mensajes desaparecieron en silencio.

### Cómo funciona el routing en AMQP (tipo `direct`)

Un exchange `direct` es como un clasificador postal con reglas exactas:

```
Producer publica mensaje con routing_key="ingest"
         │
         ▼
   [Exchange "ingest" — tipo direct]
         │
         │  ¿hay algún binding cuya binding_key == routing_key del mensaje?
         │
    ─────┴─────────────────────────────────────
    SÍ: "ingest" == "ingest"        NO: descarta el mensaje (silencio)
         │
         ▼
   [Queue "ingest"]
```

El **binding** es el cable que conecta exchange con queue. Se define con una `binding_key`. Cuando llega un mensaje, el exchange compara el `routing_key` del mensaje contra la `binding_key` del binding. Si hay match exacto → entrega. Si no hay match → el mensaje se descarta **sin error, sin log, sin excepción**.

Esto es importante: **AMQP no falla ruidosamente cuando un mensaje no rutea. Lo descarta silenciosamente.** El producer recibe un "OK" del broker igualmente.

### Por qué pasó el bug

La configuración de Symfony Messenger era:

```yaml
transports:
    ingest:
        dsn: '%env(RABBITMQ_DSN)%'
        options:
            exchange:
                name: ingest
                type: direct
            queues:
                ingest:
                    binding_keys: [ingest]
```

Los `binding_keys: [ingest]` crean el binding `exchange → queue` con binding_key `"ingest"`. Eso es correcto.

El problema estaba en **qué routing_key usa Symfony al publicar**. El comportamiento de Symfony Messenger al publicar un mensaje a AMQP es:

```
routing_key = AmqpRoutingKeyStamp (si está presente en el envelope)
           ?? default_publish_routing_key (si está configurado en el exchange)
           ?? "" (string vacío — el default si no hay nada)
```

En nuestro caso, no había stamp ni `default_publish_routing_key`. Entonces Symfony publicó todos los mensajes con `routing_key = ""`.

El exchange recibió los mensajes (por eso `publish_in: 18`), buscó un binding con `binding_key == ""`, no encontró ninguno, y los descartó. La queue quedó en 0. Sin error.

### El fix

Agregar `default_publish_routing_key` al exchange:

```yaml
exchange:
    name: ingest
    type: direct
    default_publish_routing_key: ingest   # ← esto faltaba
```

Ahora Symfony publica con `routing_key = "ingest"`, que matchea `binding_key = "ingest"`, y el mensaje llega a la queue.

### Cómo se detectó

No hay ningún error en el lado del producer. El `$bus->dispatch(...)` retorna éxito. El exchange recibe el mensaje. El único indicio es que la queue permanece vacía aunque se publique.

La forma de diagnosticarlo fue comparar las métricas del exchange vs la queue en la management UI de RabbitMQ (`localhost:15672`):

- Exchange `ingest` → `publish_in: 18`, `publish_out: 0`
- Queue `ingest` → `deliver_get: 0`

`publish_out: 0` significa que el exchange no envió nada a ninguna queue (ni a otro exchange). Ahí se confirmó que el problema era de routing, no de consumo.

### Cuándo `publish_out` es 0 y cuándo no

`publish_out` en un exchange cuenta únicamente los mensajes que el exchange reenvió a **otro exchange** (exchange-to-exchange routing). NO cuenta los mensajes entregados a queues. Así que `publish_out: 0` con `publish_in: 18` no necesariamente es un bug — solo significa que no hay exchange-to-exchange routing. El indicador real es `deliver_get` en la queue.

### Regla para recordar

> En un exchange `direct` de RabbitMQ, el mensaje solo llega a la queue si `routing_key del mensaje == binding_key del binding`. Symfony Messenger usa routing key vacío por defecto. Siempre configurar `default_publish_routing_key` cuando el exchange es `direct`.

---

## Embeddings

### Qué son

Un **embedding** es una representación numérica de texto (u otro contenido) como un vector de números decimales. Por ejemplo, el texto "Bitcoin cayó 5%" podría representarse como un vector de 1024 números como `[0.12, -0.87, 0.34, ...]`.

La idea central: **textos con significados similares tienen vectores cercanos en el espacio geométrico**. "Bitcoin cayó" y "BTC baja" estarían cerca entre sí. "Bitcoin cayó" y "una receta de pasta" estarían muy lejos.

### Por qué los usamos

En el proyecto, cada noticia que pasa por el pipeline de IA recibe un embedding. Esto nos permite:

1. **Búsqueda semántica**: un usuario busca "regulación cripto" y recibe noticias relevantes aunque no contengan esas palabras exactas — porque sus vectores están cerca del vector de la query.
2. **Clustering / deduplicación**: noticias que cuentan el mismo evento tendrán vectores muy cercanos, sin importar de qué fuente vengan o cómo estén redactadas.
3. **Contexto para el LLM**: al generar resúmenes agregados ("Market Now"), podemos recuperar las noticias más relevantes de las últimas horas por similitud vectorial.

### Cómo se generan

Se le envía el texto a un **modelo de embeddings** (un modelo de ML especializado, diferente al modelo de chat) y éste devuelve el vector. En este proyecto usamos **Voyage AI** (el proveedor de embeddings recomendado por Anthropic) a través de la interfaz `EmbeddingProvider`. El modelo `voyage-3` produce vectores de **1024 dimensiones**.

### Dónde se guardan

Los vectores se guardan en la columna `embedding` de la tabla `enrichment` usando el tipo de dato `vector(1024)` de **pgvector** (extensión de PostgreSQL). Esto permite hacer búsquedas de similitud directamente con SQL.

---

## Búsqueda por similitud vectorial (kNN)

### El problema

Una búsqueda de texto tradicional busca coincidencias exactas de palabras (LIKE, full-text search). No entiende que "ETF de Bitcoin" y "fondo indexado de BTC" hablan de lo mismo.

### La solución: kNN

**kNN** (k-Nearest Neighbors, k vecinos más cercanos) es el algoritmo que responde la pregunta: "dado un vector de query, ¿cuáles son los N vectores más cercanos en mi base de datos?"

El proceso en el proyecto es:
1. El usuario escribe una query: `"regulación cripto en Europa"`
2. Se le calcula el embedding a esa query (el mismo modelo que usamos para las noticias)
3. Se buscan los N embeddings de noticias más cercanos en la DB
4. Se devuelven esas noticias como resultado

### Métrica de distancia: similitud coseno

Hay varias formas de medir "cercanía" entre vectores. Usamos **similitud coseno**, que mide el ángulo entre dos vectores (no su magnitud). Es la más usada para texto porque captura "dirección semántica" independientemente del largo del texto.

En pgvector, el operador es `<=>` (distancia coseno). Menor distancia = mayor similitud.

```sql
-- Las 5 noticias más similares a un embedding de query
SELECT * FROM enrichment
ORDER BY embedding <=> '[0.12, -0.87, ...]'
LIMIT 5;
```

---

## Índice HNSW

### El problema de performance

Sin índice, una búsqueda kNN es un **full scan**: compara el vector de query contra TODOS los vectores de la tabla. Con 10.000 noticias es manejable. Con 1.000.000 es inaceptablemente lento.

### HNSW: Hierarchical Navigable Small World

**HNSW** es un algoritmo de indexación aproximada (ANN — Approximate Nearest Neighbor). Construye una estructura de grafo jerárquica que permite encontrar los vecinos más cercanos en tiempo **logarítmico** en lugar de lineal, con una pequeña pérdida de precisión (configurable).

```
Sin índice:  O(n) — escanea todos los vectores
Con HNSW:   O(log n) — navega el grafo
```

La "pérdida de precisión" es que HNSW devuelve los vecinos *aproximadamente* más cercanos, no los *exactamente* más cercanos. En la práctica, con los parámetros por defecto, la precisión (recall) es >95%, lo que es más que suficiente para búsqueda semántica.

### Cómo se crea en el proyecto

```sql
CREATE INDEX hnsw_enrichment_embedding
ON enrichment USING hnsw (embedding vector_cosine_ops)
WHERE embedding IS NOT NULL;
```

- `USING hnsw`: tipo de índice
- `vector_cosine_ops`: operaciones de distancia coseno (coincide con el operador `<=>` que usamos en las queries)
- `WHERE embedding IS NOT NULL`: índice parcial — solo indexa filas que ya tienen embedding calculado

**Nota importante**: Doctrine ORM no sabe administrar índices HNSW (es específico de pgvector). Por eso el índice vive en una migración Doctrine y el validador `doctrine:schema:validate` se corre con `--skip-sync`.

---

## Content Hash y deduplicación

### El problema

El scheduler corre cada 5 minutos y fetchea los mismos feeds RSS. Un artículo publicado a las 10:00 va a aparecer en el fetch de las 10:00, 10:05, 10:10... Si no hay protección, se insertaría decenas de veces y se enriquecería con IA decenas de veces (costo innecesario).

### La solución: hash de la URL

Cada artículo lleva un **contentHash**: el SHA-256 de su URL. La URL de un artículo es permanente y única — es el identificador natural de una pieza de contenido en la web.

```php
$contentHash = hash('sha256', $url); // 64 chars hex
```

La columna `content_hash` en `news_item` tiene un índice UNIQUE. Si intentamos insertar un artículo ya existente, la DB lanza una `UniqueConstraintViolationException`. El handler de ingesta atrapa esa excepción y descarta el mensaje silenciosamente — comportamiento correcto.

### Por qué SHA-256 y no simplemente la URL

- La URL puede tener hasta 2048 chars — ineficiente como clave única
- SHA-256 siempre produce 64 chars hexadecimales — tamaño fijo, índice eficiente
- Collision probability negligible para URLs

---

## Pipeline State Machine (NewsItemStatus)

### Qué es

El campo `status` de `NewsItem` es una **máquina de estados** que representa en qué etapa del pipeline está cada noticia:

```
pending → enriched
pending → failed
```

| Estado | Significado |
|--------|-------------|
| `pending` | Recién ingresada, esperando ser procesada por el worker de enriquecimiento |
| `enriched` | Procesada por IA: tiene resumen, sentiment, tickers, embedding |
| `failed` | El enriquecimiento falló después de varios reintentos (fue al DLX) |

### Por qué importa

1. **Idempotencia**: antes de enriquecer, el handler verifica que `status == pending`. Si es `enriched` o `failed`, no llama a la API de IA. Esto evita costos duplicados si un mensaje se reencola o se reprocesa.
2. **Observabilidad**: un `SELECT COUNT(*) GROUP BY status` te dice instantáneamente cuántas noticias están esperando enriquecimiento, cuántas están listas y cuántas fallaron.
3. **Filtros del dashboard**: el front puede pedir solo noticias `enriched` para mostrar.

## Foundry + Doctrine Fixtures — seeding layer

**Qué es:** capa de testing post-deploy para poblar bases de datos en staging, con datos representativos pero falsos. Equivalente Symfony al par `seeders + factories` de Laravel.

### Stack

| Componente | Rol | Equivalente Laravel |
|---|---|---|
| `doctrine/doctrine-fixtures-bundle` | Runner: `bin/console doctrine:fixtures:load` | `php artisan db:seed` |
| `zenstruck/foundry` | Factories tipadas con estados y relaciones fluidas | `HasFactory` / Faker integrado |
| `fakerphp/faker` | Generador de datos falsos (viene con Foundry) | `Faker` |

### Cómo funciona

```
AppFixtures (FixtureGroupInterface)
  └── grupos: ['staging', 'dev']
       └── llama factories:  MemberFactory::createMany(15)
                             ProjectFactory::createMany(5)
```

`AppFixtures` implementa `FixtureGroupInterface` → permite segmentar con `--group=staging` (QA/devs) vs `--group=dev` (desarrollo local) sin peligro de correr datos de prueba en prod.

### Guard de producción — target Docker `frankenphp_staging`

Las dependencias de seeding son `require-dev`. La imagen prod se compila con `--no-dev`, así que **el comando `doctrine:fixtures:load` no existe en prod**. Es una garantía estructural, no una convención:

```dockerfile
# Hereda de prod (no dev): mantiene representatividad del entorno
FROM frankenphp_prod AS frankenphp_staging
RUN composer install ...   # re-instala incluyendo dev-deps
```

Nunca hereda de `frankenphp_dev` — staging debe ser prod + tooling de seeding, no dev + tooling de seeding. Si diverge de prod, deja de testear lo que realmente corre.

### Uso (en staging)

> ⚠️ **`fixtures:load` PURGA la base antes de cargar** (DELETE/TRUNCATE de todas las
> tablas, salvo `--append`). Correr SOLO contra una DB de staging dedicada, **nunca**
> contra la DB de una app productiva en infra compartida. El guard de la imagen
> `--no-dev` no protege esto. Ver Epic E, "Deuda crítica": staging debe ser una app
> aparte a nivel infra, con su propia DB.

```bash
# 1. Construir imagen staging
docker compose -f docker-compose.yml -f docker-compose.prod.yml \
  build --target frankenphp_staging backend

# 2. Cargar fixtures (contra la DB de STAGING, no la de prod)
docker exec <app>-staging-backend-1 bin/console doctrine:fixtures:load \
  --group=staging --no-interaction
```

### Cómo extender en un fork

1. Crear factories con `bin/console make:factory` (o a mano en `src/Factory/`).
2. Agregar las llamadas en `AppFixtures::load()` o en `AppStory::build()`.
3. `AppStory` sirve para escenarios nombrados y puede llamarse desde fixtures: `AppStory::load()`.

Ver `src/DataFixtures/AppFixtures.php` y `src/Story/AppStory.php` para el esqueleto con comentarios.

## El sync Oliva → forks (por qué es pull, no push)

Intuición correcta de entrada: **no se fuerza nada hacia los forks, y Oliva no sabe que
existen.** No hay listener, no hay webhook, no hay daemon, no hay registro de forks. Todo
el movimiento lo inicia el fork. El nombre "sync" es lo que engaña: suena bidireccional y
automático, y es ninguna de las dos.

### Las 3 piezas

| Pieza | Dónde vive | Qué hace |
|---|---|---|
| Remote `oliva-upstream` | **en el fork** (`.git/config`) | el único vínculo: apunta al repo de Oliva. Oliva solo tiene `origin` = sí misma |
| `OLIVA_VERSION` | archivo en el árbol del fork | marca con qué versión de Oliva está el checkout. Viaja en el merge, así que se actualiza solo |
| `docs/oliva/UPGRADING.md` | archivo, baja con el código | el canal de mensajes de Oliva al fork (ver abajo) |

Git **no tiene** push hacia abajo: un fork es un repo aparte y Oliva no tiene credenciales
ni permiso para escribirle. Técnicamente no podría forzar nada aunque quisiera.

### Cómo "se entera" el fork: polling, no notificación

`sync.sh check` (corrido **desde el fork**) hace:

1. `git fetch oliva-upstream main` — el fork va a buscar. Oliva nunca avisa.
2. `git rev-list --count HEAD..oliva-upstream/main` — ¿cuántos commits atrás estoy?
3. Compara su `OLIVA_VERSION` contra el de upstream (`git show oliva-upstream/main:OLIVA_VERSION`).
4. Imprime las secciones de `UPGRADING.md` **más nuevas que su versión local**.

O sea: el fork se entera **cuando alguien pregunta**. Lo que hace que la pregunta se haga
sola no es tecnología, es un hábito escrito en `AGENTS.md`: `sync.sh check` está en los
chequeos de inicio de sesión. Eso es todo el "listener" que hay — un humano (o su agente)
corriendo un comando al abrir la sesión.

### Cómo se traen los cambios: un merge común

`sync.sh start` = crear rama `chore/oliva-sync-<versión>` + `git merge oliva-upstream/main`.
Un merge de toda la vida entre dos historias con ancestro común. El fork elige cuándo, y
puede abortar. Nada se aplica sin que alguien lo corra.

### Entonces, ¿dónde está el "se fuerza"? En una convención, no en un mecanismo

Lo que da la sensación de imposición es **`scripts/oliva/owned-paths.txt`**: la lista de
archivos que "son de Oliva" (`backend/Dockerfile`, `docker-compose*.yml`, `scripts/oliva/`,
el CI…). La regla —**social, no técnica**— es que un fork no los edita. Si la respeta, esos
archivos no divergen, el merge los trae sin conflicto, y *parece* automático. La "fuerza"
es la disciplina de no tocarlos; git no la hace cumplir.

Cuando el fork **sí** los tocó, `sync.sh start` clasifica cada conflicto:

- `[OLIVA]` → es de Oliva. **No** sugiere `--theirs` a ciegas: imprime qué cambió el fork
  en ese archivo, porque el fork puede haber agregado algo que necesita (caso real:
  `bcmath` en el `Dockerfile`). La salida es: moverlo a un extension point o backportearlo
  a Oliva, y recién entonces tomar theirs.
- `[FORK]` → `agent-commits.md`/`commits.md`: log del proyecto, `--ours`.
- `[LOCK]` → los `.lock` no se resuelven a mano: `sync.sh locks` los regenera.
- `[MANUAL]` → todo lo demás: combinar a mano.

**La clasificación es una heurística por nombre de archivo, no un análisis.** `[MANUAL]` es
el cajón de "no sé": cae ahí todo lo que no está en `owned-paths.txt` ni es un log o un
lock. Puede estar mal. Caso real (sync 1.1.5): `backend/config/reference.php` salió
`[MANUAL] → combinar`, pero Oliva lo había **borrado a propósito** (destrackeo) y lo
correcto era `git rm --cached`. El script solo ve "conflicto en archivo no-owned"; no
distingue un `modify/delete` intencional de una divergencia real. Por eso el humano
resuelve.

### El canal de avisos: `UPGRADING.md` llega CON el código, no antes

Como Oliva no puede notificar, deja las notas en un archivo versionado. Consecuencia que
conviene tener clara: **el aviso viaja en el mismo fetch que los cambios.** No hay alerta
previa. Si el fork no corre `check`, no se enteró — y eso es exactamente lo que pasó con
PHP2Shell: Oliva 1.1.5 estaba parcheada y pusheada, y los dos forks siguieron corriendo
PHP 8.3.35 vulnerable hasta que alguien corrió el sync a mano.

Por eso `release.sh` se niega a publicar una versión sin su sección en `UPGRADING.md`: si
el único canal hacia los forks es ese archivo, una release sin notas es una release muda.

### Por qué NO se hizo un listener (y qué costaría)

Un push real necesitaría: un registro de forks en Oliva, credenciales de escritura a cada
repo, y CI que abra PRs. Eso invierte quién manda: hoy el fork decide y hay un humano en
el loop justo donde el script puede equivocarse (resolución de conflictos). El precio de
no tenerlo es el hueco de arriba — nadie avisa, hay que preguntar.

El punto intermedio, que no está hecho: Oliva no puede *pushear código*, pero sí podría
*avisar* (una GitHub Action en Oliva que al taggear abra un issue en cada fork, o los forks
suscritos a las releases del repo). Eso daría la notificación sin tocar el modelo pull.

---

## Worker mode de FrankenPHP

### El problema que resuelve: PHP arranca de cero en cada request

PHP clásico (FPM, CGI, mod_php, o el modo clásico de FrankenPHP) es *share-nothing*: cada
request ejecuta `public/index.php` desde cero y al terminar se tira todo. En Symfony eso es,
por request: cargar el autoloader de composer, construir el `Kernel`, levantar el container
de servicios (desde caché, pero igual hay que instanciarlo), abrir la conexión a la DB,
atender el request, y destruir todo. OPcache ahorra la *compilación* del código, no este
*boot*: la app se reconstruye en memoria cada vez.

```
Clásico:   request → [boot kernel → container → conexión DB → handle → teardown]  (×N)
Worker:    arranque → [boot kernel → container → conexión DB]  (1 vez)
           request  → [handle → reset]  (×N, sobre la app ya caliente)
```

### Qué hace el worker mode

FrankenPHP arranca un pool de procesos/hilos PHP que **cargan la app una sola vez** y se
quedan vivos en un loop esperando requests (`frankenphp_handle_request()`). Con Symfony, el
loop lo pone `runtime/frankenphp-symfony` (el `APP_RUNTIME` de `worker.Caddyfile`): bootea
el kernel una vez y, por cada request, lo despacha y después llama a `terminate()` + resetea
los servicios marcados como reseteables (`ResetInterface`, el `services_resetter` de Symfony:
el EntityManager de Doctrine, loggers con buffer, etc.). Por defecto FrankenPHP levanta
~2 workers por CPU (configurable con `num` en la directiva `worker`).

### Beneficios

- **Latencia:** el boot de la app sale del camino de cada request. Es el grueso del tiempo
  en endpoints livianos (un `/health`, un GET de API simple), donde la lógica de negocio es
  poca y el boot es casi todo.
- **Throughput y CPU:** el mismo hardware atiende más requests porque no recalcula lo mismo
  N veces. En un VPS chico con varias apps (el caso de Oliva) es CPU que queda libre.
- **Conexiones persistentes:** la conexión a Postgres (y a RabbitMQ, Redis…) se abre una vez
  por worker y se reusa, en vez de un handshake TCP + auth por request.
- **Estado caliente en memoria:** caches en memoria del proceso, objetos ya construidos,
  config parseada: todo sobrevive entre requests.

### Costos y riesgos (la contracara de "sobrevive entre requests")

- **Fuga de estado entre requests.** Lo que hace rápido al worker es lo mismo que lo hace
  peligroso: si un servicio guarda algo del request A (una propiedad, una variable
  `static`, un singleton casero) y no se resetea, el request B lo ve. Puede ser un bug
  (datos del usuario anterior) o un CVE: el CVE-2026-109619 de PHP2Shell y la
  GHSA-4gfw-9v29-gp9h de FrankenPHP 1.13.2 son exactamente esa clase (estado de un request
  reusado en el siguiente, fragmentos del input de otro cliente vía `error_get_last()`).
  Regla: servicios sin estado, o con estado que implemente `ResetInterface`.
- **Memory leaks acumulativos.** En clásico, un leak muere con el request; en worker crece
  hasta que el proceso se recicla. Mitigación: reiniciar el worker cada N requests
  (`FRANKENPHP_LOOP_MAX` del runtime de Symfony) y vigilar memoria.
- **Conexiones que se mueren.** Una conexión de DB abierta horas puede caerse (timeout del
  server, restart de Postgres); el worker tiene que detectarlo y reconectar en vez de fallar.
- **El código no se recarga solo.** Cambiar un archivo no afecta a un worker ya booteado:
  hay que reiniciarlo. Por eso en dev conviene clásico (o worker con `watch`).
- **EntityManager cerrado.** Una excepción de Doctrine cierra el EntityManager; sin el reset
  entre requests, todos los siguientes del mismo worker fallarían.

### Cómo está (y cómo debería estar) en Oliva

- **Dev:** clásico a propósito (`ENV FRANKENPHP_CONFIG=""` en `frankenphp_dev`): hot-reload
  sin reiniciar workers.
- **Prod:** la intención es worker — `frankenphp_prod` setea
  `FRANKENPHP_CONFIG="import worker.Caddyfile"` y el `Caddyfile` lo inyecta en el bloque
  global `frankenphp { {$FRANKENPHP_CONFIG} }`.
- **⚠️ Hallazgo 2026-10-23:** en la práctica prod corría **clásico**. `backend` carga
  `env_file: .env`, y `.env.example` traía `FRANKENPHP_CONFIG=` vacío: una variable de
  `env_file` pisa el `ENV` de la imagen aunque esté vacía (es literalmente la forma que el
  template original documenta para *desactivar* el worker, `backend/docs/production.md`).
  `docker compose -f docker-compose.yml -f docker-compose.prod.yml config backend` lo
  mostraba: `FRANKENPHP_CONFIG: ""`. Silent failure: todo arranca y `/health` da ok.
- **✅ Resuelto en 1.4.3:** se quitó `FRANKENPHP_CONFIG` del `env_file` (`.env.example` + `.env`),
  así gana el valor horneado por imagen (dev=clásico, prod=worker). El opt-out a clásico pasó a ser
  deliberado: `FRANKENPHP_CONFIG=` vacío en el `environment:` de `docker-compose.prod.yml`, no en el
  `.env`. Tres guardas contra la regresión: CI (`prod-config`: el stack prod no resuelve la variable
  a vacío), `verify.sh` (`prod-worker`: la imagen prod hornea el valor) y la prueba empírica de
  levantar prod local y ver el arranque del worker en los logs. `FRANKENPHP_LOOP_MAX` (reciclado del
  worker, default 500) quedó explícito en `worker.Caddyfile`. Pendiente: E2E bajo carga real en el VPS.

### No confundir con el `worker` de Messenger

Son dos cosas que comparten nombre:

| | Worker mode de FrankenPHP | Servicio `worker` (Messenger) |
|---|---|---|
| Qué es | Modo de ejecución del **servidor HTTP** | Un **container aparte** que corre `bin/console messenger:consume` |
| Qué procesa | Requests HTTP | Mensajes de las colas de RabbitMQ |
| Dónde se configura | `FRANKENPHP_CONFIG` / `worker.Caddyfile` | `docker-compose.override.yml` (dev); falta en prod (deuda #6) |

Lo que sí comparten es el modelo: los dos son procesos PHP de larga vida, así que los dos
sufren los mismos riesgos de fuga de estado, leaks y conexiones muertas (por eso
`messenger:consume` también tiene `--limit`, `--memory-limit` y `--time-limit`).
