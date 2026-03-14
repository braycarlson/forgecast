#!/bin/bash
set -e

echo "Running migrations..."
bin/forgecast eval "Forgecast.Release.migrate()"

echo "Starting Forgecast..."
exec bin/forgecast start
