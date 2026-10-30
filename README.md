# ATP Spider Health

A small dbt + DuckDB project that asks: **which AllThePlaces spiders are healthy enough to trust?**

[AllThePlaces](https://www.alltheplaces.xyz/) runs thousands of web scrapers ("spiders") roughly once a week. Each one collects store and office locations for a single brand. This project loads the public run history and per-spider stats, tracks how each spider's output changes from run to run, and flags spiders that return nothing, log errors, or suddenly drop features.

It is a learning project, so several models are deliberately skeletal and marked with `TODO`.

## Data source and license

All data comes from the public AllThePlaces project:

- Run history: <https://data.alltheplaces.xyz/runs/history.json>
- Per-run spider stats: each run's `stats_url` (`.../runs/<run_id>/stats/_results.json`)

The AllThePlaces data downloads are released under the [CC0 1.0 public domain waiver](https://creativecommons.org/publicdomain/zero/1.0/). The spider software that produces them is [MIT licensed](https://github.com/alltheplaces/alltheplaces). CC0 doesn't require attribution, but credit goes to the [AllThePlaces contributors](https://github.com/alltheplaces/alltheplaces). This project only reads their published outputs and isn't affiliated with AllThePlaces.

## Run it

Requires Python 3.10–3.14. Everything installs into a project-local virtual environment.

```sh
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt

.venv/bin/python scripts/load_raw.py   # download history + stats for 4 pinned runs into DuckDB
.venv/bin/dbt build                    # models, snapshot and tests
.venv/bin/dbt source freshness
.venv/bin/dbt docs generate && .venv/bin/dbt docs serve
```

Run dbt from the repo root, where `profiles.yml` lives. The warehouse is the local file `atp_spider_health.duckdb`.

The loader picks the 4 most recent runs that have stats, up to and including `2026-10-17-13-32-31`, so the sample doesn't change as new runs are published. Use `--runs` and `--through-run` to load a different window, and `--refresh-history` to re-download `history.json`. Downloads are cached in `data/raw/`.

`dbt build` is expected to finish with one warning: the reconciliation test described below.

## Model layout

```
sources (raw schema, written by scripts/load_raw.py)
  atp.runs                 one row per run in history.json
  atp.spider_run_stats     one row per spider per sampled run
staging (views)
  stg_runs                 one row per run                       key: run_id
  stg_spider_run_stats     one row per spider per run            key: spider_run_id (run_id/spider)
intermediate (views)
  int_spider_run_deltas    feature change since the spider's prior run, zero-feature and error flags
marts (tables)
  fct_spider_runs          incremental; one row per spider per run with a health_status
  mart_spider_health       one row per spider: status of its latest run
snapshots
  spider_health_snapshot   point-in-time history of each spider's status
```

`health_status` is `failing` when a spider returns zero features, `warning` when it logs errors or loses at least half its features since its prior run, and `healthy` otherwise. The thresholds are placeholders.

## Tests

- `unique` and `not_null` on every key, including `spider_run_id` (so `(spider, run_id)` is unique)
- `non_negative` (a small generic test in `tests/generic/`) on feature and error counts
- `accepted_values` on `health_status`
- `relationships` from spider stats to runs
- Source freshness on `atp.runs.start_time`
- `tests/assert_run_totals_reconcile.sql`: compares the spider and feature totals in `history.json` with the totals summed from each run's stats. They don't match. For run `2026-10-17-13-32-31`, `history.json` reports 5,704 spiders and 43,357,385 lines, but the stats sum to 5,675 spiders and 43,121,659 features. The test is set to warn so the gap stays visible without failing the build.

## TODO

- Explain the reconciliation gap (spiders in the count but missing from `results`?) and decide whether it should fail.
- Flag spiders that disappear from a run they used to appear in (needs a spider × run spine).
- Tune the health thresholds, possibly as dbt `vars`.
- Decide how the snapshot should handle spiders that disappear (`hard_deletes`).
- Backfills: the incremental model only adds runs at or after its latest run, so loading older runs needs `dbt build --full-refresh`.
- Optional: attribute completeness per spider from each run's Parquet output (`parquet_url`, ~3 GB per run).

## License

This repository's code is released under the [MIT License](LICENSE). The AllThePlaces data it reads is CC0, as described above.
