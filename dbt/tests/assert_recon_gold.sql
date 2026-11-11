-- Fails (returns rows) if real-time gold and batch gold disagree on any compared transaction.
select * from {{ ref('recon_gold_diffs') }}
