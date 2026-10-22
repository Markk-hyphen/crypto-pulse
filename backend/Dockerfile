#syntax=docker/dockerfile:1

# Versions
# Pinned to an exact version: the floating "1-php8.3" tag pulled 1.13.1 on a rebuild and
# its Mercure refused the existing hub config. Upgrade on purpose, then re-check Mercure.
#
# 1.13.2-php8.3.36 (2026-10-21) es un bump de SEGURIDAD, no de rutina:
#   - PHP 8.3.36 arregla PHP2Shell (CVE-2026-109618/109619, CVSS 9.2, RCE sin auth). El
#     109619 es estado de request stale que un worker reusa en el request siguiente → pega
#     de lleno en el worker mode de frankenphp_prod, no es un CVE de espectador.
#   - FrankenPHP 1.13.2 arregla además 4 vulns propias, 2 aplican acá: fuga de fragmentos
#     del input del cliente anterior vía error_get_last() en worker mode
#     (GHSA-4gfw-9v29-gp9h) y thread pool ocupable por un cliente sin auth que encola y
#     se desconecta (GHSA-fq24-r53r-xcx3). Sus upgrade notes son todas de static builds
#     (glibc 2.28, assets de macOS) → no nos tocan, usamos la imagen Docker.
# Existe `1.13.1-php8.3.36` (bump mínimo, solo PHP), pero se eligió 1.13.2 por esas 2
# vulns de worker mode. Es un patch dentro del mismo minor: sin riesgo de la regresión de
# Mercure de 1.13.0 (igual el step [mercure] de scripts/oliva/verify.sh la cubre).
# El fix NO toma efecto en procesos vivos: hay que RECREAR los containers, no reiniciar
# el servicio. scripts/deploy.sh ya hace `down` antes del `up`; el step [php-version] de
# verify.sh asserta que lo que corre coincide con este pin.
FROM dunglas/frankenphp:1.13.2-php8.3.36 AS frankenphp_upstream

# The different stages of this Dockerfile are meant to be built into separate images
# https://docs.docker.com/develop/develop-images/multistage-build/#stop-at-a-specific-build-stage
# https://docs.docker.com/compose/compose-file/#target


# Base FrankenPHP image
FROM frankenphp_upstream AS frankenphp_base

WORKDIR /app

ENV PROJECT_DIR=/app
ENV HTTP_PORT=80

VOLUME /app/var/

