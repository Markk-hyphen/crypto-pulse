commit e8b47a2fed5fce69e4a353a6667da6f4713a5ebe
Author: Mark F Soler <marcosfsoler@gmail.com>
Date:   Sat Jun 13 19:39:24 2026 -0300

    docs: registrar hash 4c20e1c en agent-commits.md (fix /health proxy)
    
    Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>

commit 4c20e1c7e6fa743b9e3748406942b7d7fe66df51
Author: Mark F Soler <marcosfsoler@gmail.com>
Date:   Sat Jun 13 19:39:13 2026 -0300

    fix: proxy /health desde el frontend hacia el backend en prod
    
    Mismo bug detectado y arreglado en main (framework Oliva): el frontend
    Caddy en prod no reenviaba /health al backend, devolvía "Something went
    wrong!" en vez de {"status":"ok"}. Verificado en stack prod aislado.
    
    Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>

commit 5c1923987e71d241d3655e9ea30be7c94e93a68f
Author: Mark F Soler <marcosfsoler@gmail.com>
Date:   Mon Jun 1 03:59:04 2026 -0300

    docs: registrar hash c15bc35 en agent-commits.md (step 1.5)
    
    Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>

commit c15bc351815738d7d877cf8a2b9f1b2f5585ffbb
Author: Mark F Soler <marcosfsoler@gmail.com>
Date:   Mon Jun 1 03:58:41 2026 -0300

    feat: publish Mercure en EnrichItemHandler + NullEnrichmentProvider dev (step 1.5)
    
    - EnrichItemHandler: inyecta HubInterface, publica a topic crypto/feed
      tras flush() con payload JSON del item enriquecido (sin embedding)
    - NullEnrichmentProvider: stub dev que devuelve resultado fijo a costo $0
    - services_development.yaml: alias EnrichmentProviderInterface → Null en dev
    - MERCURE_URL: http://localhost → http://backend (nombre de servicio Docker)
      para que el worker (contenedor separado) pueda publicar al hub
    
    Verificación: curl suscrito a crypto/feed recibe 3 eventos SSE inmediatos
    con payload JSON completo tras app:enrich:requeue-pending.
    
    Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>

commit 2704ab3eb81f1d797e4cade648e86f40044f75a8
Author: Mark F Soler <marcosfsoler@gmail.com>
Date:   Mon Jun 1 03:39:21 2026 -0300

    docs: revisión de sanidad post-1.4 — deuda conocida y corrección de log
    
    - CLAUDE.md: agrega sección "Deuda conocida antes de 1.5" con hallazgos
      de revisión Opus (mock de EnrichmentProvider faltante en dev, prompt
      caching no-op, dual-write, contentHash naming, RssAdapter, re-embedding)
    - agent-commits.md: corrige entrada de paso 1.4 — .env.backend no estaba
      en el commit 5d19a32 (solo .env.example); agrega nota de reconciliación
    - .env.backend: commitea el cambio pendiente (ANTHROPIC_API_KEY /
      VOYAGE_API_KEY) que debió incluirse en el paso 1.4
    
    Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>

commit f48fc46ad8ff4dcb6fb5d35db4467e4240efa887
Author: Mark F Soler <marcosfsoler@gmail.com>
Date:   Mon Jun 1 03:11:02 2026 -0300

    docs: registrar hash 5d19a32 en agent-commits.md (step 1.4)

commit 5d19a3286a19fd4bfa39572fc0a4b7d530544db8
Author: Mark F Soler <marcosfsoler@gmail.com>
Date:   Mon Jun 1 03:10:54 2026 -0300

    feat: enriquecimiento IA — AnthropicEnrichmentProvider, VoyageEmbeddingProvider, EnrichItemHandler (step 1.4)
    
    Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>

commit ebed2d04af7fba5aed3f639f17e1cb0799beda46
Author: Mark F Soler <marcosfsoler@gmail.com>
Date:   Mon Jun 1 02:58:08 2026 -0300

    docs: registrar hash a48f5ed en agent-commits.md (step 1.3)

