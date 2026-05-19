#!/bin/bash
set -euo pipefail

# ChromaDB 1.5.9 — install into project venv + pysqlite3 wrapper
# On systems with SQLite < 3.35 the chroma CLI crashes on import, so we
# launch via a thin wrapper that swaps in pysqlite3 first.

CHROMA_VERSION="1.5.9"
CHROMA_DATA="/opt/chroma/data"
CHROMA_LOG="/opt/chroma/chroma.log"
CHROMA_WRAPPER="/opt/chroma/start_chroma.py"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
VENV_PYTHON="${PROJECT_ROOT}/.venv/bin/python"

echo "=== Installing ChromaDB ${CHROMA_VERSION} ==="

if [ ! -x "${VENV_PYTHON}" ]; then
    echo "Error: venv not found at ${PROJECT_ROOT}/.venv" >&2
    echo "Run 'uv venv --python python3.11 .venv && uv pip install -e .' first" >&2
    exit 1
fi

mkdir -p "${CHROMA_DATA}" "$(dirname "${CHROMA_LOG}")"

# Create pysqlite3 wrapper so chroma works on old-SQLite systems
cat > "${CHROMA_WRAPPER}" <<'PYEOF'
try:
    import pysqlite3, sys
    sys.modules["sqlite3"] = sys.modules.pop("pysqlite3")
except ImportError:
    pass
from chromadb.cli.cli import app
app()
PYEOF

if pgrep -f "${CHROMA_WRAPPER}" >/dev/null 2>&1; then
    echo "ChromaDB already running"
else
    pkill -f "${CHROMA_WRAPPER}" 2>/dev/null || true
    sleep 1

    echo "Starting ChromaDB..."
    nohup "${VENV_PYTHON}" "${CHROMA_WRAPPER}" run \
        --host 0.0.0.0 \
        --port 8000 \
        --path "${CHROMA_DATA}" \
        > "${CHROMA_LOG}" 2>&1 &
    sleep 5
fi

echo "Verifying..."
curl -s http://localhost:8000/api/v2/heartbeat || curl -s http://localhost:8000/api/v1/heartbeat
echo
echo "=== ChromaDB ${CHROMA_VERSION} ready on port 8000 ==="