# persistent / runtime deps
# hadolint ignore=DL3008
RUN apt-get update && apt-get install -y --no-install-recommends \
	acl \
	curl \
	file \
	gettext \
	git \
	&& rm -rf /var/lib/apt/lists/*

# install-php-extensions (mlocati), pineado fresco (NO el que viene congelado en la base), SOLO
# para lo que NO pasa por pecl.php.net: @composer (de getcomposer.org) y las extensiones bundled
# de PHP (intl/opcache/pdo_pgsql/zip, que se compilan del source de PHP, no se bajan de pecl).
# amqp/apcu/xdebug ya NO van por acá: migraron a PIE (ver RUN siguiente y el stage dev) porque
# pecl.php.net está en phase-out (RFC adopt_pie_deprecate_pecl) y rompía el build con `exit 100`.
COPY --from=mlocati/php-extension-installer:2.12.3 /usr/bin/install-php-extensions /usr/local/bin/install-php-extensions

RUN set -eux; \
	install-php-extensions \
		@composer-2.10.3 \
		intl \
		opcache \
		pdo_pgsql \
		zip \
	;

# Extra extensions of the APP (backend/php-extensions.txt belongs to the fork; Oliva ships
# it empty). Lets a fork add e.g. bcmath without editing this file, which is Oliva's.
COPY --link php-extensions.txt /tmp/php-extensions.txt
# hadolint ignore=SC2086
RUN set -eux; \
	exts="$(grep -vE '^[[:space:]]*(#|$)' /tmp/php-extensions.txt || true)"; \
	if [ -n "$exts" ]; then install-php-extensions $exts; fi

# amqp + apcu con PIE (php/pie). La imagen oficial de PIE se monta SOLO en build-time
# (--mount=type=bind) → no queda en la imagen final. PIE baja de Packagist/GitHub, nunca de
# pecl.php.net (en phase-out, era la causa del `exit 100`). `pie install` compila Y habilita
# (escribe el .ini). Deps de build: el toolchain ($PHPIZE_DEPS) + unzip (PIE extrae zips) +
# librabbitmq-dev (amqp lo necesita para compilar); se purgan al final. librabbitmq-dev se deja
# a propósito: su runtime (librabbitmq) lo linkea amqp.so y un --auto-remove lo borraría.
# VA ÚLTIMO EN EL STAGE BASE, DESPUÉS del extension point del fork: ese purga el toolchain, y los
# `install-php-extensions` de arriba (incluido el del fork, ej. bcmath) necesitan gcc para
# compilar. Si esta purga corriera antes, el bcmath del fork fallaría con `gcc: not found` (127).
# Versiones pineadas exactas, igual que antes.
# hadolint ignore=DL3008,SC2086
RUN --mount=type=bind,from=ghcr.io/php/pie:1.5.3-bin,source=/pie,target=/usr/local/bin/pie \
	set -eux; \
	export DEBIAN_FRONTEND=noninteractive; \
	apt-get -o APT::Sandbox::User=root update; \
	apt-get install -y --no-install-recommends $PHPIZE_DEPS librabbitmq-dev unzip; \
	pie install --no-cache apcu/apcu:5.1.28; \
	pie install --no-cache php-amqp/php-amqp:2.2.0; \
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false $PHPIZE_DEPS unzip; \
	rm -rf /var/lib/apt/lists/*

# supercronic — used by the scheduler service
ENV SUPERCRONIC_VERSION=v0.2.46
RUN curl -fsSL "https://github.com/aptible/supercronic/releases/download/${SUPERCRONIC_VERSION}/supercronic-linux-amd64" \
	-o /usr/local/bin/supercronic \
	&& chmod +x /usr/local/bin/supercronic

# https://getcomposer.org/doc/03-cli.md#composer-allow-superuser
ENV COMPOSER_ALLOW_SUPERUSER=1

ENV PHP_INI_SCAN_DIR=":$PHP_INI_DIR/app.conf.d"

###> recipes ###
###< recipes ###

COPY --link frankenphp/conf.d/10-app.ini $PHP_INI_DIR/app.conf.d/
COPY --link --chmod=755 frankenphp/docker-entrypoint.sh /usr/local/bin/docker-entrypoint
COPY --link frankenphp/Caddyfile /etc/caddy/Caddyfile
COPY --link scheduler/crontab /etc/supercronic/crontab

# Install dependencies from versioned composer.json
COPY --link composer.json composer.lock symfony.lock ./
RUN composer install --prefer-dist --no-progress --no-interaction --no-scripts --no-autoloader

# Copy application source
COPY --link bin bin/
COPY --link config config/
COPY --link migrations migrations/
COPY --link public public/
COPY --link src src/
COPY --link tests tests/
COPY --link phpunit.dist.xml ./

RUN composer dump-autoload --optimize

ENTRYPOINT ["docker-entrypoint"]

HEALTHCHECK --start-period=60s CMD curl -f http://localhost:2019/metrics || exit 1
# NO envolver en `sh -c`: el entrypoint distingue su bloque de setup (genera JWT,
# espera la DB, migra) con `[ "$1" = 'frankenphp' ]`. Si el CMD es `sh -c "..."`,
# $1 pasa a ser `sh` y TODO ese bloque se saltea silenciosamente en prod.
# La race de DB la cubre el wait-for-db del entrypoint (60 reintentos), no un sleep.
CMD [ "frankenphp", "run", "--config", "/etc/caddy/Caddyfile" ]

# Dev FrankenPHP image
FROM frankenphp_base AS frankenphp_dev

ENV APP_ENV=dev XDEBUG_MODE=off
ENV FRANKENPHP_CONFIG=""

RUN mv "$PHP_INI_DIR/php.ini-development" "$PHP_INI_DIR/php.ini"

# xdebug con PIE (php-ext-zend, pineado 3.5.3) — mismo motivo que amqp/apcu: fuera de pecl.php.net.
# No necesita libs de sistema extra; solo el toolchain + unzip, que se purgan acá mismo.
# `apt-get -o APT::Sandbox::User=root`: el `COPY --link php-extensions.txt /tmp/` del stage base
# le saca el sticky 1777 a /tmp en algunos buildkit, y el sandbox `_apt` de apt no puede escribir
# ahí (mkstemp /tmp Permission denied → `exit 100`). Como root no baja de privilegios. Es lo que
# install-php-extensions hace por dentro; por eso el xdebug viejo nunca lo pegó.
# hadolint ignore=DL3008,SC2086
RUN --mount=type=bind,from=ghcr.io/php/pie:1.5.3-bin,source=/pie,target=/usr/local/bin/pie \
	set -eux; \
	export DEBIAN_FRONTEND=noninteractive; \
	apt-get -o APT::Sandbox::User=root update; \
	apt-get install -y --no-install-recommends $PHPIZE_DEPS unzip; \
	pie install --no-cache xdebug/xdebug:3.5.3; \
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false $PHPIZE_DEPS unzip; \
	rm -rf /var/lib/apt/lists/*

COPY --link frankenphp/conf.d/20-app.dev.ini $PHP_INI_DIR/app.conf.d/

CMD [ "frankenphp", "run", "--config", "/etc/caddy/Caddyfile", "--watch" ]

# Prod FrankenPHP image
FROM frankenphp_base AS frankenphp_prod

ENV APP_ENV=prod
ENV FRANKENPHP_CONFIG="import worker.Caddyfile"

RUN mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"

COPY --link frankenphp/conf.d/20-app.prod.ini $PHP_INI_DIR/app.conf.d/
COPY --link frankenphp/worker.Caddyfile /etc/caddy/worker.Caddyfile

# prevent the reinstallation of vendors at every changes in the source code
COPY --link composer.* symfony.* ./

RUN set -eux; \
	composer install --no-cache --prefer-dist --no-dev --no-autoloader --no-scripts --no-progress

# copy sources
COPY --link . ./
RUN rm -Rf frankenphp/

RUN set -eux; \
	mkdir -p var/cache var/log; \
	composer dump-autoload --classmap-authoritative --no-dev; \
	composer dump-env prod; \
	composer run-script --no-dev post-install-cmd; \
	chmod +x bin/console; sync;

# Staging FrankenPHP image — inherits from prod, adds seeding tooling (Foundry + fixtures)
# Prod image is --no-dev so this command is unavailable there: structural guard against
# accidentally seeding production.
FROM frankenphp_prod AS frankenphp_staging

ENV APP_ENV=staging

# frankenphp_prod horneó .env.local.php con APP_ENV=prod compilado (composer
# dump-env prod) — heredarlo pisaría el ENV de arriba. Hay que borrarlo antes
# del install para que el entorno de staging se resuelva en runtime.
RUN set -eux; \
	rm -f .env.local.php; \
	composer install --no-cache --prefer-dist --no-autoloader --no-scripts --no-progress; \
	composer dump-autoload --classmap-authoritative; \
	composer run-script post-install-cmd; \
	chmod +x bin/console; sync;
