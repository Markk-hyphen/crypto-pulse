# Epic E — Seeding layer (staging)

> **Estado:** ✅ completo ·
> **Versión destino:** v1.1 · **Origen:**
> necesidad surgida en finanzas-ong (poblar staging con datos representativos sin SQL crudo).

## Problema

Oliva no tenía seeding de primera clase. Poblar la base en staging requería SQL
crudo a mano o scripts ad-hoc (`seed.sh` local). Sin una capa de factories,
los forks no pueden generar datos de prueba reproducibles ni testear flujos
post-deploy de forma consistente.

## Visión

Equivalente Symfony del par `seeders + factories` de Laravel: datos falsos pero
representativos, reproducibles, segregados por grupo (`staging` / `dev`), con
**guard estructural** contra seedear producción accidentalmente.

El guard no es una convención — es estructural: la imagen prod se compila con
`--no-dev`, así que el comando `doctrine:fixtures:load` directamente no existe en
la imagen prod.

## Stack agregado

| Paquete | Rol |
|---|---|
| `zenstruck/foundry` | Factories tipadas con estados y relaciones fluidas (trae FakerPHP) |
| `doctrine/doctrine-fixtures-bundle` | Runner (`doctrine:fixtures:load --group=`) |

Ambos como `require-dev` — no entran en la imagen prod.

## Target Docker `frankenphp_staging`

Multi-stage build: `frankenphp_staging` hereda de `frankenphp_prod` (no dev).
Staging = prod + tooling de seeding. Mantiene representatividad del entorno; si
divergiera de prod, dejaría de testear lo que realmente corre.

```
frankenphp_base
  ├── frankenphp_dev   (dev)
  ├── frankenphp_prod  (producción)
  └── frankenphp_staging  ← hereda de prod, suma --dev deps
```

## Slices entregados

- [x] `composer require --dev zenstruck/foundry doctrine/doctrine-fixtures-bundle`
- [x] `AppFixtures` con grupos `staging` / `dev` y comentarios para forks
- [x] `AppStory` como punto de entrada de escenarios Foundry
- [x] Target `frankenphp_staging` en el Dockerfile
- [x] Paso opt-in en el runbook de deploy del `CLAUDE.md`
- [x] Comando documentado en `.env.example`
- [x] Sección Foundry en `docs/concepts.md`
- [x] `docker-compose.staging.yml` — overlay mínimo (image + target + env_file)
- [x] `.env.staging.example` — env template para la DB desechable de staging
- [x] `scripts/deploy-staging.sh` — deploy completo de staging en una llamada
- [x] Runbook formal de staging en `CLAUDE.md`
- [x] Modelo de infra de staging documentado (Epic E, deuda crítica resuelta)

## Deuda crítica — el modelo de infra de staging (RESUELTA 2026-06-29)

> Detectada en el checkpoint del 2026-06-27. Resuelta con Opción 1 (staging como
> app más en el VPS, DB propia desechable en el mismo Postgres compartido).

`doctrine:fixtures:load` **purga la base antes de cargar** (DELETE/TRUNCATE de
todas las tablas gestionadas, salvo `--append`). El guard estructural de la imagen
prod (`--no-dev`) no alcanzaba por sí solo: el propio paso 11 del runbook anterior
hacía buildear la imagen `frankenphp_staging` que SÍ tiene el comando, y en infra
compartida el container apuntaba al Postgres central vía el `DATABASE_URL` **de
producción**.

**Solución implementada (Opción 1 — staging como app aparte):**

- `docker-compose.staging.yml`: overlay mínimo que overridea `image` y
  `build.target` del backend/scheduler (tag `app-backend-staging:1.0`, target
  `frankenphp_staging`). Evita pisar la imagen de prod en el host.
- `.env.staging` (gitignored) + `.env.staging.example`: env de staging con el
  `DATABASE_URL` de la DB desechable. Se carga como último env_file en el overlay.
- **Project name propio** (`-p <app>-staging`): red privada propia, sin colisión
  DNS con el stack de producción.
- **DB propia** en el mismo Postgres compartido de infra:
  `provision-postgres.sh <app>_staging_db <app>_staging_user`. La purga es
  inocua — la DB de staging es desechable.
- `scripts/deploy-staging.sh`: atajo que ejecuta build + up + migraciones +
  `fixtures:load` en una sola llamada.
- Runbook formal en `CLAUDE.md` (sección "Runbook de staging").

El paso 11 del runbook de shared-infra apunta ahora al runbook de staging.

## Cómo extiende un fork

1. `bin/console make:factory` para cada entidad (o a mano en `src/Factory/`).
2. Llamar las factories en `AppFixtures::load()` o en `AppStory::build()`.
3. El target `frankenphp_staging` ya existe: solo necesita `docker compose build --target frankenphp_staging`.
4. **Antes de seedear en infra compartida:** resolver la "Deuda crítica" de arriba —
   staging necesita su propia DB, no la de producción.

## Por qué es un hito de framework

El target `frankenphp_staging` introduce **multi-stage build con herencia semántica**
en Oliva: cada stage tiene un propósito explícito (dev / prod / staging) y la imagen
de staging reutiliza prod sin divergir. Es el patrón Docker recomendado para tooling
de testing post-deploy y escala para sumar más tools (ej. API collection) sin tocar prod.
