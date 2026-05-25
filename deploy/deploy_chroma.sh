#!/bin/bash
set -euo pipefail

# ChromaDB 1.5.9 — install into project venv + pysqlite3 wrapper
# On systems with SQLite < 3.35 the chroma CLI crashes on import, so we
# launch via a thin wrapper that swaps in pysqlite3 first.

CHROMA_VERSION="1.5.9"
CHROMA_DATA="/opt/chroma/data"
CHROMA_LOG="/opt/chroma/chroma.log"
CHROMA_WRAPPER="/opt/chroma/start_chroma.py"

# When run via SSH stdin (bash -s), $0 is "bash" and dirname won't help.
# Use PROJECT_ROOT env var if set, otherwise try script path, otherwise error.
if [ -n "${PROJECT_ROOT:-}" ] && [ -d "${PROJECT_ROOT}/.venv" ]; then
    :
elif [ -f "$0" ] && [ "$(basename "$0")" != "bash" ]; then
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
else
    echo "Error: PROJECT_ROOT not set and cannot detect from script path" >&2
    echo "Set PROJECT_ROOT or REMOTE_PROJECT_ROOT in .env" >&2
    exit 1
fi
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
