{{ config(alias='TRANSACTION') }}

{#- Same logic as SILVER.TRANSACTION, over the full history loaded from S3 (no 7-day window). -#}
with events as (
    {{ parse_cdc_events(source('hist', 'raw_events')) }}
)
{{ latest_per_transaction('events') }}
