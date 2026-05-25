#!/bin/bash
set -euo pipefail

# Elasticsearch — Docker/Podman install
# Supports both binary (if already installed) and container deployment.

ES_VERSION="9.3.3"
ES_IMAGE="docker.io/elastic/elasticsearch:${ES_VERSION}"
CONTAINER_NAME="elasticsearch"
ES_HOME="/opt/elasticsearch"

echo "=== Installing Elasticsearch ${ES_VERSION} ==="

# If binary install already exists, use it
if [ -d "${ES_HOME}/bin" ]; then
    echo "Using existing binary install at ${ES_HOME}"

    if ! id elasticsearch &>/dev/null; then
        groupadd -f elasticsearch
        useradd -g elasticsearch elasticsearch 2>/dev/null || true
    fi
    chown -R elasticsearch:elasticsearch "${ES_HOME}"

    grep -q "vm.max_map_count=262144" /etc/sysctl.conf 2>/dev/null || {
        echo "vm.max_map_count=262144" >> /etc/sysctl.conf
        sysctl -p 2>/dev/null || true
    }

    systemctl daemon-reload 2>/dev/null || true
    systemctl enable elasticsearch 2>/dev/null || true
    systemctl start elasticsearch
else
    # Container deployment
    sysctl -w vm.max_map_count=262144 2>/dev/null || true

    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER_NAME}$"; then
        echo "Elasticsearch container already running"
    else
        docker rm -f "${CONTAINER_NAME}" 2>/dev/null || true

        echo "Starting Elasticsearch container..."
        docker run -d \
            --name "${CONTAINER_NAME}" \
            -p 9200:9200 \
            -e "discovery.type=single-node" \
            -e "xpack.security.enabled=false" \
            -e "xpack.security.enrollment.enabled=false" \
            -e "ES_JAVA_OPTS=-Xms30g -Xmx30g" \
            "${ES_IMAGE}"
    fi
fi

echo "Waiting for startup..."
for i in $(seq 1 60); do
    if curl -sf http://localhost:9200 >/dev/null 2>&1; then
        break
    fi
    sleep 3
done

curl -s http://localhost:9200
echo
echo "=== Elasticsearch ${ES_VERSION} ready on port 9200 ==="
