#!/bin/bash
set -euo pipefail

# Qdrant 1.17.1 — binary install + systemd

QDRANT_VERSION="1.17.1"
QDRANT_URL="https://github.com/qdrant/qdrant/releases/download/v${QDRANT_VERSION}/qdrant-x86_64-unknown-linux-musl.tar.gz"
QDRANT_HOME="/opt/qdrant"

echo "=== Installing Qdrant ${QDRANT_VERSION} ==="

mkdir -p "${QDRANT_HOME}"

if [ ! -f "${QDRANT_HOME}/qdrant" ]; then
    echo "Downloading..."
    wget -q "${QDRANT_URL}" -O "/tmp/qdrant.tar.gz"
    tar -zxf "/tmp/qdrant.tar.gz" -C "${QDRANT_HOME}"
    rm -f "/tmp/qdrant.tar.gz"
fi

mkdir -p "${QDRANT_HOME}/qdrant_data/snapshots"
mkdir -p "${QDRANT_HOME}/config"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "${SCRIPT_DIR}/qdrant_config.yaml" ]; then
    cp "${SCRIPT_DIR}/qdrant_config.yaml" "${QDRANT_HOME}/config/config.yaml"
else
    echo "Warning: qdrant_config.yaml not found, using defaults"
fi

cat > /etc/systemd/system/qdrant.service <<EOF
[Unit]
Description=Qdrant Vector Database
After=network.target

[Service]
Type=simple
User=root
ExecStart=${QDRANT_HOME}/qdrant --config-path ${QDRANT_HOME}/config/config.yaml
Restart=always
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

echo "Starting Qdrant..."
systemctl daemon-reload
systemctl enable qdrant
systemctl start qdrant

echo "Waiting for startup..."
for i in $(seq 1 15); do
    if curl -s http://localhost:6333/healthz >/dev/null 2>&1; then
        break
    fi
    sleep 2
done

curl -s http://localhost:6333
echo
echo "=== Qdrant ${QDRANT_VERSION} ready on port 6333 ==="
