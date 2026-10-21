#syntax=docker/dockerfile:1

# Versions
# Pinned to an exact version: the floating "1-php8.3" tag pulled 1.13.1 on a rebuild and
# its Mercure refused the existing hub config. Upgrade on purpose, then re-check Mercure.
FROM dunglas/frankenphp:1.13.1-php8.3.35 AS frankenphp_upstream

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

# PECL extensions and composer pinned like the base image: unpinned, every rebuild took
# whatever pecl.php.net served that day. Bump on purpose (deps.sh report lists the base image).
RUN set -eux; \
	install-php-extensions \
		@composer-2.10.3 \
		amqp-2.2.0 \
		apcu-5.1.28 \
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

RUN set -eux; \
	install-php-extensions \
		xdebug-3.5.3 \
	;

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
