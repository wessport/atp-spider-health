-- Grain: one row per spider per run. Incremental: each build adds runs newer
-- than the latest run already in the table.
{{
    config(
        materialized='incremental',
        unique_key='spider_run_id',
        incremental_strategy='delete+insert',
        on_schema_change='append_new_columns'
    )
}}

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
    feature_delta,
    feature_pct_change,
    is_zero_features,
    has_errors,
    -- TODO: these thresholds are placeholders; tune them, or move them to vars.
    case
        when is_zero_features then 'failing'
        when has_errors or feature_pct_change <= -0.5 then 'warning'
        else 'healthy'
    end as health_status
from {{ ref('int_spider_run_deltas') }}

{% if is_incremental() %}
-- Reprocess the latest loaded run so late corrections replace it. Runs older
-- than that (for example, a backfill) need `dbt build --full-refresh`.
where run_started_at >= (select max(run_started_at) from {{ this }})
{% endif %}
