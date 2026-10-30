# ATP Spider Health

A small dbt + DuckDB project that asks: **which AllThePlaces spiders are healthy enough to trust?**

[AllThePlaces](https://www.alltheplaces.xyz/) runs thousands of web scrapers ("spiders") roughly once a week. Each one collects store and office locations for a single brand. This project loads the public run history and per-spider stats, tracks how each spider's output changes from run to run, and flags spiders that return nothing, log errors, or suddenly drop features.

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
.venv/bin/dbt build                    # models and tests
.venv/bin/dbt source freshness
.venv/bin/dbt docs generate && .venv/bin/dbt docs serve
```

Run dbt from the repo root, where `profiles.yml` lives. The warehouse is the local file `atp_spider_health.duckdb`.

The loader picks the 4 most recent runs that have stats, up to and including `2026-10-17-13-32-31`, so the sample doesn't change as new runs are published. Use `--runs` and `--through-run` to load a different window, and `--refresh-history` to re-download `history.json`. Downloads are cached in `data/raw/`.

## Model layout

```
sources (raw schema, written by scripts/load_raw.py)
  atp.runs                 one row per run in history.json
  atp.spider_run_stats     one row per spider per sampled run
staging (views)
  stg_runs                 one row per run                       key: run_id
```

Source tests cover `unique` and `not_null` on `runs.run_id` and a `relationships` test from spider stats to runs. Source freshness is checked on `atp.runs.start_time`.

## Roadmap

- `stg_spider_run_stats`: one row per spider per run, with a stable `(run_id, spider)` key.
- `int_spider_run_deltas`: change in features since each spider's prior run, plus zero-feature and error flags.
- `fct_spider_runs`: an incremental fact with a per-run health status.
- `mart_spider_health`: the latest status per spider.
- A snapshot of spider status over time.
- Tests for non-negative counts, accepted status values, and a reconciliation test comparing `history.json` totals with summed stats. They don't match today: for run `2026-10-17-13-32-31`, `history.json` reports 5,704 spiders and 43,357,385 lines, but the stats sum to 5,675 spiders and 43,121,659 features.
- Optional: attribute completeness per spider from each run's Parquet output (`parquet_url`, ~3 GB per run).

## License

This repository's code is released under the [MIT License](LICENSE). The AllThePlaces data it reads is CC0, as described above.
