-- Grain: one row per spider per run, with the change since that spider's
-- previous loaded run. "Previous" means the previous run present in the data,
-- so a spider missing from a run compares against its last appearance.
with stats as (
    select
        s.*,
        r.run_started_at
    from {{ ref('stg_spider_run_stats') }} as s
    inner join {{ ref('stg_runs') }} as r using (run_id)
),

with_prior as (
    select
        *,
        lag(run_id) over spider_runs as prior_run_id,
        lag(feature_count) over spider_runs as prior_feature_count
    from stats
    window spider_runs as (partition by spider order by run_started_at, run_id)
)

select
    spider_run_id,
    run_id,
    spider,
    run_started_at,
    feature_count,
    error_count,
    elapsed_seconds,
    prior_run_id,
    prior_feature_count,
    feature_count - prior_feature_count as feature_delta,
    case
        when prior_feature_count > 0
            then (feature_count - prior_feature_count)::double / prior_feature_count
    end as feature_pct_change,
    feature_count = 0 as is_zero_features,
    error_count > 0 as has_errors
    -- TODO: flag spiders missing from a run they appeared in before
    -- (needs a spider x run spine).
from with_prior
