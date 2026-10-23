# Epic — Estandarización de la capa agéntica

> **Estado:** 📋 planificado, sin ejecutar ·
> **Versión destino:** v1.4.0 · **Origen:** sesión de análisis (Opus 5, 2026-10-23).
> **Ejecución prevista:** sesión aparte en plan mode.

Dos ejes que se entregan **juntos en un solo release** porque ambos tocan el
mismo archivo compartido (`CLAUDE.md` → `AGENTS.md`): hacerlos por separado
haría que cada fork pague dos veces el mismo conflicto.

1. **CLI ejecutable `./oliva`** — un entry point único sobre los scripts existentes.
2. **Migración a `AGENTS.md`** — docs agénticos con nombres neutrales de vendor.

---

## Problema

### Eje 1 — No hay un entry point

Hoy la interfaz de Oliva **son paths de scripts**: `scripts/oliva/deps.sh due`,
`scripts/oliva/sync.sh check`, `scripts/deploy.sh`… Hay **~80 referencias a
paths `scripts/*.sh` repartidas por los docs**.

El costo no es tipear de más. Es estructural:

> `AGENTS.md`/`CLAUDE.md` es un archivo **SHARED** — Oliva y cada fork lo editan.
> Como los docs referencian **paths**, cada vez que un script se mueve, se parte o
> se renombra, eso es un diff en un archivo compartido → **superficie de conflicto
> en todos los forks**.

Un `oliva <verbo>` estable es una **capa de indirección**: las tripas pueden
moverse libremente sin tocar una línea de los docs compartidos. Es el mismo
razonamiento que ya justifica `owned-paths.txt`.

Beneficio secundario: `oliva help` es auto-descriptivo para un humano o agente
que clona el repo por primera vez.

### Eje 2 — Los docs agénticos están atados a un vendor

`CLAUDE.md`, `claude-commands.md` y `rules-claude.md` nombran a un proveedor en
el nombre del archivo. El contenido es **agnóstico** (runbooks, convenciones,
protocolos) y cualquier agente puede honrarlo. Marcos usa Anthropic, pero quien
forkee debe poder usar la herramienta que quiera sin renombrar nada.

`AGENTS.md` es el formato abierto para esto, bajo la Agentic AI Foundation
(Linux Foundation). Lo leen de forma nativa Codex, Cursor, Gemini CLI, Jules,
Copilot coding agent, Aider, Zed, Devin, Windsurf, Junie, goose, opencode y
otros — y también Claude Code.

---

## ⚠️ El landmine que define la solución del eje 2

**Verificado contra la doc oficial de Anthropic** (`code.claude.com/docs/en/memory`),
no de memoria:

Claude Code lee `AGENTS.md` nativamente desde **v2.1.277** (sept 2026), pero:

> lee `AGENTS.md` **solo si no hay `CLAUDE.md` ni `CLAUDE.local.md` en el working
> directory *ni en ningún directorio por encima***.

**`/home/marcos/CLAUDE.md` existe y está por encima de los 5 repos.**

→ Un rename "limpio" (`git mv CLAUDE.md AGENTS.md` y nada más) hace que Claude
Code **deje de leer la guía operativa del proyecto**: encuentra el `CLAUDE.md`
de home, le alcanza, y nunca mira el `AGENTS.md` del repo. **El rename puro es
justamente el que rompe, y rompe en silencio.**

### Solución adoptada: `AGENTS.md` + stub `CLAUDE.md`

Cada repo lleva dos archivos:

- **`AGENTS.md`** — el contenido real. Lo lee cualquier agente de forma nativa.
- **`CLAUDE.md`** — una línea: `@AGENTS.md` (import de Claude Code).

Es el patrón que la doc de Anthropic recomienda explícitamente para "compartir
un solo archivo con otras herramientas". Funciona con cualquier versión,
cualquier config y cualquier anidamiento de directorios.

**Alternativas descartadas y por qué:**

