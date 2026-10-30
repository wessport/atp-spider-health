-- Grain: one row per AllThePlaces run.
select
    run_id,
    start_time as run_started_at,
    end_time as run_ended_at,
    spiders as reported_spider_count,
    total_lines as reported_feature_count,
    size_bytes,
    stats_url,
    stats_url is not null as has_stats,
    parquet_url
from {{ source('atp', 'runs') }}
