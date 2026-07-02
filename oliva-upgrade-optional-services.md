# Oliva — Upgrade: servicios opcionales vía Compose profiles

> **Repo:** Oliva (framework base).
> **Rama sugerida:** `feature/optional-services-profiles`.
> **Qué es este doc:** especificación de un upgrade del framework. Claude CLI
> construye el cambio a partir de acá y lo mergea a `main` cuando esté probado.
> **Qué NO es:** no contiene nada de deploy ni de ninguna app concreta. El
> framework no conoce a las apps que lo forkean. El deploy de finanzas-ong vive
> en su propio repo (ver `deploy-finanzas-ong-prod-v1.md`).

> **Naturaleza:** upgrade temporal. Resuelve el caso de hoy (prender/apagar
> servicios opcionales sin borrarlos). La solución definitiva — flags en
> instalación — es v2.0 (sección 4).

---

## 1. Problema

Oliva levanta por default el stack completo: backend + frontend + database +
**rabbitmq + worker (Messenger) + mercure**. Toda app que forkea Oliva hereda
esos servicios opcionales aunque no los use.

No queremos:
- correr y mantener en prod piezas que no hacen nada (RAM idle, superficie de
  falla, ruido al razonar sobre el sistema);
- "borrar" servicios del compose por app (destructivo, no versionable, se
  re-rompe en cada fork).

Queremos una palanca limpia, por variable de entorno, que sea capacidad nativa
de Oliva y la herede cualquier fork.

---

## 2. Solución: Docker Compose profiles

Compose tiene `profiles` nativo. Un servicio **sin** `profiles` siempre se
levanta; uno **con** `profiles` solo se levanta si ese perfil está activo. No
hay que construir nada — es de la herramienta.

### Cambios en `docker-compose.yml`

```yaml
services:
  backend:        # core — sin profile, siempre arriba
    # ...
  frontend:       # core
    # ...
  database:       # core
    # ...

  rabbitmq:
    image: rabbitmq:3-management
    profiles: ["queues"]
    # ...

  worker:
    # command: messenger:consume
    profiles: ["queues"]
    # ...

  mercure:
    profiles: ["realtime"]
    # ...
```

Agrupar por perfil semántico, no por servicio:
- `queues` → rabbitmq + worker (van juntos: el worker no sirve sin broker).
- `realtime` → mercure.

### Control por variable de entorno

En `.env`:

```dotenv
# Por default, app mínima: solo core arriba.
COMPOSE_PROFILES=

# Una app que use colas y tiempo real:
# COMPOSE_PROFILES=queues,realtime
```

`docker compose up -d` con `COMPOSE_PROFILES` vacío levanta SOLO core.

---

## 3. Coherencia de variables (documentar en README)

Los profiles deciden *qué contenedores se levantan*, no las variables que la app
le pasa al backend. Si alguien activa `queues` pero no configura el DSN del
broker, el backend falla al arrancar.

Agregar al README de Oliva una tabla del estilo:

| Perfil | Servicios | Variables que hay que configurar |
|---|---|---|
| (ninguno) | backend, frontend, database | `DATABASE_URL`, `APP_SECRET`, ... |
| `queues` | + rabbitmq, worker | `MESSENGER_TRANSPORT_DSN` |
| `realtime` | + mercure | claves Mercure (`openssl rand -hex 32`) |

> Regla: si activás un perfil, configurás también sus variables. Esa coherencia
> es responsabilidad de quien forkea, no del framework.

---

## 4. Tareas para CLI

- [x] `profiles: ["queues"]` en `rabbitmq` y `worker`.
- [x] ~~`profiles: ["realtime"]` en `mercure`~~ — descartado: Mercure corre
      embebido en el backend vía el hub de Caddy (FrankenPHP), no es un
      contenedor separado. No hay nada que togglear, y separarlo iría contra
      el diseño de FrankenPHP. Ver README, sección "Always-on, not behind a
      profile".
- [x] `COMPOSE_PROFILES=` (vacío) en `.env.example`.
- [x] Tabla de perfiles ↔ variables en el README (solo `queues`, ver arriba).
- [x] Test local: `COMPOSE_PROFILES=` vacío → `docker compose up -d` levanta
      SOLO backend + frontend + database (+ scheduler, always-on). Verificado
      con `docker compose ps` — sin rabbitmq/worker.
- [x] Test local: `COMPOSE_PROFILES=queues` → aparecen rabbitmq + worker;
      al vaciar la variable y `docker compose stop`, desaparecen.
- [x] Testeo manual del usuario: `COMPOSE_PROFILES=queues` levanta rabbitmq +
      worker (healthy), worker consume `ingest`/`enrich` sin errores, sin
      tocar backend/database/frontend/scheduler ya corriendo.
- [x] Merge a `main` con el upgrade probado.

### Cambio adicional no previsto en el spec original

Para que el toggle funcione de verdad hubo que quitar `depends_on: rabbitmq`
de `backend` y `scheduler` (en `docker-compose.yml`) y del `scheduler` en
`docker-compose.override.yml`. Sin esto, Compose volvía a levantar rabbitmq
aunque el profile estuviera apagado, porque un servicio core dependía de él.
Documentado en el README ("Adding a new profile", punto 2) como regla para
perfiles futuros.

> **Scope guard:** esto son ~4 líneas `profiles:` + 1 variable + doc en README.
> Si empieza a sentirse como "construir un sistema", parar — eso ya es v2.0.

---

## 5. Hacia v2.0 (NO ahora — registro de intención del framework)

Items que son responsabilidad del framework (los de ops viven en el doc de
deploy):

- **Flags en instalación / scaffolding:** que forkear Oliva pregunte (o lea un
  manifiesto) qué servicios incluir, en vez de heredar todo y apagar con
  profiles. Los profiles de v1 son el puente, no el destino.
- **Definición de `worker` para producción:** hoy `worker` solo está en
  `docker-compose.override.yml` (dev). Falta su equivalente prod. Relevante
  cuando una app use Messenger en serio en producción.
- **Mecanismo de propagación de upgrades a forks:** hoy una app que forkeó
  Oliva no recibe automáticamente los cambios del framework (ver el doc de
  deploy, sección "port"). v2.0 debería definir cómo se sincroniza un fork con
  upstream sin parchear a mano.

> Disparador para abrir v2.0: la segunda app real lista para prod.
