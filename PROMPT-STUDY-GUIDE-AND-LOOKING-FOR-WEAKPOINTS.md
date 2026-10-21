CONTEXTO — Auditoría + documentación de estudio: Crypto Market Pulse (hitos 1.6–1.8, 2.4–2.6)

Esta sesión es de lectura y documentación, no de construcción. No modifiques código, no toques `main`, no hagas commits salvo que yo lo pida explícito.

## Qué pasó

Entre 0.0 y 1.4 construí y entendí a fondo (Messenger, retry/backoff, DLX, tagged_iterator, deduplicación por hash, idempotencia en capas, las dos cachés — Symfony Cache vs Anthropic Prompt Caching). Desde 1.5 hasta 2.1 y luego 2.4 a 2.6 se construyó en una sesión intensiva con otro modelo. Funciona. No lo entiendo en profundidad todavía.

**2.2 (búsqueda semántica con pgvector) y 2.3 (clustering por embeddings) NO se construyeron — quedaron pausados deliberadamente.** Confirmá primero el estado real del código antes de asumir nada: si hay algo parcial de 2.2/2.3, decímelo explícito y no lo documentes como completo. Si están genuinamente vacíos, simplemente saltealos del recorrido — no hay nada que auditar ahí todavía.

## La tarea

Recorré cada hito real y presente en el código: 1.5, 1.6, 1.7, 1.8, 2.1, 2.4, 2.5, 2.6 (ajustá si el runbook numera distinto a lo que encontrás). Para cada uno:

1. **Qué problema resuelve** en el pipeline real, no en abstracto.
2. **El código real que lo implementa** — citá archivos y funciones concretas del repo, no expliques con pseudocódigo genérico de Symfony.
3. **Las decisiones de diseño que tomó el otro modelo** donde el runbook dejaba margen (ej: heurística exacta de impact score en 2.5, cómo se arma "Market Now" en 2.4, criterios de filtros en 2.6). Explicá el tradeoff de cada una — no las des por buenas sin mirarlas.
4. **Conexión explícita** con lo que ya domino (Messenger, idempotencia, caché) vs. lo que es genuinamente nuevo — marcá la frontera con claridad, no des nada por sabido salvo lo listado arriba.
5. **Un checkpoint práctico** por hito: algo que pueda correr yo mismo (una query SQL, un curl, un comando de consola) para verificar que entendí, no una pregunta retórica.

## Auditoría en paralelo (no solo docencia)

Mientras recorrés el código, cruzalo contra:
- **§3.7 del runbook** (controles de costo obligatorios: idempotencia, caché, prompt caching, límite de gasto, métrica de costo) — confirmá que sobrevivieron intactos a esta cantidad de hitos de construcción rápida, no asumas que sí.
- **§7 anti-scope** — flageá cualquier cosa que se haya colado fuera de scope (knowledge graphs, auth compleja, SPA, k8s, etc.).
- **§12 checklist maestro** — corregí cualquier casillero que ya no refleje el estado real, incluyendo marcar 2.2/2.3 correctamente como pendientes.

Si encontrás algo sobre-construido, un atajo, o una decisión que no se sostiene bien, decilo directo. Esto es auditoría, no un tour de cortesía.

## Sobre 2.2/2.3 pendientes

No los documentes ni los expliques en profundidad — no hay código que auditar. Simplemente dejá registrado en el entregable, con la misma claridad que el resto, que quedan como bloqueante explícito antes de v3, y que requieren estudio de pgvector/HNSW (índice, `vector_cosine_ops`, tuning, degradación con inserciones incrementales) antes de construirse — no un repaso de código ya hecho, porque no existe.

## Entregable

Uno o pocos documentos markdown en el repo (proponé vos la ubicación, consistente con dónde vive el runbook y el CLAUDE.md), organizados por hito o por tema, pensados para releer, estudiar, entender integralmente el codigo y el sistema  y usar como referencia — no para leer una sola vez en el chat.

Cerrá con una sección explícita: **"Qué sigue sin cerrarse"** — el estado real de 2.2/2.3 como pendiente de estudio previo a construcción, más cualquier otro gap que encuentres en el recorrido de 1.5–2.6.

