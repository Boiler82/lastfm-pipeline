-- Business rule: fct_chart_drops only contains tracks that FELL in the chart.
-- A drop of 0 or less would mean the filter in the model is broken.
-- A dbt test passes when this query returns no rows.

select
    track_name,
    loaded_at,
    previous_position,
    chart_position,
    positions_dropped
from {{ ref('fct_chart_drops') }}
where positions_dropped <= 0