| Alternativa | Por qué no |
|---|---|
| Symlink `ln -s AGENTS.md CLAUDE.md` | **No es Windows-safe:** git lo checkoutea como texto plano salvo `core.symlinks`, dejando al clon con un `CLAUDE.md` de una línea en lugar de las instrucciones. Además Edit/Write se niegan a escribir a través de un symlink. |
| Renombrar también `~/CLAUDE.md` | Frágil: cualquier `CLAUDE.local.md` que aparezca después vuelve a apagar todo, en silencio. |
| Setting `instructionFiles: claude-md-and-agents-md` | Contradice el claim del propio README (*"None of this lives in a personal config"*): Oliva dependería de la config de la máquina de Marcos para que sus reglas carguen. |

> **Punto honesto:** el stub *es* un archivo vendor-specific. La neutralidad
> total cuesta robustez acá. Esto es el 95%: respeta a quien use otra
> herramienta, sin romper el setup existente.

**Ganancia de ownership:** el stub nunca cambia → se declara **OLIVA-owned** en
`owned-paths.txt`. La superficie de conflicto compartida queda solo en
`AGENTS.md`, igual que hoy. No empeora nada y el stub es inerte para siempre.

---

## Decisiones tomadas (no re-litigar en la ejecución)

| # | Decisión | Razón |
|---|---|---|
| 1 | CLI con alcance completo: framework + operación + `doctor` | Es cuando más barato sale: **no hay VPS ni nada productivo**, cambiar la interfaz de deploy no puede romper nada corriendo |
| 2 | **Los comandos de operación son pass-throughs finos. CERO flags nuevos** | `deploy` es lo que más varía entre apps. En cuanto exista `oliva deploy`, el paso obvio es `--cron --shared-infra`… que es **exactamente el sistema de flags que el roadmap item 3 difiere hasta tener el friction log** |
| 3 | `AGENTS.md` + stub `CLAUDE.md` con `@AGENTS.md` | Ver el landmine arriba |
| 4 | `claude-commands.md` → `agent-commands.md`, **pero los triggers siguen siendo `claude <x>`** | Es solo una frase-gatillo documentada, no una dependencia del vendor; cualquier agente la honra. Marcos no cambia su costumbre |
| 5 | `agent-commands.md` declara el prefijo **una sola vez arriba** | `agent-commands.md` queda SHARED: un fork ajeno que quiera otro prefijo cambia **una línea** en vez de diez, y el conflicto queda acotado a esa línea |
| 6 | **No renombrar `scripts/oliva/*.sh`** | ~80 referencias en docs. El CLI los envuelve; los docs migran de a poco. Cero breakage |
| 7 | Un solo release **1.4.0** con los dos ejes | Ambos tocan el archivo SHARED: un solo merge doloroso por fork en vez de dos |

---

## Diseño del CLI

Archivo **`./oliva`** en la raíz del repo, ejecutable, **NO en el `PATH`**.

> **Por qué no global:** los scripts son relativos al checkout. Un `oliva`
> global tendría que encontrar el repo igual, y driftearía de la versión del
> checkout — exactamente el problema que todo el sistema de sync existe para
> evitar.

### Mapa de comandos (1:1 con lo que ya existe)

| Comando | Envuelve |
|---|---|
| `oliva deps <due\|report\|update\|audit\|scan-images>` | `scripts/oliva/deps.sh` |
| `oliva sync <check\|start\|locks\|verify>` | `scripts/oliva/sync.sh` |
| `oliva verify` | `scripts/oliva/verify.sh` |
| `oliva release X.Y.Z` | `scripts/oliva/release.sh` |
| `oliva deploy` | `scripts/deploy.sh` |
| `oliva deploy-staging` | `scripts/deploy-staging.sh` |
| `oliva down` | `scripts/down.sh` |
| `oliva down-staging` | `scripts/down-staging.sh` |
| `oliva doctor` | **nuevo** — ver abajo |
| `oliva version` | imprime `OLIVA_VERSION` |
| `oliva help` (y sin args) | ayuda |

Nombres **literales 1:1**, sin inventar agrupaciones (`oliva staging up` sería
más lindo pero inventa interfaz — difierelo al friction log).

### Guardrails de implementación

