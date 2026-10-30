-- Grain: one row per spider, describing its most recent loaded run.
with ranked as (
    select
        *,
        count(*) over (partition by spider) as runs_observed,
        row_number() over (
            partition by spider order by run_started_at desc, run_id desc
        ) as recency_rank
    from {{ ref('fct_spider_runs') }}
),

latest_run as (
    select max(run_id) as run_id from {{ ref('fct_spider_runs') }}
)

select
    ranked.spider,
    ranked.run_id as last_run_id,
    ranked.run_started_at as last_run_started_at,
    ranked.feature_count,
    ranked.error_count,
    ranked.feature_delta,
    ranked.feature_pct_change,
    ranked.health_status,
    ranked.runs_observed,
    ranked.run_id = latest_run.run_id as is_in_latest_run
    -- TODO: optional attribute completeness (share of features with phone,
    -- opening_hours, etc.) from each run's large parquet_url output.
from ranked
cross join latest_run
where ranked.recency_rank = 1
