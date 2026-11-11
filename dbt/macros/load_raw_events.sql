{#-
  Batch path, step 1: load raw S3 files into HIST.RAW_EVENTS (full history, append-only).
  Usage: dbt run-operation load_raw_events --args "{day: '2026-11-11'}"    (omit day = every file)

  - Reshapes each line into bronze's shape, so the same macros (cdc.sql) parse both paths:
      RECORD_METADATA = {topic, partition, offset, CreateTime} from the fields the S3 sink added
      RECORD_CONTENT  = the Debezium event without those fields
  - Idempotent: COPY remembers loaded files (64 days), so re-running a day loads only new files.
-#}
{% macro load_raw_events(day=none) %}
    {%- set table = 'CDC_LAB.HIST.RAW_EVENTS' -%}
    {%- set path = '' -%}
    {%- if day -%}
        {%- set d = modules.datetime.date.fromisoformat(day) -%}
        {%- set path = 'year=%04d/month=%02d/day=%02d/' % (d.year, d.month, d.day) -%}
    {%- endif -%}

    {% do run_query("
        create table if not exists " ~ table ~ " (
            RECORD_METADATA variant,
            RECORD_CONTENT  variant,
            FILE_NAME       string,
            LOADED_AT       timestamp_ltz
        ) comment = 'cdc-lab batch path: raw events loaded from S3 (load_raw_events)'
    ") %}

    {% set result = run_query("
        copy into " ~ table ~ " (RECORD_METADATA, RECORD_CONTENT, FILE_NAME, LOADED_AT)
        from (
            select
                object_construct(
                    'topic', 'cdc.public.transaction',
                    'partition', $1:kafka_partition,
                    'offset', $1:kafka_offset,
                    'CreateTime', $1:kafka_timestamp
                ),
                object_delete($1, 'kafka_partition', 'kafka_offset', 'kafka_timestamp'),
                metadata$filename,
                current_timestamp()
            from @CDC_LAB.HIST.RAW_STAGE/" ~ path ~ "
        )
        file_format = (type = json)
        on_error = abort_statement
    ") %}

    {#- COPY returns one row per file: (file, status, rows_parsed, rows_loaded, ...); or one row "0 files processed". -#}
    {%- set ns = namespace(files=0, rows=0) -%}
    {%- for r in result.rows if r[1] == 'LOADED' -%}
        {%- set ns.files = ns.files + 1 -%}
        {%- set ns.rows = ns.rows + r[3] -%}
    {%- endfor -%}
    {{ log("load_raw_events(" ~ (day or 'all') ~ "): " ~ ns.files ~ " new file(s), " ~ ns.rows ~ " row(s)", info=True) }}
{% endmacro %}
