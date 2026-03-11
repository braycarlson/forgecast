set dotenv-load

set windows-shell := ["cmd", "/c"]

clear := if os() == "windows" { "cls" } else { "clear" }

# List all available recipes.
default:
    @just --list

# Install all dependencies and set up the database.
setup:
    {{clear}}
    mix deps.get
    mix ecto.create
    mix ecto.migrate
    cd ui && bun install

# Start the backend with an interactive shell.
server:
    {{clear}}
    iex -S mix

# Start the UI development server.
ui:
    {{clear}}
    cd ui && bun run dev

# Compile the backend.
build:
    {{clear}}
    mix compile

# Compile the backend with warnings treated as errors.
build-strict:
    {{clear}}
    mix compile --warnings-as-errors

# Format all Elixir files.
format:
    {{clear}}
    mix format

# Check formatting without writing changes.
format-check:
    {{clear}}
    mix format --check-formatted

# --- Database ---

# Run pending Ecto migrations.
migrate:
    {{clear}}
    mix ecto.migrate

# Rollback the last Ecto migration.
rollback:
    {{clear}}
    mix ecto.rollback

# Generate a new Ecto migration with the given name.
migration name:
    {{clear}}
    mix ecto.gen.migration {{name}}

# Drop, create, and migrate the database from scratch.
db-reset:
    {{clear}}
    mix ecto.reset

# --- Testing ---

# Run the full test suite.
test:
    {{clear}}
    mix test

# Run the full test suite with detailed output.
test-verbose:
    {{clear}}
    mix test --trace

# Run tests excluding those tagged as slow.
test-fast:
    {{clear}}
    mix test --exclude slow

# Run a specific test file.
test-file file:
    {{clear}}
    mix test {{file}}

# Run a specific test file at a given line number.
test-line file line:
    {{clear}}
    mix test {{file}}:{{line}}

# Run only tests that failed on the last run.
test-failed:
    {{clear}}
    mix test --failed

# Run tests with coverage reporting.
test-cover:
    {{clear}}
    mix test --cover

# --- Docker ---

# Start Postgres only for local development.
db:
    {{clear}}
    docker compose up db

# Start all services in Docker.
up:
    {{clear}}
    docker compose up --build db api

# Start the backend and database only, without the poller.
up-api:
    {{clear}}
    POLLER=false docker compose up --build db api

# Start all services including the production UI.
up-all:
    {{clear}}
    docker compose up --build

# Stop all Docker services.
down:
    {{clear}}
    docker compose down

# Run Ecto migrations inside the Docker container.
docker-migrate:
    {{clear}}
    docker compose exec api bin/forgecast eval "Forgecast.Release.migrate()"

# Tail logs for all Docker services.
logs:
    {{clear}}
    docker compose logs -f

# Tail logs for a specific Docker service.
logs-service service:
    {{clear}}
    docker compose logs -f {{service}}

# Remove all Docker containers and volumes, then rebuild from scratch.
docker-reset:
    {{clear}}
    docker compose --profile dev down -v
    docker compose up --build

# --- Frontend (Production) ---

# Start the production UI container. Assumes the database and API are running.
up-app:
    {{clear}}
    docker compose up --build app

# Stop and remove the production UI container.
down-app:
    {{clear}}
    docker compose stop app
    docker compose rm -f app

# --- Frontend (Development) ---

# Start the development UI container with the dev profile.
up-dev:
    {{clear}}
    docker compose --profile dev up --build app-dev

# Stop and remove the development UI container.
down-dev:
    {{clear}}
    docker compose --profile dev stop app-dev
    docker compose --profile dev rm -f app-dev

# Lint the frontend inside the development container.
lint:
    {{clear}}
    docker compose --profile dev exec app-dev bun run lint

# Lint and auto-fix the frontend inside the development container.
lint-fix:
    {{clear}}
    docker compose --profile dev exec app-dev bun run lint:fix

# Run type checking and linting for the frontend inside the development container.
check:
    {{clear}}
    docker compose --profile dev exec app-dev bun run type-check
    docker compose --profile dev exec app-dev bun run lint
