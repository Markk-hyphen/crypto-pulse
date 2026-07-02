# Claude Commands

Comandos que el usuario puede escribir en el chat para activar protocolos específicos.

---

## `claude reiniciar [x=60]`

**Qué hace:** Si el contexto de la conversación está por encima de `x`% de su límite, guarda todo lo necesario para un reinicio exitoso y avisa que se puede abrir una nueva sesión.

**Cuándo usarlo:** Antes de empezar una tarea larga, o si la conversación se siente lenta o degradada.

**Protocolo que ejecuta el agente:**

1. **Estimar uso de contexto.** El agente no puede medirlo con precisión; estima en base a la longitud de la conversación y lo declara explícitamente.

2. **Si está por debajo del umbral:** informar el porcentaje estimado y continuar sin hacer nada más.

3. **Si está por encima del umbral:**
   a. Verificar que no haya código sin commitear (`git status -s`). Si hay trabajo pendiente, commitearlo primero.
   b. Verificar que `agent-commits.md` esté al día con el último commit (si el proyecto lo usa).
   c. Actualizar los archivos de memoria en `/home/marcos/.claude/projects/-home-marcos-app/memory/` con el estado actual del proyecto: fase en curso, qué está hecho, qué sigue, decisiones abiertas.
   d. Informar al usuario: "Contexto al X%. Estado guardado — podés abrir una sesión nueva."

**Umbral por defecto:** 60%.
