FROM node:20-slim AS base
WORKDIR /usr/src/app
RUN command -v yarn || npm install --global yarn
# yarn.lock versionado + --frozen-lockfile: el build instala EXACTAMENTE lo
# lockeado y falla si package.json cambió sin regenerar el lock. Sin lock cada
# build resolvía versiones nuevas en silencio (mismo bug que un tag flotante).
COPY package.json yarn.lock ./
ARG NODE_ENV
RUN yarn install --frozen-lockfile --production=false

# Development Stage
FROM base AS development
EXPOSE 3000
CMD ["yarn", "run", "dev"]

# Production Stage
FROM base AS builder
COPY . .
RUN yarn run build

FROM caddy:2.8.4 AS production
WORKDIR /usr/share/caddy
COPY --from=builder /usr/src/app/dist /usr/share/caddy
COPY --link Caddyfile /etc/caddy/Caddyfile
CMD ["caddy", "run", "--config", "/etc/caddy/Caddyfile"]

