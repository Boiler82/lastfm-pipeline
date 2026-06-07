{{ config(materialized='table') }}

with staging as (
    select * from {{ ref('stg_top_tracks') }}
),

with_previous as (
    select
        loaded_at,
        track_name,
        artist_name,
        chart_position,
        LAG(chart_position) OVER (
            PARTITION BY track_name
            ORDER BY loaded_at
        ) as previous_position
    from staging
),

drops as (
    select
        loaded_at,
        track_name,
        artist_name,
        chart_position,
        previous_position,
        chart_position - previous_position as positions_dropped
    from with_previous
    where previous_position is not null
    and chart_position - previous_position > 0
    and loaded_at >= DATEADD(day, -2, CURRENT_DATE)
)

select * from drops
order by positions_dropped desc