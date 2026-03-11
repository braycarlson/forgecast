ARG BUILDER_IMAGE="hexpm/elixir:1.19.5-erlang-28.2-debian-bookworm-20260202-slim"
ARG RUNNER_IMAGE="debian:bookworm-20260202-slim"

# --- UI build stage ---

FROM oven/bun:1 AS ui

WORKDIR /app

COPY ui/package.json ui/bun.lock* ui/bun.lockb* ./
RUN bun install

COPY ui/ .

ARG VITE_API_URL=/api
ENV VITE_API_URL=${VITE_API_URL}

RUN bun run build-only

# --- Elixir build stage ---

FROM ${BUILDER_IMAGE} AS builder

RUN apt-get update -y && \
    apt-get install -y build-essential git && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV MIX_ENV=prod

RUN mix local.hex --force && \
    mix local.rebar --force

COPY mix.exs mix.lock ./
RUN mix deps.get --only prod && \
    mix deps.compile

COPY config config
COPY lib lib
COPY priv priv

COPY --from=ui /app/dist priv/static

RUN mix compile
RUN mix release

# --- Runtime stage ---

FROM ${RUNNER_IMAGE}

RUN apt-get update -y && \
    apt-get install -y libstdc++6 openssl libncurses5 locales ca-certificates && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR /app

RUN useradd --create-home --shell /bin/bash forgecast && \
    mkdir -p /data/og_images /data/logs && \
    chown -R forgecast:forgecast /data

USER forgecast

COPY --from=builder --chown=forgecast:forgecast /app/_build/prod/rel/forgecast ./
COPY --chown=forgecast:forgecast entrypoint.sh ./

RUN chmod +x entrypoint.sh

ENTRYPOINT ["./entrypoint.sh"]
