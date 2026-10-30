-- Grain: one row per spider per run. spider_run_id is the stable key.
select
    run_id || '/' || spider as spider_run_id,
    run_id,
    spider,
    filename as spider_filename,
    features as feature_count,
    errors as error_count,
    elapsed_time as elapsed_seconds
from {{ source('atp', 'spider_run_stats') }}
