#!/bin/bash
set -euo pipefail

# ChromaDB 1.5.9 — pip install + chroma run

CHROMA_VERSION="1.5.9"
CHROMA_DATA="/opt/chroma/data"
CHROMA_LOG="/opt/chroma/chroma.log"

echo "=== Installing ChromaDB ${CHROMA_VERSION} ==="

pip install "chromadb==${CHROMA_VERSION}" 2>/dev/null || pip install chromadb

mkdir -p "${CHROMA_DATA}" "$(dirname ${CHROMA_LOG})"

if pgrep -f "chroma run" >/dev/null 2>&1; then
    echo "ChromaDB already running"
else
    echo "Starting ChromaDB..."
    nohup chroma run \
        --host 0.0.0.0 \
        --port 8000 \
        --path "${CHROMA_DATA}" \
        > "${CHROMA_LOG}" 2>&1 &
    sleep 3
fi

echo "Verifying..."
curl -s http://localhost:8000/api/v1/heartbeat
echo
echo "=== ChromaDB ${CHROMA_VERSION} ready on port 8000 ==="
