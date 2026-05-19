# VDB StreamBench

This project runs reproducible streaming-ingestion benchmarks across multiple
vector databases using VectorDBBench's `StreamingPerformanceCase`.

The benchmark focuses on a common production pattern: vectors are inserted over
time while the system is also serving searches. Instead of measuring only a
fully-loaded, read-only index, the script evaluates how each database behaves
while data is still being written.

## Background

Vector databases often look different under streaming workloads than under
offline bulk-load workloads. During continuous ingestion, a database must balance
index construction, write throughput, search latency, recall, memory use, and
background compaction or persistence work.

This repository wraps VectorDBBench with a simple runner that:

- Downloads the selected VectorDBBench dataset before the run.
- Deploys and health-checks each selected database.
- Runs one database at a time to reduce resource interference.
- Stops each database after its benchmark finishes.
- Collects result JSON files and prints a compact comparison table.
- Saves a CSV summary under `/tmp/vectordb_bench_results`.

The current benchmark uses HNSW-style index parameters across supported
databases where possible:

- `M = 16`
- `ef_construction = 256`
- `ef_search = 200`

The default streaming case uses:

- `insert_rate = 500`
- `search_stages = [0.5, 0.8]`
- `concurrencies = [5, 10]`
- `read_dur_after_write = 30`

## Supported Databases

The runner currently supports:

- SeekDB
- Elasticsearch
- Milvus
- Chroma
- Qdrant
- LanceDB

Deployment helpers live in `deploy/`. The runner checks whether a database is
already healthy before starting it. If the database is not healthy and a deploy
script exists, the runner executes the matching deploy script automatically.

LanceDB is embedded and does not require an external service.

## Requirements

Use Linux for full benchmark execution. The deployment scripts assume common
Linux tools and services such as `systemctl`, `curl`, `wget`, `tar`, `yum`, and
`mysql`.

Python requirements:

- Python 3.11 or newer
- A virtual environment
- Project dependencies installed from `pyproject.toml`

System requirements:

- Sufficient memory for database services. Elasticsearch is configured with a
  30 GB heap in `deploy/deploy_elasticsearch.sh`.
- Sufficient disk space for datasets, database data, and result files.
- Container support for SeekDB. The script uses the `docker` command. On some
  Alibaba Cloud Linux images, `docker` may be provided by `podman-docker`, which
  is also acceptable for the current deployment script.
- Network access for downloading Python packages, benchmark datasets, and
  database binaries or images.

## Installation

Clone or copy the project to the target Linux machine, then create a Python 3.11
virtual environment from the project root:

```bash
cd /root/vdb-bench

python3.11 -m venv .venv
source .venv/bin/activate

python -m pip install -U pip
python -m pip install -e .
```

Do not use the system Python if it is older than Python 3.11. For example, some
Linux distributions still provide Python 3.6 as `/usr/bin/python`.

## Dependency Notes

This project pins a compatible OpenTelemetry/protobuf dependency set for Chroma,
Milvus, and the current VectorDBBench dependency graph.

The important compatibility constraints are:

- `protobuf>=5.27.2,<7`
- `opentelemetry-api==1.41.1`
- `opentelemetry-sdk==1.41.1`
- `opentelemetry-proto==1.41.1`
- `opentelemetry-exporter-otlp-proto-grpc==1.41.1`

Chroma also requires SQLite 3.35 or newer. Many enterprise Linux systems ship an
older system SQLite. The project depends on `pysqlite3-binary`, and
`run_bench.py` swaps it in before importing Chroma-related modules.

## Usage

Run all supported databases on the default dataset:

```bash
cd /root/vdb-bench
source .venv/bin/activate

python run_bench.py
```

Run all supported databases on the medium Cohere dataset:

```bash
python run_bench.py \
  -d seekdb elasticsearch milvus chroma qdrant lancedb \
  --dataset CohereMedium
```

Run only one database:

```bash
python run_bench.py -d qdrant --dataset CohereSmall
```

Run a subset of databases:

```bash
python run_bench.py -d milvus qdrant lancedb --dataset CohereMedium
```

Show command-line help:

```bash
python run_bench.py --help
```

## Datasets

Supported dataset names:

- `CohereSmall`
- `CohereMedium`
- `CohereLarge`

The runner first attempts to prepare the dataset from S3, then falls back to
Aliyun OSS if the S3 download fails.

