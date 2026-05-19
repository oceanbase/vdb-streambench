#!/usr/bin/env python3
"""Benchmark vector databases using VectorDBBench StreamingPerformanceCase."""

import argparse
import csv
import os
import subprocess
import sys
import time
from pathlib import Path

# Fix sqlite3 for ChromaDB on systems with old SQLite (<3.35)
try:
    __import__("pysqlite3")
    sys.modules["sqlite3"] = sys.modules.pop("pysqlite3")
except ImportError:
    pass

from dotenv import load_dotenv
from tabulate import tabulate

from vectordb_bench.backend.cases import CaseType
from vectordb_bench.backend.clients import DB
from vectordb_bench.backend.data_source import DatasetSource
from vectordb_bench.backend.dataset import DatasetWithSizeType
from vectordb_bench.interface import benchmark_runner
from vectordb_bench.models import CaseConfig, TaskConfig

from vectordb_bench.backend.clients.milvus.config import HNSWConfig as MilvusHNSWConfig
from vectordb_bench.backend.clients.milvus.config import MilvusConfig
from vectordb_bench.backend.clients.elastic_cloud.config import (
    ElasticCloudConfig,
    ElasticCloudIndexConfig,
)
from vectordb_bench.backend.clients.qdrant_local.config import (
    QdrantLocalConfig,
    QdrantLocalIndexConfig,
)
from vectordb_bench.backend.clients.chroma.config import ChromaConfig, ChromaIndexConfig
from vectordb_bench.backend.clients.lancedb.config import LanceDBConfig, LanceDBHNSWIndexConfig
from vectordb_bench.backend.clients.seekdb.config import SeekDBConfig, SeekDBHNSWConfig

RESULTS_DIR = Path("/tmp/vectordb_bench_results")

DATASET_MAP = {
    "CohereSmall": DatasetWithSizeType.CohereSmall,
    "CohereMedium": DatasetWithSizeType.CohereMedium,
    "CohereLarge": DatasetWithSizeType.CohereLarge,
}

ALL_DBS = ["seekdb", "elasticsearch", "milvus", "chroma", "qdrant", "lancedb"]

STOP_COMMANDS = {
    "milvus": "systemctl stop milvus",
    "elasticsearch": "systemctl stop elasticsearch",
    "qdrant": "systemctl stop qdrant",
    "chroma": "pkill -f 'chroma run'",
    "seekdb": "docker stop seekdb",
    "lancedb": None,
}


def stop_db(name: str):
    cmd = STOP_COMMANDS.get(name)
    if not cmd:
        return
    print(f"  Stopping {name}...")
    try:
        subprocess.run(cmd, shell=True, timeout=60, check=False)
        print(f"  {name} stopped")
    except Exception as e:
        print(f"  Warning: failed to stop {name}: {e}")


def build_db_config(name: str):
    # HNSW params unified across all DBs
    # m=16, ef_construction=256, ef_search=200
    if name == "milvus":
        return (
            DB.Milvus,
            MilvusConfig(uri=os.getenv("MILVUS_URI", "http://localhost:19530")),
            MilvusHNSWConfig(M=16, efConstruction=256, ef=200),
        )
    if name == "elasticsearch":
        return (
            DB.ElasticCloud,
            ElasticCloudConfig(
                host=os.getenv("ES_HOST", "localhost"),
                port=int(os.getenv("ES_PORT", "9200")),
                scheme="http",
                password=os.getenv("ES_PASSWORD", "unused"),
            ),
            ElasticCloudIndexConfig(M=16, efConstruction=256, num_candidates=200),
        )
    if name == "qdrant":
        return (
            DB.QdrantLocal,
            QdrantLocalConfig(url=os.getenv("QDRANT_URL", "http://localhost:6333")),
            QdrantLocalIndexConfig(m=16, ef_construct=256, hnsw_ef=200),
        )
    if name == "chroma":
        return (
            DB.Chroma,
            ChromaConfig(
                host=os.getenv("CHROMA_HOST", "localhost"),
                port=int(os.getenv("CHROMA_PORT", "8000")),
            ),
            ChromaIndexConfig(m=16, ef_construct=256, ef_search=200),
        )
    if name == "lancedb":
        return (
            DB.LanceDB,
            LanceDBConfig(
                uri=os.getenv("LANCEDB_URI", "./lancedb_data"),
                db_label="lancedb",
            ),
            LanceDBHNSWIndexConfig(m=16, ef_construction=256, ef=200),
        )
    if name == "seekdb":
        return (
            DB.SeekDB,
            SeekDBConfig(
                host=os.getenv("SEEKDB_HOST", "127.0.0.1"),
                port=int(os.getenv("SEEKDB_PORT", "2881")),
                user=os.getenv("SEEKDB_USER", "root"),
                password=os.getenv("SEEKDB_PASSWORD", "unused"),
                database=os.getenv("SEEKDB_DATABASE", "test"),
            ),
            SeekDBHNSWConfig(m=16, ef_construction=256, ef_search=200),
        )
    raise ValueError(f"Unknown database: {name}")


