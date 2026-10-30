-- Reconciliation: for each run with loaded stats, history.json's spider and
-- feature totals should equal the counts summed from stats/_results.json.
-- They don't today (e.g. 2026-10-17-13-32-31 reports 5,704 spiders and
-- 43,357,385 lines, but its stats sum to 5,675 spiders and 43,121,659
-- features), so this warns rather than fails.
{{ config(severity='warn') }}

with stats_totals as (
    select
        run_id,
        count(*) as stats_spider_count,
        sum(feature_count) as stats_feature_count
    from {{ ref('stg_spider_run_stats') }}
    group by run_id
)

select
    r.run_id,
    r.reported_spider_count,
    s.stats_spider_count,
    r.reported_spider_count - s.stats_spider_count as spider_gap,
    r.reported_feature_count,
    s.stats_feature_count,
    r.reported_feature_count - s.stats_feature_count as feature_gap
from {{ ref('stg_runs') }} as r
inner join stats_totals as s using (run_id)
where r.reported_spider_count is distinct from s.stats_spider_count
   or r.reported_feature_count is distinct from s.stats_feature_count