- **Dispatcher puro.** Toda la lógica queda en los scripts. Si el CLI empieza a
  crecer (parseo de flags, colores, completion), se volvió un proyecto aparte.
- **`exec` al script**, para que argumentos, stdin/stdout y exit codes pasen
  verbatim. Un `oliva verify` que se come el exit code rompe el CI y `release.sh`.
- Los scripts siguen siendo invocables directo por su path. El CLI **agrega**, no
  reemplaza.

### `oliva doctor` — el único comportamiento nuevo

Colapsa los 7 comandos de "Chequeos de sanidad (inicio de sesión)" en una
llamada idéntica en todo fork. `AGENTS.md` pasa de un bloque de 7 comandos que
el agente debe acordarse de correr, a una línea.

Composición (todo **read-only**, nada muta estado):

1. `git branch --show-current`
2. `git status -s`
3. `git log --oneline -3`
4. `docker compose ps`
5. `docker compose exec backend bin/console doctrine:migrations:status`
6. `scripts/oliva/deps.sh due`
7. `scripts/oliva/sync.sh check` — **solo si existe el remote `oliva-upstream`**

**Requisitos de robustez:**

- ⚠️ **Trampa de `set -e` — leer antes de escribir una línea.** Los scripts de
  la casa usan `set -euo pipefail`. Copiar ese header tal cual hace que `doctor`
  **aborte en el paso 4 si Docker está apagado** — justo el escenario donde más
  se lo necesita. `doctor` es un diagnóstico: **ningún paso puede matarlo.**
  Cada paso corre aislado y captura su resultado:

  ```bash
  step() {                      # step <etiqueta> <comando...>
    local label="$1"; shift
    echo; echo "── $label ──"
    if "$@"; then return 0; else
      echo "   (no disponible: salió $?)"   # informa y sigue
      return 0
    fi
  }
  ```

  Alternativa equivalente: dejar `set -euo pipefail` y cerrar **cada** invocación
  con `|| true`. Lo que no es aceptable es un `doctor` que corta en el primer
  problema.
- **Paso 7 condicional.** En Oliva no hay `oliva-upstream` → se omite con una
  nota, no es un error. Detectar con
  `git remote get-url oliva-upstream >/dev/null 2>&1`.
- **Exit code:** `0` siempre que haya podido correr los chequeos. `doctor`
  informa, no falla el build.
- **Gate de la fase:** probar `doctor` **con Docker abajo** (`./scripts/down.sh`
  o deteniendo el daemon) y confirmar que llega hasta el último paso. Si no se
  prueba apagado, no está probado.

---

## Plan de ejecución

Orden deliberado: **el CLI primero y verificado**, porque el eje 2 va a
referenciarlo desde los docs. Hacerlo al revés obliga a escribir los docs dos veces.

### Fase 1 — CLI (sin tocar docs agénticos)

1. Crear `./oliva` con el dispatcher y `help`. `chmod +x` y confirmar que el
   **bit de ejecución queda en git** (`git ls-files -s oliva` → modo `100755`).
2. Implementar `oliva doctor` con los requisitos de robustez de arriba.
3. Agregar `oliva` a `scripts/oliva/owned-paths.txt` (es del framework).
   **Verificado:** `is_owned()` (`scripts/oliva/sync.sh:41`) hace match **exacto**
   para entradas sin barra final (`[[ "$f" == "$p" ]]`), así que la línea `oliva`
   cubre el archivo y nada más — no hay colisión por prefijo.
   El archivo se llama `oliva` **también en los forks** (es el CLI del
   framework, no de la app): no renombrarlo por fork.
4. **Gate:** cada comando produce output idéntico a su script directo.
   Probar como mínimo: `oliva help`, `oliva version`, `oliva deps due`,
   `oliva doctor`, y que `oliva verify` propaga el exit code
   (`./oliva verify; echo $?` vs `scripts/oliva/verify.sh; echo $?`).
5. Commit.

### Fase 2 — Migración a AGENTS.md