def download_dataset(dataset_enum):
    """Pre-download dataset with S3 -> AliyunOSS fallback."""
    from vectordb_bench.backend.cases import StreamingPerformanceCase

    case = StreamingPerformanceCase(dataset_with_size_type=dataset_enum.value)
    dm = case.dataset

    for source in [DatasetSource.S3, DatasetSource.AliyunOSS]:
        try:
            print(f"  Trying {source.value}...")
            if dm.prepare(source=source):
                print(f"  Dataset ready (source: {source.value})")
                return True
        except Exception as e:
            print(f"  {source.value} failed: {e}")

    print("  Warning: pre-download failed, benchmark will attempt download itself")
    return False


def build_task(db_name, dataset_enum):
    custom_case = {
        "dataset_with_size_type": dataset_enum.value,
        "insert_rate": 500,
        "search_stages": [0.5, 0.8],
        "concurrencies": [5, 10],
        "read_dur_after_write": 30,
    }

    db, db_config, db_case_config = build_db_config(db_name)
    return TaskConfig(
        db=db,
        db_config=db_config,
        db_case_config=db_case_config,
        case_config=CaseConfig(
            case_id=CaseType.StreamingPerformanceCase,
            custom_case=custom_case,
        ),
    )


def run_single_db(db_name, dataset_enum, task_label):
    """Run benchmark for a single DB, then stop the DB service."""
    print(f"\n--- Benchmarking {db_name} ---")
    task = build_task(db_name, dataset_enum)
    label = f"{task_label}_{db_name}"

    if not benchmark_runner.run([task], task_label=label):
        print(f"  Error: failed to start benchmark for {db_name}", file=sys.stderr)
        return label

    while benchmark_runner.has_running():
        time.sleep(10)
        print(".", end="", flush=True)
    print(f" {db_name} done!")

    stop_db(db_name)
    return label


def extract_80_metrics(metric):
    """Extract 80% stage metrics from a Metric object."""
    stages = getattr(metric, "st_search_stage_list", None) or []

    idx = None
    for i, s in enumerate(stages):
        if s == 80 or s == 0.8:
            idx = i
            break
    if idx is None:
        return None

    def safe_get(lst, i):
        try:
            return lst[i] if lst else None
        except (IndexError, TypeError):
            return None

    return {
        "recall": safe_get(metric.st_recall_list, idx),
        "serial_p99": safe_get(metric.st_serial_latency_p99_list, idx),
        "conc_qps": safe_get(metric.st_conc_qps_list_list, idx),
        "conc_p99": safe_get(metric.st_conc_latency_p99_list_list, idx),
        "conc_nums": safe_get(metric.st_conc_num_list_list, idx),
    }


def fmt_conc(values, nums):
    if not values or not nums:
        return "N/A"
    return " / ".join(f"c{n}:{v:.2f}" for n, v in zip(nums, values))


def print_summary(results, task_labels, run_label):
    headers = [
        "Database",
        "Conc QPS (80%)",
        "Serial P99 (80%) ms",
        "Conc P99 (80%) ms",
        "Recall (80%)",
    ]
    rows = []

    for tr in results:
        if tr.task_label not in task_labels:
            continue
        for cr in tr.results:
            db_name = cr.task_config.db.value
            m = extract_80_metrics(cr.metrics)
            if m is None:
                rows.append([db_name, "N/A", "N/A", "N/A", "N/A"])
                continue
            rows.append([
                db_name,
                fmt_conc(m["conc_qps"], m["conc_nums"]),
                f"{m['serial_p99'] * 1000:.2f}" if m["serial_p99"] else "N/A",
                fmt_conc(
                    [v * 1000 for v in m["conc_p99"]] if m["conc_p99"] else None,
                    m["conc_nums"],
                ),
                f"{m['recall']:.4f}" if m["recall"] else "N/A",
            ])

    print("\n=== Streaming Benchmark Results (80% stage) ===\n")
    print(tabulate(rows, headers=headers, tablefmt="pipe"))

    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    csv_path = RESULTS_DIR / f"summary_{run_label}.csv"
    with open(csv_path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(headers)
        writer.writerows(rows)
    print(f"\nCSV saved to: {csv_path}")


def main():
    parser = argparse.ArgumentParser(
        description="VectorDBBench Streaming Performance Benchmark"
    )
    parser.add_argument(
        "-d", "--databases", nargs="+", choices=ALL_DBS, default=ALL_DBS,
        help="Databases to benchmark (default: all)",
    )
    parser.add_argument(
        "--dataset",
        choices=list(DATASET_MAP.keys()),
        default="CohereSmall",
        help="Dataset to use (default: CohereSmall)",
    )
    args = parser.parse_args()

    load_dotenv()

    dataset_enum = DATASET_MAP[args.dataset]
    run_label = f"streaming_{time.strftime('%Y%m%d_%H%M%S')}"

    print(f"Databases : {', '.join(args.databases)}")
    print(f"Dataset   : {args.dataset}")
    print(f"Label     : {run_label}")
    print(f"Results   : {RESULTS_DIR}")

    print("\n[1/3] Downloading dataset...")
    download_dataset(dataset_enum)

    print("\n[2/3] Running benchmarks (one DB at a time, stopping after each)...")
    task_labels = []
    for i, db_name in enumerate(args.databases, 1):
        print(f"\n[{i}/{len(args.databases)}] {db_name}")
        label = run_single_db(db_name, dataset_enum, run_label)
        task_labels.append(label)

    print("\n[3/3] Collecting results...")
    results = benchmark_runner.get_results()
    if not results:
        print("No results found.", file=sys.stderr)
        sys.exit(1)

    print_summary(results, set(task_labels), run_label)


if __name__ == "__main__":
    main()