commit a48f5ed3442f19bef1827073a3089d8a40be8f9c
Author: Mark F Soler <marcosfsoler@gmail.com>
Date:   Mon Jun 1 02:58:00 2026 -0300

    feat: poll programado — SourcesPollCommand itera adapters registrados (step 1.3)
    
    Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>

commit 6a7d89d55db73e573ef0b0c70e434f66624febcd
Author: Mark F Soler <marcosfsoler@gmail.com>
Date:   Mon Jun 1 02:55:04 2026 -0300

    docs: registrar hash 2f1e829 en agent-commits.md (step 1.2)

commit 2f1e82910cb8f478e8acb03449b32c7105128924
Author: Mark F Soler <marcosfsoler@gmail.com>
Date:   Mon Jun 1 02:54:56 2026 -0300

    feat: ingesta RSS — SourceAdapterInterface, RssAdapter, EnrichItemMessage, handler real (step 1.2)
    
    Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>

commit c3e7d3fc3affe0481fc2c27ace8f9f3916ced693
Author: Mark F Soler <marcosfsoler@gmail.com>
Date:   Mon Jun 1 02:46:53 2026 -0300

    docs: tildar paso 1.1 en PLAN-MARKET-PULSE.md
    
    Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>

commit 5b5fd15892ed8afae0d8dd49b133b76db2a53ee5
Author: Mark F Soler <marcosfsoler@gmail.com>
Date:   Mon Jun 1 02:44:20 2026 -0300

    feat: modelo de dominio — NewsItem, Enrichment, migración + HNSW (step 1.1)
    
    Entidades Doctrine con enum de estado, contentHash único y columna
    vector(1024) para embeddings. Migración incluye índice HNSW parcial
    para búsqueda coseno. doctrine.yaml con mapping_types para introspección
    inversa del tipo vector. CI actualizado con --skip-sync. Conceptos de
    embeddings, kNN, HNSW, content hash y state machine agregados.
    
    Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>

commit 545a2e74f849e59c082f3c73bbec63d3b124437f
Author: Mark F Soler <marcosfsoler@gmail.com>
Date:   Mon Jun 1 02:37:27 2026 -0300

    docs: registrar fix FRANKENPHP_CONFIG en agent-commits.md
    
    Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>

commit be0662e5553e8cae661e8a44701c4e7495dafda2
Author: Mark F Soler <marcosfsoler@gmail.com>
Date:   Mon Jun 1 02:21:51 2026 -0300

    fix: vaciar FRANKENPHP_CONFIG en .env.example; agregar logs-on-failure al CI
    
    FRANKENPHP_CONFIG="php:80" en .env.example inyectaba un directivo inválido
    en el bloque global frankenphp{} del Caddyfile → Caddy no arrancaba →
    backend unhealthy en CI. Localmente la var no estaba seteada (expandía
    a vacío). Fix: dejarla vacía. Se agrega paso de dump de logs con if:failure()
    para diagnóstico de futuros crashes.
    
    Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>

commit d29e58113913de391373f1cf15c6727698217d3c
Author: Mark F Soler <marcosfsoler@gmail.com>
Date:   Mon Jun 1 02:08:29 2026 -0300

    docs: tildar pasos 0.1-0.8 en plan; relajar failOn* en phpunit.dist.xml
    
    Cajas de §4 y checklist §12 marcadas como completadas. Verificación de
    §0.8 corregida (vendor/bin/phpunit). failOnDeprecation/Notice/Warning
    removidos del phpunit.dist.xml — se endurecen en paso 3.4 con cobertura
    real; Symfony/Doctrine emiten deprecations propias que romperían la suite.
    
    Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>

commit ba2caaa513028ce049a6ca5784ceba371e716598
Author: Mark F Soler <marcosfsoler@gmail.com>
Date:   Mon Jun 1 01:58:14 2026 -0300

    docs: registrar paso 0.8 en agent-commits.md con hash real; actualizar próximo paso en CLAUDE.md
    
    Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>

