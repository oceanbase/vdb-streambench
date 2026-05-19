#!/bin/bash
set -euo pipefail

# SeekDB (OceanBase) — Docker install
# Ref: https://hub.docker.com/r/oceanbase/seekdb

CONTAINER_NAME="seekdb"
SEEKDB_DATA="$PWD/seekdb_data"

echo "=== Installing SeekDB (Docker) ==="

if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "SeekDB container already running"
else
    docker rm -f "${CONTAINER_NAME}" 2>/dev/null || true
    mkdir -p "${SEEKDB_DATA}"

    echo "Starting SeekDB container..."
    docker run -d \
        --name "${CONTAINER_NAME}" \
        -p 2881:2881 \
        -p 2886:2886 \
        -v "${SEEKDB_DATA}:/var/lib/oceanbase" \
        oceanbase/seekdb

    echo "Waiting for SeekDB to initialize (this may take 1-2 minutes)..."
    for i in $(seq 1 60); do
        if mysql -h 127.0.0.1 -P 2881 -u root -e "SELECT 1" >/dev/null 2>&1; then
            break
        fi
        sleep 3
    done
fi

echo "Creating test database..."
mysql -h 127.0.0.1 -P 2881 -u root -e "CREATE DATABASE IF NOT EXISTS test;" 2>/dev/null || true

echo "Verifying..."
mysql -h 127.0.0.1 -P 2881 -u root -e "SHOW DATABASES;"
echo "=== SeekDB ready on port 2881 ==="
