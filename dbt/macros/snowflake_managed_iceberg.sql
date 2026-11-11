{#-
  dbt-snowflake always adds BASE_LOCATION to dynamic Iceberg tables, but Snowflake rejects it for Snowflake storage
  ("BASE_LOCATION property is not supported for Iceberg tables using Snowflake Managed Storage").
  These overrides call dbt's own macros and drop BASE_LOCATION when the volume is SNOWFLAKE_MANAGED.
-#}

{% macro _drop_base_location(ddl) -%}
    {%- if "SNOWFLAKE_MANAGED" in ddl | upper -%}
        {{ modules.re.sub("base_location\\s*=\\s*'[^']*'", "", ddl, flags=modules.re.IGNORECASE) }}
    {%- else -%}
        {{ ddl }}
    {%- endif -%}
{%- endmacro %}

{% macro snowflake__create_dynamic_table_built_in_sql(dynamic_table, relation, sql) -%}
    {{ _drop_base_location(dbt.snowflake__create_dynamic_table_built_in_sql(dynamic_table, relation, sql)) }}
{%- endmacro %}

{% macro snowflake__replace_dynamic_table_built_in_sql(dynamic_table, relation, sql) -%}
    {{ _drop_base_location(dbt.snowflake__replace_dynamic_table_built_in_sql(dynamic_table, relation, sql)) }}
{%- endmacro %}
