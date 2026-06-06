{{ config(materialized='view') }}

with source as (
    select
        loaded_at,
        raw_data
    from {{ source('raw', 'top_tracks') }}
),

flattened as (
    select
        loaded_at,
        value:name::string as track_name,
        value:artist.name::string as artist_name,
        value:chart_position::integer as chart_position
    from source,
    lateral flatten(input => raw_data:tracks.track)
)

select * from flattened