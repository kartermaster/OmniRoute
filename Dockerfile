FROM node:22.22.2-trixie-slim AS builder
WORKDIR /app

RUN apt-get update \
  && apt-get install -y --no-install-recommends libsecret-1-0 ca-certificates \
  && rm -rf /var/lib/apt/lists/*

COPY package*.json ./
COPY scripts/postinstall.mjs ./scripts/postinstall.mjs
COPY scripts/native-binary-compat.mjs ./scripts/native-binary-compat.mjs
RUN if [ -f package-lock.json ]; then npm ci --no-audit --no-fund; else npm install --no-audit --no-fund; fi

COPY . ./

# 1. ВСТАВКА ДЛЯ БИЛДА (чтобы не было FATAL: JWT_SECRET is not set)
ARG JWT_SECRET="EtqKjBPCdor5oH2e8uVKegiliqD+nvVm7uOru1zDYQFclUBdfHJA5iiSVIljI43g"
ENV JWT_SECRET=$JWT_SECRET

RUN mkdir -p /app/data && npm run build -- --webpack

FROM node:22.22.2-trixie-slim AS runner-base
WORKDIR /app

LABEL org.opencontainers.image.title="omniroute" \
  org.opencontainers.image.description="Unified AI proxy — route any LLM through one endpoint" \
  org.opencontainers.image.url="https://omniroute.online" \
  org.opencontainers.image.source="https://github.com/diegosouzapw/OmniRoute" \
  org.opencontainers.image.licenses="MIT"

ENV NODE_ENV=production
ENV PORT=20128
ENV HOSTNAME=0.0.0.0

# 2. ВСТАВКА ДЛЯ ИСПРАВЛЕНИЯ ОШИБКИ КИРО (fetch failed)
# Добавляем флаг ipv4first в NODE_OPTIONS
ENV NODE_OPTIONS="--max-old-space-size=256 --dns-result-order=ipv4first"
# Прописываем секрет и для работы самого приложения
ENV JWT_SECRET="EtqKjBPCdor5oH2e8uVKegiliqD+nvVm7uOru1zDYQFclUBdfHJA5iiSVIljI43g"

# Data directory inside Docker
ENV DATA_DIR=/app/data
RUN apt-get update \
  && apt-get install -y --no-install-recommends libsecret-1-0 ca-certificates \
  && rm -rf /var/lib/apt/lists/*
RUN mkdir -p /app/data

COPY --from=builder /app/public ./public
COPY --from=builder /app/.next/static ./.next/static
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/node_modules/@swc/helpers ./node_modules/@swc/helpers
COPY --from=builder /app/node_modules/pino-abstract-transport ./node_modules/pino-abstract-transport
COPY --from=builder /app/node_modules/pino-pretty ./node_modules/pino-pretty
COPY --from=builder /app/node_modules/split2 ./node_modules/split2
COPY --from=builder /app/scripts/run-standalone.mjs ./run-standalone.mjs
COPY --from=builder /app/scripts/runtime-env.mjs ./runtime-env.mjs
COPY --from=builder /app/scripts/bootstrap-env.mjs ./bootstrap-env.mjs
COPY --from=builder /app/scripts/healthcheck.mjs ./healthcheck.mjs

EXPOSE 20128

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD ["node", "healthcheck.mjs"]

CMD ["node", "run-standalone.mjs"]

FROM runner-base AS runner-cli

RUN apt-get update \
  && apt-get install -y --no-install-recommends git ca-certificates docker.io docker-compose \
  && rm -rf /var/lib/apt/lists/* \
  && git config --system url."https://github.com/".insteadOf "ssh://git@github.com/"

RUN npm install -g --no-audit --no-fund @openai/codex @anthropic-ai/claude-code droid openclaw@latest
