# ---- deps: instala dependencias y compila el binding nativo de better-sqlite3 ----
FROM node:20-bookworm-slim AS deps
WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends python3 make g++ \
    && rm -rf /var/lib/apt/lists/*

COPY package.json package-lock.json ./
RUN npm ci --omit=dev

# ---- runtime: imagen final, sin herramientas de compilacion ----
FROM node:20-bookworm-slim
WORKDIR /app
ENV NODE_ENV=production \
    TZ=America/Monterrey

ARG OPENCODE_VERSION=latest
RUN npm install -g opencode-ai@${OPENCODE_VERSION} @ai-sdk/openai-compatible

COPY requirements.txt ./
RUN apt-get update \
    && apt-get install -y --no-install-recommends python3 python3-pip tzdata \
    && ln -snf /usr/share/zoneinfo/$TZ /etc/localtime \
    && echo $TZ > /etc/timezone \
    && rm -rf /var/lib/apt/lists/* \
    && pip3 install --no-cache-dir --break-system-packages -r requirements.txt

COPY --from=deps /app/node_modules ./node_modules
COPY package.json ./
COPY src ./src
COPY scripts ./scripts
COPY public ./public
COPY prompts ./prompts
COPY ejemplos ./ejemplos
COPY opencode.json ./opencode.json

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD ["node", "-e", "require('http').get('http://localhost:3000/healthz',r=>process.exit(r.statusCode===200?0:1)).on('error',()=>process.exit(1))"]

CMD ["node", "src/index.js"]