6. `git mv CLAUDE.md AGENTS.md` y `git mv claude-commands.md agent-commands.md`
   (**`git mv`, no `mv` + `add`** — hace falta que git detecte el rename para
   que el merge en los forks sea limpio).
7. Crear `CLAUDE.md` nuevo: la **primera línea es `@AGENTS.md` sola**, sin
   backticks y sin code fence (el parser de imports saltea code spans y bloques
   de código; adentro de un fence el import no se expande). Debajo, un
   comentario corto: el contenido vive en `AGENTS.md`, este archivo no se edita.

   > **Verificado (2026-10-23):** el `CLAUDE.md` de Oliva y los de ambos forks
   > tienen **cero** caracteres `@`, así que al pasar a `AGENTS.md` **no hay
   > riesgo de que un token se parsee como import accidental**. No hace falta
   > auditar el contenido por esto.
8. Renombrar `rules-claude.md` → `AGENTS.local.md` y actualizar `.gitignore`.
   Sigue siendo gitignored y de lectura explícita (hoy tampoco se auto-carga:
   se lee porque la convención lo ordena, así que **no hay regresión de
   mecanismo**, solo cambia el nombre).
9. En `agent-commands.md`: agregar arriba la nota de prefijo configurable
   (decisión 5). Los triggers siguen siendo `claude <x>`.
10. Actualizar referencias cruzadas dentro de Oliva:
    - `README.md` (líneas ~37 y ~357)
    - `scripts/oliva/owned-paths.txt` → nota SHARED: `AGENTS.md`,
      `agent-commands.md`; y `CLAUDE.md` (stub) pasa a la lista **OLIVA-owned**
    - `scripts/oliva/sync.sh` línea ~141 (mensaje de drift menciona `CLAUDE.md`)
    - `docs/oliva/actualizaciones.md` (líneas ~33, ~111, ~132, ~139)
    - `docs/qa-y-staging.md` (~5), `docs/concepts.md` (~5, ~350)
    - `scripts/deploy.sh` (~4, ~57)
    - `docs/roadmap/epics/E-seeding-layer.md` (~52, ~58, ~87)
    - **No tocar `agent-commits.md`**: es un registro histórico, los nombres
      viejos eran correctos cuando se escribieron.
11. En `AGENTS.md`: reemplazar el bloque de 7 comandos de "Chequeos de sanidad"
    por `./oliva doctor`, y migrar las referencias a scripts al CLI donde aplique.

12. **Gate de completitud del barrido.** La lista del paso 10 es una guía, no una
    garantía — no confiar en haberlas encontrado todas a ojo. Correr:

    ```bash
    grep -rn --exclude-dir=.git -E 'CLAUDE\.md|claude-commands|rules-claude' .
    ```

    **Todo hit que quede tiene que estar en uno de estos cuatro archivos**, y en
    todos los casos es legítimo:

    | Archivo | Por qué es legítimo |
    |---|---|
    | `agent-commits.md` | Registro histórico: los nombres viejos eran correctos cuando se escribieron |
    | `docs/oliva/UPGRADING.md` | Entradas históricas de versiones previas **+** las instrucciones de `git mv` de la sección 1.4.0, que mencionan los nombres viejos a propósito |
    | `docs/roadmap/epics/E-capa-agentica.md` | Este epic documenta la migración |
    | `./CLAUDE.md` | Es el stub |

    **Un hit en cualquier otro archivo es una referencia que quedó sin migrar.**

13. **Gate de carga efectiva.** Es un fallo mudo: si el import no funciona, el
    agente simplemente no lee la guía y nadie se entera. Abrir una sesión nueva
    en el repo, correr `/context` y confirmar que **`AGENTS.md` aparece bajo
    "Memory files"**. Sin este chequeo la migración no está terminada.

14. Commit.

### Fase 3 — Release

15. Sección `## 1.4.0` en `docs/oliva/UPGRADING.md` con **acción requerida**
    explícita para cada fork (ver abajo). `release.sh` **se niega a publicar sin
    esta sección** — es el gate del framework.
16. `scripts/oliva/verify.sh` en verde.
17. `scripts/oliva/release.sh 1.4.0` + push de `main` y el tag (**el push lo
    confirma Marcos**).