## Runtime Behavior

The benchmark flow is:

1. Load environment variables from `.env` if present.
2. Download or prepare the selected dataset.
3. For each selected database:
   - Check whether the database is already healthy.
   - Deploy it if needed.
   - Build the VectorDBBench task config.
   - Run the streaming performance benchmark.
   - Wait until the benchmark finishes.
   - Stop the database service or container.
4. Read VectorDBBench result JSON files.
5. Print an 80% stage comparison table.
6. Save a CSV summary.

Each database is benchmarked sequentially so that one database does not consume
CPU, memory, or IO during another database's run.

## Configuration

Most defaults are defined in `run_bench.py`. You can override service addresses
with environment variables or a `.env` file.

Supported environment variables include:

```bash
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
```

## Results

The script prints a table similar to:

```text
=== Streaming Benchmark Results (80% stage) ===
```

The summary includes:

- Concurrent QPS at the 80% stage.
- Serial P99 latency at the 80% stage.
- Concurrent P99 latency at the 80% stage.
- Recall at the 80% stage.

CSV summaries are written to:

```text
/tmp/vectordb_bench_results
```

The filename format is:

```text
summary_streaming_YYYYMMDD_HHMMSS.csv
```

VectorDBBench also writes its raw result files under its configured local results
directory. `run_bench.py` reads those JSON files directly when building the final
summary.

## Deployment Helpers

The deployment scripts are:

- `deploy/deploy_seekdb.sh`
- `deploy/deploy_elasticsearch.sh`
- `deploy/deploy_milvus.sh`
- `deploy/deploy_chroma.sh`
- `deploy/deploy_qdrant.sh`

The runner maps databases to these scripts automatically. You can also execute a
deployment script manually when debugging a single service:

```bash
bash deploy/deploy_qdrant.sh
```

## Troubleshooting

### `ModuleNotFoundError: No module named 'dotenv'`

Install the project dependencies inside the virtual environment:

```bash
source .venv/bin/activate
python -m pip install -e .
```

### `Descriptors cannot be created directly`

This usually means an incompatible `protobuf` and OpenTelemetry proto package
combination is installed. Reinstall the project dependencies after pulling the
latest `pyproject.toml`:

```bash
source .venv/bin/activate
python -m pip install -U -e .
```

You can verify the relevant versions with:

```bash
python -m pip show protobuf opentelemetry-proto opentelemetry-exporter-otlp-proto-grpc
```

### `Chroma requires sqlite3 >= 3.35.0`

Install dependencies from this project so that `pysqlite3-binary` is available:

```bash
source .venv/bin/activate
python -m pip install -e .
```

`run_bench.py` imports `pysqlite3` before importing Chroma and replaces the
standard `sqlite3` module for the current process.

### `docker.service not found`

Some machines provide the `docker` command through `podman-docker` instead of a
Docker daemon managed by `docker.service`. Check the runtime with:

```bash
docker info
```

The SeekDB deploy script only needs the `docker` command to support container
operations such as `docker run`, `docker ps`, `docker rm`, and `docker stop`.

### Database Health Checks Fail

Check the service manually:

```bash
curl http://localhost:9200
curl http://localhost:6333/readyz
curl http://localhost:8000/api/v2/heartbeat
curl http://localhost:19530/v1/vector/collections
mysql -h 127.0.0.1 -P 2881 -u bench -pbench123 -e "SELECT 1"
```

Then inspect the corresponding service logs or deployment logs.

## Running in the Background

Longer datasets can take a while. To keep the benchmark running after the SSH
session exits:

```bash
cd /root/vdb-bench
source .venv/bin/activate

nohup python run_bench.py \
  -d seekdb elasticsearch milvus chroma qdrant lancedb \
  --dataset CohereMedium \
  > bench_CohereMedium.log 2>&1 &
```

Follow the log:

```bash
tail -f bench_CohereMedium.log
```

## Project Layout

```text
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

## Notes for Benchmark Interpretation

Benchmark results are sensitive to hardware, kernel settings, filesystem
performance, memory pressure, service versions, and dataset download location.
For fair comparisons, run all databases on the same machine with the same
dataset and avoid other heavy workloads during the benchmark.

Because the runner starts and stops services sequentially, results are intended
to compare each database under similar machine-level conditions rather than under
multi-database contention.