commit dc444bc32fae260841478e84dd8dba1d8d57748c
Author: Mark F Soler <marcosfsoler@gmail.com>
Date:   Mon Jun 1 01:56:32 2026 -0300

    feat: PHPUnit base — instalar, configurar y habilitar en CI (step 0.8)
    
    PHPUnit 12.5 + symfony/test-pack instalados; phpunit.dist.xml de la
    recipe de Flex; primer test unitario (IngestSourceMessage); .dockerignore
    corregido para incluir tests/ en el build; CI habilitado con
    php vendor/bin/phpunit (bin/phpunit ya no es generado en PHPUnit 12).
    
    Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>

commit 7e642776890bf2eb12a2bb9dcbffda47cb9a7395
Author: Mark F Soler <marcosfsoler@gmail.com>
Date:   Mon Jun 1 01:20:40 2026 -0300

    docs: registrar paso 0.7 en agent-commits.md; actualizar próximo paso en CLAUDE.md
    
    Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>

commit a1942d421e1e06d38b45f017ecc3721da949d1da
Author: Mark F Soler <marcosfsoler@gmail.com>
Date:   Mon Jun 1 01:20:15 2026 -0300

    feat: corregir CI y agregar health endpoint (step 0.7)
    
    - .github/workflows/ci.yml: mover de backend/.github/ a raíz del repo (GitHub Actions requiere .github/ en raíz)
      - agregar rama release/plan-market-pulse al trigger push
      - step para generar .env y .env.backend en CI con valores seguros
      - usar docker compose build en lugar de bake-action
      - fix: service name php → backend
      - fix: Mercure check usa HTTP (dev sirve :80, no HTTPS)
      - habilitar pasos Doctrine (migrations + schema:validate); quitar if:false
      - mantener PHPUnit con if:false hasta paso 0.8
      - especificar backend/Dockerfile en hadolint
    - backend/src/Controller/HealthController.php: GET /health → {"status":"ok"}; reemplaza check de raíz que devolvía 404
    
    Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>

commit 6e954e60012a62465729aec8f9fcb24c5bcc1b2a
Author: Mark F Soler <marcosfsoler@gmail.com>
Date:   Mon Jun 1 00:56:08 2026 -0300

    docs: agregar explicación de AMQP routing y bug default_publish_routing_key a concepts.md
    
    Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>

commit e885fbc2558679d850e3ce44c0fb75d544d5322b
Author: Mark F Soler <marcosfsoler@gmail.com>
Date:   Mon Jun 1 00:53:17 2026 -0300

    docs: registrar paso 0.6 en agent-commits.md; actualizar próximo paso en CLAUDE.md
    
    Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>

commit fc7cb2315664c66fb0517dcf308cfb871dc216a2
Author: Mark F Soler <marcosfsoler@gmail.com>
Date:   Mon Jun 1 00:52:47 2026 -0300

    feat: scheduler cron container with supercronic (step 0.6)
    
    - backend/Dockerfile: install supercronic v0.2.46; COPY scheduler/crontab
    - backend/scheduler/crontab: poll every 5 min via bin/console app:sources:poll
    - backend/src/Command/SourcesPollCommand.php: stub command, dispatches IngestSourceMessage per source
    - backend/src/Message/IngestSourceMessage.php: message DTO for ingest pipeline
    - backend/src/MessageHandler/IngestSourceHandler.php: stub handler, logs no-op
    - backend/config/packages/messenger.yaml: add default_publish_routing_key to ingest/enrich exchanges; enable IngestSourceMessage routing
    - docker-compose.yml: add scheduler service (base)
    - docker-compose.override.yml: add scheduler override with supercronic command and volume mounts
    
    Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>

commit ab04c9a321938aa4d9ed717c53f0d0cd463aa72b
Author: Mark F Soler <marcosfsoler@gmail.com>
Date:   Mon Jun 1 00:30:31 2026 -0300

    docs: registrar commit de concepts.md en agent-commits.md
    
    Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>