### Fase 4 — Forks (sesión aparte, uno por vez)

`finanzas-ong` y `crypto-pulse`. `mario-bros` y `ao-libre-upgrade` **no son
forks de Oliva** — se migran aparte y a mano si Marcos quiere, sin `sync.sh`.

> ⚠️ **Esta fase no es mecánica como las anteriores.** Las fases 1-3 son
> ejecución con gates verificables; acá se resuelven merges sobre un archivo
> **SHARED** (`AGENTS.md`), que es criterio, no procedimiento: hay que decidir
> qué de Oliva entra y qué del fork se conserva. No apoyarse en este plan como
> si fuera un checklist — un fork por sesión, y ante duda real sobre contenido
> del fork, preguntar.

---

## Contenido obligatorio de la sección `## 1.4.0` de UPGRADING.md

Es el único canal de Oliva hacia sus forks. Sin esto, el rename produce
conflicto `rename/add` en cada fork.

> **Antes de resolver el merge**, en el fork:
> ```bash
> git mv CLAUDE.md AGENTS.md
> git mv claude-commands.md agent-commands.md
> git commit -m "chore: renombrar docs agénticos antes del sync de Oliva 1.4.0"
> ```
> Así git ve un rename **en ambos lados** y mergea el contenido normalmente, en
> vez de tratarlo como un archivo borrado + uno nuevo.
>
> **Después del merge:**
> - `mv rules-claude.md AGENTS.local.md` (está gitignored → es un `mv` común, no
>   viene en el merge y no genera conflicto).
> - Verificar en la sesión siguiente que `CLAUDE.md` aparece bajo **Memory
>   files** al correr `/context`.

---

## Riesgos y cómo se cubren

| Riesgo | Cobertura |
|---|---|
| **El rename hace que el agente no lea nada, en silencio** | El stub `CLAUDE.md`. Verificación explícita con `/context` → `AGENTS.md` debe aparecer bajo Memory files. Es un fallo mudo: si no se chequea, no se nota |
| Conflicto `rename/add` en cada fork | El `git mv` previo, ordenado en UPGRADING.md |
| El CLI se come un exit code → rompe CI / `release.sh` | `exec` al script + gate 4 comparando `$?` |
| Scope creep del CLI hacia flags de deploy | Decisión 2, escrita acá y a repetir en el roadmap |
| `oliva doctor` aborta si Docker está apagado | Requisito de degradación suave |
| Las memorias de los 5 proyectos referencian los nombres viejos | **Fuera del alcance de este epic.** Se actualizan al cierre de cada sesión que toque cada repo |
| `/home/marcos/CLAUDE.md` es la *spec* de `claude new project` y quedaría desactualizada | **Fuera del repo, pero obligatorio.** Ver abajo |

---

## Fuera del repo, pero parte del trabajo

`/home/marcos/CLAUDE.md` define la convención que usa `claude new project`.
Después del release hay que actualizarlo para que **un proyecto nuevo nazca ya
con la convención correcta**: tabla de archivos (`AGENTS.md` + stub `CLAUDE.md`,
`agent-commands.md`, `AGENTS.local.md`), el paso de bootstrap y la regla
estándar de `rules-claude.md` renombrada.

**Ese archivo se queda como `CLAUDE.md`** (decisión 3: no se renombra el de
home). Es personal, no se versiona en ningún repo y renombrarlo no aporta
neutralidad a nadie.

---

## Lo que este epic NO hace

- **No renombra `scripts/oliva/*.sh`** (decisión 6).
- **No agrega flags a `deploy`** (decisión 2) — espera al friction log del
  roadmap item 1.
- **No genera `.claude/commands/`** desde `agent-commands.md`. Sería la versión
  "de verdad" de los comandos de chat, pero es vendor-specific y es
  over-engineering hoy. Queda anotado como idea, no como pendiente.
- **No toca `~/CLAUDE.md`** más allá de actualizar su contenido (no lo renombra).
- **No pone `oliva` en el `PATH`.**
