-- Fails (returns a row) unless bronze and the S3 batch both hold every offset of the shared range exactly once.
select *
from {{ ref('recon_summary') }}
where expected is null
   or expected <= 0
   or bronze_rows <> expected or bronze_offsets <> expected
   or batch_rows <> expected or batch_offsets <> expected
