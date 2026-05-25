#!/bin/bash
set -euo pipefail

# Qdrant — Docker/Podman install
# Supports both binary (if already installed) and container deployment.

QDRANT_VERSION="1.17.1"
QDRANT_IMAGE="docker.io/qdrant/qdrant:v${QDRANT_VERSION}"
CONTAINER_NAME="qdrant"
QDRANT_HOME="/opt/qdrant"
QDRANT_DATA="/opt/qdrant/qdrant_data"

echo "=== Installing Qdrant ${QDRANT_VERSION} ==="

# If binary install already exists, use it
if [ -f "${QDRANT_HOME}/qdrant" ]; then
    echo "Using existing binary install at ${QDRANT_HOME}"
    systemctl daemon-reload 2>/dev/null || true
    systemctl enable qdrant 2>/dev/null || true
    systemctl start qdrant
else
    # Container deployment
    mkdir -p "${QDRANT_DATA}"

    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER_NAME}$"; then
        echo "Qdrant container already running"
    else
        docker rm -f "${CONTAINER_NAME}" 2>/dev/null || true

        echo "Starting Qdrant container..."
        docker run -d \
            --name "${CONTAINER_NAME}" \
            -p 6333:6333 \
            -p 6334:6334 \
            -v "${QDRANT_DATA}:/qdrant/storage" \
            "${QDRANT_IMAGE}"
    fi
fi

echo "Waiting for startup..."
for i in $(seq 1 30); do
    if curl -sf http://localhost:6333/readyz >/dev/null 2>&1; then
        break
    fi
    sleep 2
done

curl -s http://localhost:6333
echo
echo "=== Qdrant ${QDRANT_VERSION} ready on port 6333 ==="