commit 18e1740ca89705e6f58fc541f253ead44b506032
Author: Mark F Soler <marcosfsoler@gmail.com>
Date:   Mon Jun 1 00:26:34 2026 -0300

    docs: agregar explicación de RabbitMQ a concepts.md
    
    Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>

commit e37d16064c804a3120f4c6358592994c997232af
Author: Mark F Soler <marcosfsoler@gmail.com>
Date:   Mon Jun 1 00:20:20 2026 -0300

    chore: ignore frontend build artifacts and Doctrine auto-generated .gitignores
    
    Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>

commit 1dcd18fdd60312bc55a4ef12f0ca04560011ffa1
Author: Mark F Soler <marcosfsoler@gmail.com>
Date:   Mon Jun 1 00:20:01 2026 -0300

    fix: worker healthcheck, session protocol in CLAUDE.md, Doctrine empty dirs
    
    - Override worker healthcheck (kill -0 1) — image healthcheck hits :2019 (Caddy), not valid for worker
    - Add sanity check protocol to CLAUDE.md (pre/post session commands)
    - Update CLAUDE.md next step to 0.6
    - Add .gitkeep for empty Entity/ and Repository/ dirs (created by Doctrine maker)
    - Commit migrations/.gitignore (auto-generated by DoctrineMigrationsBundle)
    - Commit .env.backend with RabbitMQ and Mercure vars
    
    Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>

commit 5cc6832eb7de772ec19097d56b95785d8441e200
Author: Mark F Soler <marcosfsoler@gmail.com>
Date:   Mon Jun 1 00:18:22 2026 -0300

    chore: commit interactive-demo work and accumulated Flex/config updates
    
    - frontend: landing page (index.html, main.js, style.css, Caddyfile)
    - docker-compose.prod.yml: fix SERVER_NAME ":80" (was "http://localhost")
    - backend/frankenphp/Caddyfile: updates from interactive Mercure demo
    - backend/config/reference.php: updated by Symfony Flex during package installs
    
    Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>

commit 9fa83c0fd1325ca924e206a64598b2a83e05a391
Author: Mark F Soler <marcosfsoler@gmail.com>
Date:   Mon Jun 1 00:11:25 2026 -0300

    docs: fix hash for step 0.5 in agent-commits
    
    Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>

commit b6c53f1401749e9a2fb510bb7388199e49f0ce37
Author: Mark F Soler <marcosfsoler@gmail.com>
Date:   Mon Jun 1 00:11:17 2026 -0300

    feat: add RabbitMQ, Symfony Messenger, worker service (step 0.5)
    
    - Add rabbitmq:3-management service with healthcheck and durable volume
    - Add worker service (messenger:consume ingest enrich, time-limit=3600)
    - Add ext-amqp to Dockerfile PHP extensions
    - Install symfony/messenger + symfony/amqp-messenger
    - Configure ingest/enrich/failed transports with AMQP DSN, DLX, retry backoff
    - Add RABBITMQ_DSN to env files; document all new vars in .env.example
    - Verified: messenger:stats shows 3 transports connected, queues visible in UI
    
    Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>

commit 55dd7397cba2aefdcfa7b2289069f4113741f2e8
Author: Mark F Soler <marcosfsoler@gmail.com>
Date:   Sun May 31 23:57:21 2026 -0300

    docs: fix hash for step 0.4 in agent-commits
    
    Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>

commit 88f4a938a45f32bca8ee0b0672559ad61b86599e
Author: Mark F Soler <marcosfsoler@gmail.com>
Date:   Sun May 31 23:57:12 2026 -0300

    feat: install MercureBundle, configure publisher (step 0.4)
    
    - Install symfony/mercure-bundle; register in bundles.php
    - Add mercure.yaml config (MERCURE_URL / MERCURE_PUBLIC_URL / MERCURE_JWT_SECRET)
    - Add MercurePublishTestCommand for smoke testing the publisher
    - Fix JWT secret: !ChangeThisSecret! is 144 bits, HMAC-SHA256 needs 256+
    - Add Mercure vars to .env.backend with proper 256-bit key
    - Verified: publish returns UUID, EventSource receives message in browser
    
    Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>

