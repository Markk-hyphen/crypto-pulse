# Conceptos técnicos

Explicaciones teóricas de las tecnologías que forman parte del framework Oliva.
Este archivo es acumulativo: nunca se borra contenido, solo se agrega — ver el
protocolo de explicaciones conceptuales en `AGENTS.md`.

---

## pgvector

### Qué es

`pgvector` es una extensión de PostgreSQL que agrega un tipo de dato nativo llamado `vector` y operadores para hacer **búsqueda por similitud** entre vectores. En términos simples: te permite guardar y comparar listas de números flotantes directamente en tu base de datos Postgres existente, sin necesidad de una base de datos vectorial separada (Pinecone, Weaviate, Qdrant, etc.).

### Para qué sirve

Cuando un modelo de IA procesa un texto (un documento, un mensaje, una descripción de producto, etc.), puede generar un **embedding**: una lista de números flotantes que representa el *significado semántico* de ese texto. Dos contenidos sobre el mismo tema tienen embeddings parecidos (vectorialmente cercanos); dos contenidos sin relación tienen embeddings lejanos.

`pgvector` permite hacer consultas como:
> *"Dame los 5 registros más similares semánticamente a esta query del usuario"*

sin mover los datos fuera de Postgres. Es la base para features de **búsqueda semántica** o **RAG** (retrieval-augmented generation) en cualquier dominio.

### Cómo funciona por dentro

Un embedding es un punto en un espacio de alta dimensión (por ejemplo, 1536 dimensiones si usás `text-embedding-3-small` de OpenAI, o 1024/1536 con modelos de Voyage AI). La "distancia" entre dos puntos mide qué tan parecidos son semánticamente.

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

### Cómo se usa en Symfony/Doctrine

`pgvector` no tiene soporte nativo en Doctrine. Se necesita declarar un tipo custom que mapea el tipo SQL `vector(n)` a un array PHP de floats. El flujo es:

```
PHP array de floats → Doctrine Type custom → SQL vector(n) en Postgres
```

En una entidad se declara así:

```php
#[ORM\Column(type: 'vector', length: 1536)]
private array $embedding = [];
```

Y en la migración se genera:

```sql
ALTER TABLE mi_entidad ADD COLUMN embedding vector(1536);
CREATE INDEX ON mi_entidad USING hnsw (embedding vector_cosine_ops);
```

Para queries de similitud se usa SQL nativo o DQL con funciones custom:

```php
$em->createNativeQuery(
    'SELECT * FROM mi_entidad ORDER BY embedding <=> :query_vec LIMIT 5',
    $rsm
)->setParameter('query_vec', $queryEmbedding);
```

### Por qué en Postgres y no en una DB vectorial dedicada

Para la escala de la mayoría de las apps construidas sobre Oliva (miles/decenas de miles de registros), `pgvector` es más que suficiente y tiene ventajas reales:

- **Un solo servicio menos** en Docker Compose (la imagen `pgvector/pgvector` es un Postgres normal con la extensión compilada; si no la usás, no cambia nada).
- **Transacciones** — el embedding y los metadatos del registro se guardan atómicamente.
- **SQL estándar** — podés filtrar por cualquier columna *y* ordenar por similitud en una sola query.
- **Backup unificado** — un `pg_dump` y tenés todo.

Una DB vectorial dedicada tiene sentido a partir de decenas de millones de vectores o cuando necesitás features muy específicas (multi-tenancy vectorial, filtros complejos a escala masiva).

---

## RabbitMQ

### Qué es

RabbitMQ es un **message broker**: un proceso intermediario que recibe mensajes de un productor, los guarda en colas, y los entrega a uno o más consumidores. Es el equivalente a una oficina de correo: el que manda la carta (productor) no necesita saber quién la va a leer ni cuándo; solo la deposita, y el broker se ocupa de la entrega.

El protocolo que usa RabbitMQ se llama **AMQP** (Advanced Message Queuing Protocol).

### Conceptos clave

| Concepto | Qué es |
|---|---|
| **Producer** | Quien publica el mensaje (ej: un comando programado que detectó trabajo nuevo) |
| **Exchange** | Punto de entrada. Recibe el mensaje y decide a qué colas mandarlo según reglas de routing |
| **Queue** | Buffer persistente donde esperan los mensajes hasta ser consumidos |
| **Consumer** | Quien procesa los mensajes (ej: un worker de Symfony Messenger) |
| **Binding** | Regla que conecta un exchange con una queue |
| **Routing key** | Etiqueta en el mensaje que usa el exchange para decidir el destino |

El flujo es siempre: `Producer → Exchange → Queue → Consumer`.

### Por qué no llamar directamente al worker

La alternativa "simple" sería que el productor llame al worker por HTTP o ejecute la lógica directamente. El problema:

