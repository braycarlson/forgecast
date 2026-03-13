#!/usr/bin/env bash
#
# Forgecast — Fly.io first-time setup and deploy.
#
# Prerequisites:
#   - flyctl installed and authenticated (fly auth login)
#   - Docker running (for the build step)
#
# Usage:
#   ./deploy.sh setup    — full first-time setup (app + db + volume + secrets + deploy)
#   ./deploy.sh deploy   — deploy only (assumes app and db already exist)
#   ./deploy.sh db       — create and attach the database only
#   ./deploy.sh secrets  — set secrets from .env interactively
#   ./deploy.sh migrate  — run migrations on the deployed app
#   ./deploy.sh ci       — generate deploy token for GitHub Actions
#   ./deploy.sh domain   — add custom domain and show DNS records
#   ./deploy.sh status   — show app, db, and volume status
#   ./deploy.sh console  — open a remote IEx console
#   ./deploy.sh destroy  — tear everything down (asks for confirmation)

set -euo pipefail

# Git Bash on Windows doesn't inherit the Windows PATH entry for fly.
# Resolve fly.exe when running under WSL.
if ! command -v fly &>/dev/null && ! command -v fly.exe &>/dev/null; then
    for dir in /mnt/c/Users/*/.fly/bin; do
        if [ -x "$dir/fly.exe" ]; then
            export PATH="$PATH:$dir"
            break
        fi
    done
fi

# WSL doesn't resolve "fly" to "fly.exe" — create a wrapper.
if ! command -v fly &>/dev/null && command -v fly.exe &>/dev/null; then
    fly() { fly.exe "$@"; }
    export -f fly
fi

if ! command -v fly &>/dev/null; then
    red "Error: fly not found. Install flyctl or add it to your PATH."
    exit 1
fi

APP_NAME="forgecast"
REGION="yyz"
DB_NAME="forgecast-db"
DB_IMAGE="flyio/postgres-flex-timescaledb:16"
VOLUME_NAME="forgecast"
VOLUME_SIZE_GB=1
DB_VOLUME_SIZE_GB=10
DOMAIN="forgecast.io"
ENV_FILE=".env"

# ---------------------------------------------------------------
# Colors
# ---------------------------------------------------------------

red()    { printf "\033[0;31m%s\033[0m\n" "$1"; }
green()  { printf "\033[0;32m%s\033[0m\n" "$1"; }
yellow() { printf "\033[0;33m%s\033[0m\n" "$1"; }
bold()   { printf "\033[1m%s\033[0m\n" "$1"; }

# ---------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------

app_exists() {
    fly apps list --json 2>/dev/null | grep -q "\"${APP_NAME}\""
}

db_exists() {
    fly postgres list --json 2>/dev/null | grep -q "\"${DB_NAME}\""
}

volume_exists() {
    fly volumes list --app "$APP_NAME" --json 2>/dev/null | grep -q "\"${VOLUME_NAME}\""
}

# ---------------------------------------------------------------
# Steps
# ---------------------------------------------------------------

step_create_app() {
    bold "Step 1: Create Fly app"

    if app_exists; then
        green "  App '$APP_NAME' already exists, skipping."
    else
        fly apps create "$APP_NAME" --machines
        green "  Created app '$APP_NAME'."
    fi
    echo
}

step_create_db() {
    bold "Step 2: Create Postgres + TimescaleDB database"
    yellow "  Using image: $DB_IMAGE"
    echo

    if db_exists; then
        green "  Database '$DB_NAME' already exists, skipping creation."
    else
        fly pg create \
            --name "$DB_NAME" \
            --image-ref "$DB_IMAGE" \
            --region "$REGION" \
            --vm-size shared-cpu-1x \
            --initial-cluster-size 1 \
            --volume-size "$DB_VOLUME_SIZE_GB"

        green "  Created database '$DB_NAME' with TimescaleDB (${DB_VOLUME_SIZE_GB}GB volume)."

        yellow "  Waiting 10s for database to become ready..."
        sleep 10
    fi

    echo
    bold "  Attaching database to app..."

    if fly postgres attach "$DB_NAME" --app "$APP_NAME" 2>&1 | grep -q "already"; then
        green "  Database already attached."
    else
        green "  Attached '$DB_NAME' to '$APP_NAME'."
        yellow "  DATABASE_URL has been set as a secret automatically."
    fi

    echo
    bold "  Enabling TimescaleDB extension..."

    db_name=$(echo "$APP_NAME" | tr '-' '_')

    if fly ssh console --app "$DB_NAME" \
        -C "psql -U postgres -d $db_name -c 'CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;'" \
        2>/dev/null; then
        green "  TimescaleDB extension enabled."
    else
        yellow "  Could not enable extension automatically."
        yellow "  Run this manually:"
        yellow "    fly pg connect --app $DB_NAME"
        yellow "    CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;"
    fi
    echo
}

step_create_volume() {
    bold "Step 3: Create persistent volume"

    if volume_exists; then
        green "  Volume '$VOLUME_NAME' already exists, skipping."
    else
        fly volumes create "$VOLUME_NAME" \
            --app "$APP_NAME" \
            --region "$REGION" \
            --size "$VOLUME_SIZE_GB" \
            --yes

        green "  Created ${VOLUME_SIZE_GB}GB volume '$VOLUME_NAME' in $REGION."
    fi
    echo
}

step_set_secrets() {
    bold "Step 4: Set secrets"
    echo

    if [ ! -f "$ENV_FILE" ]; then
        red "  No $ENV_FILE found. Create one with KEY=VALUE pairs."
        echo
        return
    fi

    yellow "  Reading secrets from $ENV_FILE"
    yellow "  Lines without a value will be prompted interactively."
    yellow "  Press Enter to skip any secret you don't want to change."
    echo

    secrets_args=()

    # Secrets already defined in fly.toml [env] — skip these
    # and unset them if they were previously set as secrets.
    skip_keys="POLLER MIX_ENV PORT GITHUB_OAUTH_REDIRECT_URI"

    unset_args=()
    for sk in $skip_keys; do
        if fly secrets list --app "$APP_NAME" 2>/dev/null | grep -qw "$sk"; then
            unset_args+=("$sk")
        fi
    done

    if [ ${#unset_args[@]} -gt 0 ]; then
        yellow "  Unsetting secrets managed by fly.toml: ${unset_args[*]}"
        fly secrets unset --app "$APP_NAME" "${unset_args[@]}"
    fi

    while IFS= read -r line || [ -n "$line" ]; do
        # Skip empty lines and comments
        line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [[ -z "$line" || "$line" == \#* ]] && continue

        if [[ "$line" == *"="* ]]; then
            key="${line%%=*}"
            value="${line#*=}"
            # Strip surrounding quotes
            value=$(echo "$value" | sed "s/^['\"]//;s/['\"]$//")
        else
            key="$line"
            value=""
        fi

        if [ -z "$value" ]; then
            existing=$(fly secrets list --app "$APP_NAME" 2>/dev/null | grep "$key" || true)

            if [ -n "$existing" ]; then
                yellow "  $key is already set. Press Enter to keep, or type a new value."
            else
                yellow "  $key"
            fi

            printf "  > "
            read -r value
        else
            green "  $key=<from .env>"
        fi

        if [ -n "$value" ]; then
            secrets_args+=("${key}=${value}")
        fi
    done < "$ENV_FILE"

    if [ ${#secrets_args[@]} -gt 0 ]; then
        fly secrets set --app "$APP_NAME" "${secrets_args[@]}"
        green "  Secrets updated."
    else
        green "  No secrets changed."
    fi
    echo
}

step_deploy() {
    bold "Deploying..."
    echo

    fly deploy --app "$APP_NAME" --yes

    green "  Deploy complete."
    echo
}

step_migrate() {
    bold "Running migrations..."
    echo

    fly ssh console --app "$APP_NAME" -C '/app/bin/forgecast eval "Forgecast.Release.migrate()"'

    green "  Migrations complete."
    echo
}

step_status() {
    bold "App status"
    fly status --app "$APP_NAME" 2>/dev/null || red "  App not found."
    echo

    bold "Volumes"
    fly volumes list --app "$APP_NAME" 2>/dev/null || red "  No volumes."
    echo

    bold "Secrets"
    fly secrets list --app "$APP_NAME" 2>/dev/null || red "  No secrets."
    echo

    bold "Database"
    if db_exists; then
        fly postgres status --app "$DB_NAME" 2>/dev/null || true
    else
        red "  Database '$DB_NAME' not found."
    fi
    echo
}

step_console() {
    fly ssh console --app "$APP_NAME" -C '/app/bin/forgecast remote'
}

step_domain() {
    bold "Custom domain setup"
    echo

    fly certs add "$DOMAIN" --app "$APP_NAME" 2>&1 || true
    fly certs add "www.${DOMAIN}" --app "$APP_NAME" 2>&1 || true

    echo
    green "  Certificates requested for $DOMAIN and www.${DOMAIN}."
    yellow "  Fly handles SSL automatically once DNS is pointing here."
    echo
    fly certs list --app "$APP_NAME" 2>/dev/null || true
    echo
}

step_ci() {
    bold "GitHub Actions — Auto-deploy setup"
    echo

    if [ ! -d ".github/workflows" ]; then
        yellow "  No .github/workflows directory found."
        yellow "  Create it and add deploy.yml before running this."
        echo
        return
    fi

    if [ ! -f ".github/workflows/deploy.yml" ]; then
        yellow "  No .github/workflows/deploy.yml found."
        yellow "  Add the workflow file before running this."
        echo
        return
    fi

    green "  .github/workflows/deploy.yml found."
    echo

    bold "  Generating deploy token..."
    token=$(fly tokens create deploy --app "$APP_NAME" 2>/dev/null)

    if [ -z "$token" ]; then
        red "  Failed to generate token."
        return
    fi

    echo
    green "  Token generated. Add it to your GitHub repo:"
    echo
    yellow "  1. Go to: https://github.com/<you>/<repo>/settings/secrets/actions"
    yellow "  2. Click 'New repository secret'"
    yellow "  3. Name:  FLY_API_TOKEN"
    yellow "  4. Value: (copied below)"
    echo
    echo "  $token"
    echo
    green "  Once added, every push to 'main' will auto-deploy."
    echo
}

step_destroy() {
    echo
    red "This will permanently destroy:"
    red "  - App: $APP_NAME"
    red "  - Database: $DB_NAME"
    red "  - All volumes and data"
    echo

    printf "Type '%s' to confirm: " "$APP_NAME"
    read -r confirmation

    if [ "$confirmation" != "$APP_NAME" ]; then
        yellow "Aborted."
        exit 0
    fi

    echo
    fly apps destroy "$APP_NAME" --yes 2>/dev/null || true
    fly apps destroy "$DB_NAME" --yes 2>/dev/null || true
    green "Destroyed."
}

# ---------------------------------------------------------------
# Main
# ---------------------------------------------------------------

case "${1:-}" in
    setup)
        bold "Forgecast — Fly.io Setup"
        echo
        step_create_app
        step_create_db
        step_create_volume
        step_set_secrets
        step_deploy
        step_ci
        step_domain
        echo
        green "Setup complete. Your app is live at https://${DOMAIN}"
        echo
        yellow "Make sure your DNS records are configured (see output above)."
        echo
        ;;
    deploy)
        step_deploy
        ;;
    db)
        step_create_db
        ;;
    secrets)
        step_set_secrets
        ;;
    migrate)
        step_migrate
        ;;
    ci)
        step_ci
        ;;
    domain)
        step_domain
        ;;
    status)
        step_status
        ;;
    console)
        step_console
        ;;
    destroy)
        step_destroy
        ;;
    *)
        bold "Usage: ./deploy.sh <command>"
        echo
        echo "  setup    — full first-time setup (app + db + volume + secrets + deploy)"
        echo "  deploy   — deploy only"
        echo "  db       — create and attach database (TimescaleDB)"
        echo "  secrets  — set secrets from .env"
        echo "  migrate  — run migrations on deployed app"
        echo "  ci       — generate deploy token for GitHub Actions"
        echo "  domain   — add custom domain and show DNS records"
        echo "  status   — show app, db, and volume status"
        echo "  console  — open remote IEx console"
        echo "  destroy  — tear everything down"
        echo
        ;;
esac
