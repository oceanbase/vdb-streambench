# VDB StreamBench

Reproducible streaming-ingestion benchmarks across multiple vector databases,
built on VectorDBBench's `StreamingPerformanceCase`.

The benchmark evaluates how each database performs while data is continuously
being inserted — balancing index construction, write throughput, search latency,
recall, and memory usage under a realistic production pattern.

## Supported Databases

| Database | Deploy | Health Check | Notes |
|---|---|---|---|
| SeekDB | `deploy_seekdb.sh` | `mysql ... SELECT 1` | Docker-based |
| Elasticsearch | `deploy_elasticsearch.sh` | `curl :9200` | systemd service |
| Milvus | `deploy_milvus.sh` | `curl :19530` | systemd service |
| Chroma | `deploy_chroma.sh` | `curl :8000` | Python process |
| Qdrant | `deploy_qdrant.sh` | `curl :6333` | systemd service |
| LanceDB | N/A | N/A | Embedded, no external service |

## Quick Start

```bash
python3.11 -m venv .venv
source .venv/bin/activate
pip install -U pip && pip install -e .

# Run all databases on CohereSmall (default)
python run_bench.py

# Run specific databases on a larger dataset
python run_bench.py -d seekdb milvus qdrant --dataset CohereLarge
```

## Deployment Modes

The runner automatically detects whether each database is local or remote based
on its configured host address.

### Local (default)

When the host resolves to `localhost` / `127.0.0.1` / `::1`:

1. Health-check the database.
2. If not healthy, run the deploy script locally.
3. After benchmark, stop the database service locally.

### Remote (split client/server)

When the host points to a remote address (e.g., `SEEKDB_HOST=172.16.0.200`):

1. Health-check the database from the client machine.
2. If not healthy, deploy via SSH (`ssh {SSH_USER}@{host} bash -s < script`).
3. After benchmark, stop the database via SSH.

Requirements for remote mode:
- SSH key authentication set up between client and server.
- The client machine must be able to reach the database port directly (for
  health checks and benchmark connections).
- `SSH_USER` env var (default: `root`).

## Configuration

Service addresses are configured via environment variables or a `.env` file.
The runner calls `load_dotenv()` at startup.

```bash
# .env example
MILVUS_URI=http://localhost:19530

ES_HOST=localhost
ES_PORT=9200
ES_PASSWORD=unused

QDRANT_URL=http://localhost:6333

CHROMA_HOST=localhost
CHROMA_PORT=8000

LANCEDB_URI=./lancedb_data

SEEKDB_HOST=127.0.0.1
SEEKDB_PORT=2881
SEEKDB_USER=bench
SEEKDB_PASSWORD=bench123
SEEKDB_DATABASE=test

# SSH user for remote deploy/stop (default: root)
SSH_USER=root
```

## Datasets

| Name | Vectors | Dimensions |
|---|---|---|
| `CohereSmall` | 1M | 768 |
| `CohereMedium` | 5M | 768 |
| `CohereLarge` | 10M | 768 |

The runner downloads datasets from S3, falling back to Aliyun OSS on failure.

## Benchmark Parameters

All databases use unified HNSW index parameters:

| Parameter | Value |
|---|---|
| `M` | 16 |
| `ef_construction` | 256 |
| `ef_search` | 200 |

Streaming case defaults:

| Parameter | Value |
|---|---|
| `insert_rate` | 500 rows/s |
| `search_stages` | 50%, 80% |
| `concurrencies` | 5, 10 |
| `read_dur_after_write` | 30s |

## CohereLarge Memory Tuning

CohereLarge (10M x 768dim) is memory-intensive. On a 61 GB server the HNSW
index alone grows to ~37 GB at full scale. The runner automatically applies the
following when running SeekDB + CohereLarge:

1. **THP check** -- verifies Transparent Huge Pages is disabled on the server.
   THP causes ~7 GB+ untracked memory fragmentation leading to OOM. The runner
   exits with a detailed error if THP is still enabled:

   ```bash
   echo never > /sys/kernel/mm/transparent_hugepage/enabled
   echo never > /sys/kernel/mm/transparent_hugepage/defrag
   ```

2. **Memory parameters** -- raises limits to fully utilize the server:
   - `memory_limit_percentage = 90`
   - `ob_vector_memory_limit_percentage = 80`

Smaller datasets (CohereSmall/CohereMedium) stay within default limits and
don't need these adjustments.

## Results

The runner prints a comparison table at 80% stage and saves a CSV:

```
/tmp/vectordb_bench_results/summary_streaming_YYYYMMDD_HHMMSS.csv
```

Metrics reported: Concurrent QPS, Serial P99, Concurrent P99, Recall.

## Running in Background

```bash
nohup python run_bench.py \
  -d seekdb milvus qdrant \
  --dataset CohereLarge \
  > /tmp/bench_coherelarge.log 2>&1 &

tail -f /tmp/bench_coherelarge.log
```

## Project Layout

```
.
├── deploy/
│   ├── deploy_chroma.sh
│   ├── deploy_elasticsearch.sh
│   ├── deploy_milvus.sh
│   ├── deploy_qdrant.sh
│   ├── deploy_seekdb.sh
│   └── qdrant_config.yaml
├── pyproject.toml
├── README.md
└── run_bench.py
```

## Requirements

- Python >= 3.11
- Linux (deploy scripts use `systemctl`, `curl`, `docker`, etc.)
- `mysql` client (for SeekDB health checks)
- Sufficient memory for database services and dataset
- Network access for downloading datasets and database binaries

## Dependency Notes

Pinned OpenTelemetry/protobuf versions for Chroma + Milvus compatibility:

```
protobuf>=5.27.2,<7
opentelemetry-api==1.41.1
opentelemetry-sdk==1.41.1
opentelemetry-proto==1.41.1
opentelemetry-exporter-otlp-proto-grpc==1.41.1
```

Chroma requires SQLite >= 3.35. The project includes `pysqlite3-binary` and
swaps it in at startup for systems with older SQLite.

## Troubleshooting

**`ModuleNotFoundError: No module named 'dotenv'`** -- Install project
dependencies: `pip install -e .`

**`Descriptors cannot be created directly`** -- Reinstall to fix
protobuf/OpenTelemetry mismatch: `pip install -U -e .`

**`Chroma requires sqlite3 >= 3.35.0`** -- Ensure `pysqlite3-binary` is
installed via `pip install -e .`

**Health check fails** -- Verify the service manually:

```bash
curl http://localhost:9200                          # Elasticsearch
curl http://localhost:6333/readyz                    # Qdrant
curl http://localhost:8000/api/v2/heartbeat          # Chroma
curl http://localhost:19530/v1/vector/collections    # Milvus
mysql -h 127.0.0.1 -P 2881 -u bench -pbench123 -e "SELECT 1"  # SeekDB
```
