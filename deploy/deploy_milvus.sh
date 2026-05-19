#!/bin/bash
set -euo pipefail

# Milvus 2.6.9 — RPM binary install + systemd
# Ref: https://milvus.io/docs/zh/install_standalone-binary.md

MILVUS_VERSION="2.6.9"
RPM_URL="https://github.com/milvus-io/milvus/releases/download/v${MILVUS_VERSION}/milvus_${MILVUS_VERSION}-1_amd64.rpm"
RPM_FILE="milvus_${MILVUS_VERSION}-1_amd64.rpm"

echo "=== Installing Milvus ${MILVUS_VERSION} ==="

if ! command -v milvus &>/dev/null; then
    echo "Downloading RPM..."
    wget -q "${RPM_URL}" -O "${RPM_FILE}"
    yum install -y "./${RPM_FILE}"
    rm -f "${RPM_FILE}"
fi

echo "Starting Milvus..."
systemctl enable milvus
systemctl start milvus
systemctl status milvus --no-pager

echo "Verifying..."
sleep 5
curl -s http://localhost:19530/v1/vector/collections | head -c 200
echo
echo "=== Milvus ${MILVUS_VERSION} ready on port 19530 ==="
