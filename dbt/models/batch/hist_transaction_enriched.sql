{{ config(alias='TRANSACTION_ENRICHED') }}

{#- Same logic as GOLD.TRANSACTION_ENRICHED, full history. -#}
{{ enrich_transactions(ref('hist_transaction')) }}
