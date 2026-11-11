{{ config(alias='TRANSACTION_ENRICHED') }}

{#- Silver + customer tier + product type. TARGET_LAG 1 minute: at most ~1 minute behind bronze. -#}
{{ enrich_transactions(ref('silver_transaction')) }}
