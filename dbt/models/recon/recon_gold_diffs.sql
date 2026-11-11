{#-
  RECON.RECON_GOLD_DIFFS: transactions where real-time gold and batch gold disagree (expected: no rows).
  Compared: transactions whose latest event lies inside the shared offset range, and for which real-time
  has nothing newer than the batch has seen (newer events are expected, not a difference).
  Whole rows are compared (hash(*)): both golds come from the same macro, so columns line up.
-#}
with rng as (
    select * from {{ ref('recon_range') }}
),
realtime as (
    select transaction_id, kafka_offset, hash(*) as row_hash
    from {{ ref('gold_transaction_enriched') }}
),
batch as (
    select transaction_id, kafka_offset, hash(*) as row_hash
    from {{ ref('hist_transaction_enriched') }}
),
paired as (
    select
        coalesce(r.transaction_id, b.transaction_id) as transaction_id,
        r.kafka_offset as realtime_offset,
        b.kafka_offset as batch_offset,
        r.row_hash     as realtime_hash,
        b.row_hash     as batch_hash
    from realtime r
    full outer join batch b on b.transaction_id = r.transaction_id
)
select
    p.*,
    case
        when p.realtime_offset is null then 'missing_in_realtime'
        when p.batch_offset is null then 'missing_in_batch'
        when p.realtime_offset <> p.batch_offset then 'different_latest_event'
        else 'different_values'
    end as issue
from paired p, rng
where greatest(coalesce(p.realtime_offset, -1), coalesce(p.batch_offset, -1)) between rng.lo and rng.hi
  and coalesce(p.realtime_offset, -1) <= rng.hi
  and (p.realtime_offset is distinct from p.batch_offset or p.realtime_hash <> p.batch_hash)
