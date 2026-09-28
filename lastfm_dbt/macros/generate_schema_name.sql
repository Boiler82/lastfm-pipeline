{#
    By default dbt builds models in "<target schema>_<custom schema>",
    e.g. STAGING_MARTS instead of MARTS.
    This override uses the custom schema name exactly as written in
    dbt_project.yml (+schema: STAGING / +schema: MARTS), so the models land in
    LASTFM.STAGING and LASTFM.MARTS, the schemas created in snowflake_setup.sql.
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim | upper }}
    {%- endif -%}
{%- endmacro %}