## Reglas

Ante ambigüedad sobre qué hace un fragmento de código, decímelo — no inventes una explicación plausible para no interrumpir el documento.


ACA VOY A PEGAR UNA CHARLA CON CLAUDE CLI TANTO MI PARTE COMO LA SUYA. INTERPRETALA PARA SABER QUE HACER. ESTA RELACIONADO A LO ANTERIOR

YO :
ah una cosa que suelo hacer, como se avanzaron 3 hitos, 2 chicos y uno mediano (los ultimos 3). LE voy a pedir a un Opus que revise los ultimos 3 hitos hechos, que revise sus potenciales weakpoints pra no haber introducido bugs.. ahora, eso va a hacer que revise codigo de por si, entonces pensaba. Sera que conviene pedirle como dijiste vos uqe revise todo lo que se construyo hoy, de paso aprende el codigo, analiza weak points y luego de ese proceso en la misma sesion hace la guia de estudio.. osea aprovecha el contexto que ya le da buscar weak points. Tiene sentido?

CLAUDE y para vos :
Tiene sentido y es más eficiente — el review de weak points y la comprensión profunda del código no son tareas separadas, son el mismo trabajo visto desde dos ángulos. Para encontrar un bug real en 2.5 (el impact score), Opus tiene que entender qué hace la heurística, no solo leerla por arriba. Ese entendimiento es exactamente lo que necesitás para el documento de estudio. Separarlo en dos pasadas es hacerle leer el mismo código dos veces por una distinción artificial.

El único ajuste real al prompt es de orden y de honestidad en el output: que el review de weak points ocurra primero — mientras está mirando el código con ojo crítico, no de cortesía — y que lo que encuentre ahí (bugs, decisiones frágiles, supuestos que no se sostienen) se filtre hacia arriba en el documento de estudio en vez de quedar como sección aparte. Si documentás "cómo funciona el impact score" sin mencionar que tiene un peso hardcodeado sin justificar o que no maneja un caso borde, el documento te da falsa confianza — te enseña el código como si estuviera bien, cuando el review paralelo ya sabe que no lo está.

Un matiz de scope: vos le pediste el review específicamente para **2.4, 2.5, 2.6** (los últimos tres). El prompt de auditoría que armamos cubre 1.5 en adelante. Si el objetivo de hoy es cerrar la sesión con foco en lo recién construido, tiene sentido acotar el review profundo de weak points a esos tres hitos, y dejar 1.5–2.1 con el nivel de auditoría que ya definimos (más liviano, enfocado en decisiones de diseño y checkpoints, no búsqueda de bugs línea por línea). Meterle el mismo nivel de escrutinio de bug-hunting a hitos que ya vienen de sesiones anteriores es trabajo que no pediste y alarga la sesión sin necesidad.

Te dejo el ajuste puntual al prompt, no hace falta rehacerlo entero — es una sección nueva que se inserta antes de "La tarea":

```
## Prioridad de esta sesión

Los últimos 3 hitos (2.4, 2.5, 2.6) se construyeron en esta misma sesión de trabajo, sin que yo revisara el código a medida que salía. Para esos tres específicamente, además de los 5 puntos de abajo, hacé una revisión de weak points genuina antes de documentar: casos borde no manejados, supuestos frágiles, valores hardcodeados sin justificación, lugares donde el código asume que el happy path siempre ocurre. No la hagas como paso separado — mientras entendés el código para documentarlo, buscá activamente dónde podría romperse. Lo que encuentres ahí va DENTRO del documento de estudio de ese hito, no en una sección aparte — si hay una debilidad real, el documento tiene que reflejarla, no enseñar el código como si estuviera bien cuando no lo está.

Para 1.5–2.1 (sesión anterior, ya con más kilometraje), el nivel de los 5 puntos de abajo alcanza — no hace falta el mismo nivel de bug-hunting línea por línea ahí.
```

Con eso el prompt queda como uno solo, ordenado, y no le duplicás trabajo a Opus ni te devuelve un documento que enseña código con bugs como si fuera oro.
