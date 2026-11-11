{{ config(alias='TRANSACTION') }}

{#-
  Latest state per transaction. Dynamic Iceberg table, refreshed when gold needs it.
  The 7-day window comes from bronze (daily purge task); no time filter here, because CURRENT_TIMESTAMP in a
  dynamic table makes every refresh do work and keeps the warehouse awake even without new data.
-#}
with events as (
    {{ parse_cdc_events(source('bronze', 'transaction_raw')) }}
)
{{ latest_per_transaction('events') }}
