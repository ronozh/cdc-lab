{#-
  RECON.RECON_SUMMARY: one row, for people. Inside the shared offset range [lo, hi]:
    expected        hi - lo + 1 (one event per offset)
    bronze_*        rows / distinct offsets in bronze      → both must equal expected (no gaps, no duplicates)
    batch_*         rows / distinct offsets loaded from S3 → both must equal expected
    gold_compared   transactions whose latest event (same offset) is in both golds, inside the range
    gold_diffs      rows in RECON_GOLD_DIFFS (must be 0)
-#}
with rng as (
    select * from {{ ref('recon_range') }}
),
bronze as (
    select RECORD_METADATA:offset::int as o
    from {{ source('bronze', 'transaction_raw') }}, rng
    where RECORD_METADATA:offset::int between rng.lo and rng.hi
),
batch as (
    select RECORD_METADATA:offset::int as o
    from {{ source('hist', 'raw_events') }}, rng
    where RECORD_METADATA:offset::int between rng.lo and rng.hi
)
select
    rng.lo,
    rng.hi,
    rng.hi - rng.lo + 1                                   as expected,
    (select count(*) from bronze)                         as bronze_rows,
    (select count(distinct o) from bronze)                as bronze_offsets,
    (select count(*) from batch)                          as batch_rows,
    (select count(distinct o) from batch)                 as batch_offsets,
    (select count(*)
       from {{ ref('gold_transaction_enriched') }} r
       join {{ ref('hist_transaction_enriched') }} b
         on b.transaction_id = r.transaction_id and b.kafka_offset = r.kafka_offset
      where r.kafka_offset between rng.lo and rng.hi)    as gold_compared,
    (select count(*) from {{ ref('recon_gold_diffs') }})  as gold_diffs,
    current_timestamp()                                   as checked_at
from rng