- Si el worker se cae, el trabajo se pierde.
- Si llegan muchos eventos a la vez, el productor se bloquea esperando respuesta.
- No podés escalar consumidores sin cambiar el productor.

Con un broker en el medio:
- El mensaje **persiste en la cola** aunque el worker esté caído. Cuando vuelve, lo procesa.
- El productor termina en microsegundos (solo publica). El procesamiento es **asíncrono**.
- Podés levantar varios workers en paralelo sin tocar el productor.

### Cómo se usa en este framework

El patrón general habilitado por Oliva es:

```
[scheduler / comando]
     │ publica un mensaje (Symfony Messenger)
     ▼
[RabbitMQ - exchange]
     │ routing → queue
     ▼
[worker - bin/console messenger:consume]
     │ consume el mensaje
     │ ejecuta la lógica de negocio
     │ persiste en Postgres (eventualmente con embedding via pgvector)
     ▼
[Mercure Hub]
     │ push SSE al frontend
     ▼
[Dashboard en vivo]
```

Symfony usa su componente **Messenger** para abstraer RabbitMQ: en el código PHP se hace `$bus->dispatch(new MiMensaje(...))` y Messenger se encarga del transporte AMQP. No hay llamadas manuales a la librería de RabbitMQ. Ver `docs/examples/` para un esqueleto de mensaje + handler + comando de polling.

### Por qué RabbitMQ y no Kafka o Redis Streams

- **Kafka** es correcto para millones de mensajes/segundo y retención larga. Overkill para la mayoría de apps y agrega complejidad operativa real.
- **Redis Streams** es válido y más liviano, pero RabbitMQ tiene mejor integración nativa con **Symfony Messenger** (transport oficial, reintentos, dead-letter queues out of the box).
- **RabbitMQ** tiene UI de management (`localhost:15672`) que facilita debug en desarrollo.

Si una app no necesita colas, el servicio `rabbitmq` (y `scheduler`/`worker`) se puede quitar de `docker-compose.yml` sin afectar al resto.

---

## AMQP Routing y el bug de `default_publish_routing_key`

### El problema en una línea

Se publicaron mensajes al exchange `ingest`. La queue `ingest` quedó en 0. Los mensajes desaparecieron en silencio.

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

### Por qué pasa el bug

Una configuración típica (e incompleta) de Symfony Messenger es:

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

El problema está en **qué routing_key usa Symfony al publicar**. El comportamiento de Symfony Messenger al publicar un mensaje a AMQP es:

```
routing_key = AmqpRoutingKeyStamp (si está presente en el envelope)
           ?? default_publish_routing_key (si está configurado en el exchange)
           ?? "" (string vacío — el default si no hay nada)
```

Si no hay stamp ni `default_publish_routing_key`, Symfony publica todos los mensajes con `routing_key = ""`.

El exchange recibe los mensajes (por eso `publish_in` sube), busca un binding con `binding_key == ""`, no encuentra ninguno, y los descarta. La queue queda en 0. Sin error.

### El fix

Agregar `default_publish_routing_key` al exchange:

```yaml
exchange:
    name: ingest
    type: direct
    default_publish_routing_key: ingest   # ← esto faltaba
```

Ahora Symfony publica con `routing_key = "ingest"`, que matchea `binding_key = "ingest"`, y el mensaje llega a la queue. Esto ya está aplicado en `backend/config/packages/messenger.yaml`.

### Cómo se detecta

No hay ningún error en el lado del producer. El `$bus->dispatch(...)` retorna éxito. El exchange recibe el mensaje. El único indicio es que la queue permanece vacía aunque se publique.

La forma de diagnosticarlo es comparar las métricas del exchange vs la queue en la management UI de RabbitMQ (`localhost:15672`):

- Exchange `ingest` → `publish_in: N`, `publish_out: 0`
- Queue `ingest` → `deliver_get: 0`

`publish_out: 0` significa que el exchange no envió nada a ninguna queue (ni a otro exchange). Ahí se confirma que el problema es de routing, no de consumo.

### Cuándo `publish_out` es 0 y cuándo no

`publish_out` en un exchange cuenta únicamente los mensajes que el exchange reenvió a **otro exchange** (exchange-to-exchange routing). NO cuenta los mensajes entregados a queues. Así que `publish_out: 0` con `publish_in: N > 0` no necesariamente es un bug — solo significa que no hay exchange-to-exchange routing. El indicador real es `deliver_get` en la queue.

### Regla para recordar

> En un exchange `direct` de RabbitMQ, el mensaje solo llega a la queue si `routing_key del mensaje == binding_key del binding`. Symfony Messenger usa routing key vacío por defecto. Siempre configurar `default_publish_routing_key` cuando el exchange es `direct`.

---

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
