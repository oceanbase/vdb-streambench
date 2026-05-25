#!/bin/bash
set -euo pipefail

# Milvus — Docker/Podman standalone install
# Supports both binary (if already installed) and container deployment.

MILVUS_VERSION="2.6.9"
MILVUS_IMAGE="docker.io/milvusdb/milvus:v${MILVUS_VERSION}"
CONTAINER_NAME="milvus"
MILVUS_DATA="/opt/milvus/data"

echo "=== Installing Milvus ${MILVUS_VERSION} ==="

# If binary install already exists, use it
if command -v milvus &>/dev/null; then
    echo "Using existing binary install"
    systemctl enable milvus 2>/dev/null || true
    systemctl start milvus
else
    # Container deployment
    mkdir -p "${MILVUS_DATA}"

    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER_NAME}$"; then
        echo "Milvus container already running"
    else
        docker rm -f "${CONTAINER_NAME}" 2>/dev/null || true

        echo "Starting Milvus standalone container..."
        docker run -d \
            --name "${CONTAINER_NAME}" \
            --privileged \
            -p 19530:19530 \
            -p 9091:9091 \
            -v "${MILVUS_DATA}:/var/lib/milvus" \
            -e ETCD_USE_EMBED=true \
            -e COMMON_STORAGETYPE=local \
            "${MILVUS_IMAGE}" \
            milvus run standalone
    fi
fi

echo "Waiting for startup (may take 1-2 minutes for embedded etcd)..."
for i in $(seq 1 90); do
    if curl -sf http://localhost:19530/v1/vector/collections >/dev/null 2>&1; then
        break
    fi
    sleep 5
done

curl -s http://localhost:19530/v1/vector/collections | head -c 200
echo
echo "=== Milvus ${MILVUS_VERSION} ready on port 19530 ==="
