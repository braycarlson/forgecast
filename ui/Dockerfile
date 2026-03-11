FROM oven/bun:1 AS deps

WORKDIR /app

COPY package.json bun.lock* bun.lockb* ./
RUN bun install && ls node_modules/vue-router

# --- Build stage ---

FROM oven/bun:1

WORKDIR /app

RUN apt-get update -y && \
    apt-get install -y nginx && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

COPY --from=deps /app/node_modules ./node_modules
COPY . .

ARG VITE_API_URL=/api
ENV VITE_API_URL=${VITE_API_URL}

RUN bun run build-only

COPY nginx.conf /etc/nginx/conf.d/default.conf
RUN cp -r dist/* /usr/share/nginx/html/

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
