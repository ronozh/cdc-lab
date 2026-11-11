{{ config(alias='TRANSACTION') }}

{#- Latest state per transaction over the last 7 days (by Kafka time). Dynamic Iceberg table, refreshed when gold needs it. -#}
with events as (
    {{ parse_cdc_events(source('bronze', 'transaction_raw')) }}
)
{{ latest_per_transaction('events', where="kafka_ts >= dateadd(day, -7, current_timestamp())") }}
