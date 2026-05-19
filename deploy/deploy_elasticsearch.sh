#!/bin/bash
set -euo pipefail

# Elasticsearch 9.3.3 — tar install + systemd
# Ref: https://www.elastic.co/downloads/elasticsearch

ES_VERSION="9.3.3"
ES_URL="https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-${ES_VERSION}-linux-x86_64.tar.gz"
ES_HOME="/opt/elasticsearch"

echo "=== Installing Elasticsearch ${ES_VERSION} ==="

if [ ! -d "${ES_HOME}/bin" ]; then
    echo "Downloading..."
    wget -q "${ES_URL}" -O "/tmp/elasticsearch-${ES_VERSION}.tar.gz"
    mkdir -p "${ES_HOME}"
    tar -zxf "/tmp/elasticsearch-${ES_VERSION}.tar.gz" -C "${ES_HOME}" --strip-components=1
    rm -f "/tmp/elasticsearch-${ES_VERSION}.tar.gz"
fi

if ! id elasticsearch &>/dev/null; then
    groupadd -f elasticsearch
    useradd -g elasticsearch elasticsearch 2>/dev/null || true
fi
chown -R elasticsearch:elasticsearch "${ES_HOME}"

mkdir -p "${ES_HOME}/data" "${ES_HOME}/logs"

grep -q "elasticsearch soft nofile" /etc/security/limits.conf 2>/dev/null || {
    echo "elasticsearch soft nofile 65536" >> /etc/security/limits.conf
    echo "elasticsearch hard nofile 65536" >> /etc/security/limits.conf
}

grep -q "vm.max_map_count=262144" /etc/sysctl.conf 2>/dev/null || {
    echo "vm.max_map_count=262144" >> /etc/sysctl.conf
    sysctl -p
}

# ES 9.x auto-generates a security config block (TLS + enrollment) on first
# start, which overrides a simple sed patch.  Write the full config up front
# so the auto-generation never kicks in.
cat > "${ES_HOME}/config/elasticsearch.yml" <<'ESYML'
xpack.security.enabled: false
xpack.security.enrollment.enabled: false
xpack.security.http.ssl.enabled: false
xpack.security.transport.ssl.enabled: false
http.host: 0.0.0.0
discovery.type: single-node
ESYML
cat > "${ES_HOME}/config/jvm.options.d/heap.options" <<'JVMEOF'
-Xms30g
-Xmx30g
JVMEOF

chown -R elasticsearch:elasticsearch "${ES_HOME}"

cat > /etc/systemd/system/elasticsearch.service <<'EOF'
[Unit]
Description=Elasticsearch
Wants=network-online.target
After=network-online.target

[Service]
User=elasticsearch
Group=elasticsearch
WorkingDirectory=/opt/elasticsearch
ExecStart=/opt/elasticsearch/bin/elasticsearch
LimitNOFILE=65536
LimitMEMLOCK=infinity

[Install]
WantedBy=multi-user.target
EOF

echo "Starting Elasticsearch..."
systemctl daemon-reload
systemctl enable elasticsearch
systemctl start elasticsearch

echo "Waiting for startup..."
for i in $(seq 1 30); do
    if curl -s http://localhost:9200 >/dev/null 2>&1; then
        break
    fi
    sleep 2
done

curl -s http://localhost:9200
echo
echo "=== Elasticsearch ${ES_VERSION} ready on port 9200 ==="
