-- Business rule: the pipeline asks Last.fm for the Top 50, so every chart
-- position must be between 1 and 50. Anything else means the API response
-- or the enrichment in load_to_snowflake.py changed.
-- A dbt test passes when this query returns no rows.

select
    track_name,
    loaded_at,
    chart_position
from {{ ref('stg_top_tracks') }}
where chart_position not between 1 and 50
