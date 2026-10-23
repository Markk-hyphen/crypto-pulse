# Claude Commands

Comandos que el usuario puede escribir en el chat para activar protocolos específicos.

---

## `claude reiniciar [x=60] [-f]`

**Qué hace:** Si el contexto de la conversación está por encima de `x`% de su límite, guarda todo lo necesario para un reinicio exitoso y avisa que se puede abrir una nueva sesión.

**Cuándo usarlo:** Antes de empezar una tarea larga, o si la conversación se siente lenta o degradada.

**Protocolo que ejecuta el agente:**

1. **Estimar uso de contexto.** El agente no puede medirlo con precisión; estima en base a la longitud de la conversación y lo declara explícitamente.

2. **Si está por debajo del umbral:** informar el porcentaje estimado y continuar sin hacer nada más.

3. **Si está por encima del umbral:**
   a. Verificar que no haya código sin commitear (`git status -s`). Si hay trabajo pendiente, commitearlo primero.
   b. Verificar que `agent-commits.md` esté al día con el último commit (si el proyecto lo usa).
   c. Actualizar los archivos de memoria en la memoria del proyecto (`/home/marcos/.claude/projects/<ruta del repo con / → ->/memory/`, ej. `~/oliva` → `-home-marcos-oliva`) con el estado actual del proyecto: fase en curso, qué está hecho, qué sigue, decisiones abiertas.
   d. Informar al usuario: "Contexto al X%. Estado guardado — podés abrir una sesión nueva."

**Umbral por defecto:** 60%.

**Flag `-f` (force):** salta el paso 1 (la estimación de contexto) y va directo a guardar
— ejecuta 3a, 3b, 3c y 3d sin evaluar el umbral. Estimar el % es impreciso e innecesario
cuando la intención de guardar ya es explícita (ej. el usuario corta la sesión por otra
razón: se tiene que poner a trabajar, cambia de prioridad, etc.).

---

## `claude oliva deps`

**Dónde:** en Oliva. **Qué hace:** el ciclo de mantenimiento de `docs/oliva/actualizaciones.md`.

1. `scripts/oliva/deps.sh report` y mostrarle a Marcos el resumen: qué está EOL (⛔), qué saltos de imagen/major hay (⇑/↑) y CVEs.
2. `scripts/oliva/deps.sh update` (bump dentro de rangos + verify). Si falla, diagnosticar antes de seguir.
3. Proponer los saltos manuales **uno por commit** y esperar el OK de Marcos para cada uno (FrankenPHP, node, postgres, rabbitmq, majors de paquetes).
4. Al cerrar: sección nueva en `docs/oliva/UPGRADING.md`, merge local a `main`, `scripts/oliva/release.sh X.Y.Z`. El push lo confirma Marcos.

## `claude oliva sync`

**Dónde:** en un fork. **Qué hace:** trae la última versión de Oliva.

1. `scripts/oliva/sync.sh check`; si está al día, avisar y terminar.
2. `scripts/oliva/sync.sh start` y leer las notas de `UPGRADING.md` que imprime **antes** de resolver.
3. Resolver según la clasificación (`[OLIVA]` → theirs, `[LOCK]` → `sync.sh locks`, `[MANUAL]` → combinar conservando lo del fork). Ante una duda real sobre código del fork, preguntar.
4. Ejecutar los pasos de "Acción requerida" de cada versión, `git commit --no-edit`, `scripts/oliva/sync.sh verify`.
5. Si pasa: merge local a `main`. Push y deploy solo si Marcos lo pide.