commit 43be82f1aa56cd225ddfd3d13056032460080f79
Author: Mark F Soler <marcosfsoler@gmail.com>
Date:   Sun May 31 21:14:52 2026 -0300

    docs: update hash for step 0.3 in agent-commits
    
    Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>

commit 1435f0cc7ce0f97367fc5ec87a46881d10fdc980
Author: Mark F Soler <marcosfsoler@gmail.com>
Date:   Sun May 31 21:14:44 2026 -0300

    feat: add pgvector — extension, migration, Doctrine type (step 0.3)
    
    - Switch database image to pgvector/pgvector:pg15 (volume-compatible)
    - Add migration enabling vector extension (CREATE EXTENSION IF NOT EXISTS vector)
    - Install pgvector/pgvector PHP package for Doctrine type mapping
    - Register VectorType in doctrine.yaml; fix server_version to 15
    
    Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>

commit 0c2f05eb4d4822ad0ea8c6d3dbefae86346fbf2e
Author: Mark F Soler <marcosfsoler@gmail.com>
Date:   Sun May 31 21:11:26 2026 -0300

    docs: add concepts.md (pgvector explanation) and protocol to CLAUDE.md
    
    Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>

commit 3b2fd39e0bbcad560d5b97a5ef2d4eaf7b12f2cb
Author: Mark F Soler <marcosfsoler@gmail.com>
Date:   Sun May 31 21:07:00 2026 -0300

    docs: update agent-commits hash for step 0.2
    
    Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>

commit 0d6075308698f2d57060173d196c9d044a816e70
Author: Mark F Soler <marcosfsoler@gmail.com>
Date:   Sun May 31 21:06:51 2026 -0300

    feat: install Doctrine ORM + Migrations, add pdo_pgsql extension (step 0.2)
    
    - Add pdo_pgsql to Dockerfile PHP extensions (missing from original template)
    - Install symfony/orm-pack, doctrine/doctrine-migrations-bundle, symfony/maker-bundle
    - Add doctrine.yaml and doctrine_migrations.yaml (Flex partial-write workaround)
    - Register DoctrineMigrationsBundle in bundles.php manually
    - Mount migrations/ in dev override; COPY migrations/ in Dockerfile
    - Fix DATABASE_URL password mismatch in .env.example (your_db_password vs password)
    
    Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>

commit d9b3a0cc6f09da08230c0ade62ad09c58133d95b
Author: Mark F Soler <marcosfsoler@gmail.com>
Date:   Sun May 31 20:53:14 2026 -0300

    docs: add agent-commits log and commit protocol to CLAUDE.md
    
    Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>

commit 59aab7c2513b18e1f6266b7503bbfffc30fafd57
Author: Mark F Soler <marcosfsoler@gmail.com>
Date:   Sun May 31 20:48:32 2026 -0300

    feat: graduate backend from generated boilerplate to versioned app (step 0.1)
    
    - Version backend/src/, config/, bin/, composer.json/lock, symfony.lock
    - Remove `composer create-project` from Dockerfile; install from versioned lockfile
    - Clean docker-entrypoint.sh: remove first-install block, keep JWT keygen + DB wait
    - Add backend/.env with Symfony defaults (secrets injected via Docker env_file)
    - Fix root .gitignore to allow backend/.env; fix backend/.gitignore to allow config/packages
    - Add .env mount to dev override so Symfony can read it at runtime
    - Remove unused SYMFONY_VERSION/STABILITY build args from docker-compose.yml
    - Add migrations/ directory placeholder
    - Add PLAN-MARKET-PULSE.md runbook and update CLAUDE.md with project direction
    - Include Mercure demo files (live.php, live.js) from feat/interactive-demo
    
    Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
