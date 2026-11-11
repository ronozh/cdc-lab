{{ config(materialized='ephemeral') }}

{#-
  The Kafka offset range both paths have seen: bronze (real-time input) ∩ HIST.RAW_EVENTS (batch input).
  Bronze's lower end only counts events up to 6 days old, so they are surely inside silver's 7-day window.
  One topic partition (0), so offsets alone identify events.
-#}
with bronze as (
    select min(RECORD_METADATA:offset::int) as lo, max(RECORD_METADATA:offset::int) as hi
    from {{ source('bronze', 'transaction_raw') }}
    where to_timestamp_ltz(RECORD_METADATA:CreateTime::number, 3) >= dateadd(day, -6, current_timestamp())
),
batch as (
    select min(RECORD_METADATA:offset::int) as lo, max(RECORD_METADATA:offset::int) as hi
    from {{ source('hist', 'raw_events') }}
)
select greatest(bronze.lo, batch.lo) as lo, least(bronze.hi, batch.hi) as hi
from bronze, batch
