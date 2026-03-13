#!/bin/bash
set -e

echo "Waiting for database..."
for i in $(seq 1 30); do
    if bin/forgecast eval "Forgecast.Repo.query('SELECT 1')" 2>/dev/null; then
        echo "Database is ready."
        break
    fi
    echo "Attempt $i/30 — waiting 2s..."
    sleep 2
done

echo "Running migrations..."
bin/forgecast eval "Forgecast.Release.migrate()"

echo "Starting Forgecast..."
exec bin/forgecast start

echo "Running migrations..."
bin/forgecast eval "Forgecast.Release.migrate()"

echo "Starting Forgecast..."
exec bin/forgecast start
