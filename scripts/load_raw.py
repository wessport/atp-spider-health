"""Load public AllThePlaces run history and per-spider stats into DuckDB.

Downloads history.json plus the stats for a small, pinned sample of runs,
caches the JSON under data/raw/, and (re)creates two tables in the `raw`
schema of the project's DuckDB file:

  raw.runs              one row per run in history.json
  raw.spider_run_stats  one row per spider per sampled run

The sample is reproducible: it is the N most recent runs that have a stats_url
and a run_id at or before --through-run, ordered by (start_time, run_id).

Usage:
  python scripts/load_raw.py                       # pinned defaults
  python scripts/load_raw.py --runs 8 --through-run 2026-10-17-13-32-31
"""

import argparse
import json
import urllib.request
from pathlib import Path

import duckdb

HISTORY_URL = "https://data.alltheplaces.xyz/runs/history.json"
ROOT = Path(__file__).resolve().parent.parent
RAW_DIR = ROOT / "data" / "raw"
DB_PATH = ROOT / "atp_spider_health.duckdb"

# Pinned so the sample does not change as new runs are published.
DEFAULT_THROUGH_RUN = "2026-10-17-13-32-31"
DEFAULT_RUNS = 4


def fetch(url: str, dest: Path, refresh: bool) -> Path:
    if dest.exists() and not refresh:
        return dest
    dest.parent.mkdir(parents=True, exist_ok=True)
    print(f"downloading {url}")
    # The ATP CDN rejects urllib's default User-Agent with 403.
    request = urllib.request.Request(url, headers={"User-Agent": "atp-spider-health/0.1"})
    with urllib.request.urlopen(request, timeout=120) as resp:
        dest.write_bytes(resp.read())
    return dest


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--runs", type=int, default=DEFAULT_RUNS)
    parser.add_argument("--through-run", default=DEFAULT_THROUGH_RUN)
    parser.add_argument(
        "--refresh-history",
        action="store_true",
        help="re-download history.json instead of using the cached copy",
    )
    args = parser.parse_args()

    history_path = fetch(HISTORY_URL, RAW_DIR / "history.json", args.refresh_history)
    history = json.loads(history_path.read_text())

    candidates = sorted(
        (r for r in history if r.get("stats_url") and r["run_id"] <= args.through_run),
        key=lambda r: (r["start_time"], r["run_id"]),
    )
    sample = candidates[-args.runs :]
    print(f"history runs: {len(history)}; sampled runs: {[r['run_id'] for r in sample]}")

    stats_files = []
    for run in sample:
        path = fetch(run["stats_url"], RAW_DIR / "stats" / f"{run['run_id']}.json", False)
        stats = json.loads(path.read_text())
        rows = [{"run_id": run["run_id"], **result} for result in stats["results"]]
        out = path.with_suffix(".ndjson")
        out.write_text("\n".join(json.dumps(row) for row in rows) + "\n")
        stats_files.append(str(out))

    con = duckdb.connect(str(DB_PATH))
    con.execute("create schema if not exists raw")
    con.execute(
        """
        create or replace table raw.runs as
        select
            run_id,
            cast(start_time as timestamp) as start_time,
            cast(end_time as timestamp) as end_time,
            cast(spiders as integer) as spiders,
            cast(total_lines as bigint) as total_lines,
            cast(size_bytes as bigint) as size_bytes,
            output_url,
            parquet_url,
            stats_url,
            insights_url,
            current_timestamp as _loaded_at
        from read_json(?, format = 'array', columns = {
            run_id: 'varchar', start_time: 'varchar', end_time: 'varchar',
            spiders: 'bigint', total_lines: 'bigint', size_bytes: 'bigint',
            output_url: 'varchar', parquet_url: 'varchar',
            stats_url: 'varchar', insights_url: 'varchar'
        })
        """,
        [str(history_path)],
    )
    con.execute(
        """
        create or replace table raw.spider_run_stats as
        select *, current_timestamp as _loaded_at
        from read_json(?, format = 'newline_delimited', columns = {
            run_id: 'varchar', spider: 'varchar', filename: 'varchar',
            errors: 'bigint', features: 'bigint', elapsed_time: 'double'
        })
        """,
        [stats_files],
    )
    for table in ("raw.runs", "raw.spider_run_stats"):
        print(f"{table}: {con.execute(f'select count(*) from {table}').fetchone()[0]} rows")
    con.close()


if __name__ == "__main__":
    main()
