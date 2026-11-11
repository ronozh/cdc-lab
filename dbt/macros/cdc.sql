{#-
  The one transformation logic, shared by the real-time path (dynamic tables over BRONZE.TRANSACTION_RAW)
  and the batch path (tables over HIST.RAW_EVENTS). Both inputs have the same two VARIANT columns:
    RECORD_METADATA  Kafka: partition, offset, CreateTime (ms), ...
    RECORD_CONTENT   Debezium event: before, after, op, source {lsn, ts_ms, ...}, ts_ms
-#}

{#- One typed row per change event (r = snapshot, c = insert, u = update). -#}
{% macro parse_cdc_events(relation) -%}
    select
        RECORD_METADATA:partition::int                                as kafka_partition,
        RECORD_METADATA:offset::int                                   as kafka_offset,
        to_timestamp_ltz(RECORD_METADATA:CreateTime::number, 3)::timestamp_ltz(6)     as kafka_ts,   -- Iceberg timestamps: scale 6
        RECORD_CONTENT:op::string                                     as op,
        RECORD_CONTENT:source:lsn::number                             as lsn,
        to_timestamp_ltz(RECORD_CONTENT:source:ts_ms::number, 3)::timestamp_ltz(6)    as committed_at,
        RECORD_CONTENT:after:transaction_id::string                   as transaction_id,
        to_timestamp_ntz(RECORD_CONTENT:after:event_ts::number, 6)::timestamp_ntz(6)  as event_ts,   -- Debezium: epoch microseconds
        RECORD_CONTENT:after:customer_id::int                         as customer_id,
        RECORD_CONTENT:after:product_id::int                          as product_id,
        RECORD_CONTENT:after:campaign_id::int                         as campaign_id,
        RECORD_CONTENT:after:quantity::int                            as quantity,
        RECORD_CONTENT:after:unit_price::number(10, 2)                as unit_price,      -- NUMERIC arrives as a string (decimal.handling.mode=string)
        RECORD_CONTENT:after:unit_cost::number(10, 2)                 as unit_cost,
        RECORD_CONTENT:after:discount_pct::number(4, 2)               as discount_pct,
        RECORD_CONTENT:after:gross_amount::number(12, 2)              as gross_amount,
        RECORD_CONTENT:after:net_amount::number(12, 2)                as net_amount,
        RECORD_CONTENT:after:margin_amount::number(12, 2)             as margin_amount,
        RECORD_CONTENT:after:currency::string                         as currency,
        RECORD_CONTENT:after:payment_method::string                   as payment_method,
        RECORD_CONTENT:after:channel::string                          as channel,
        RECORD_CONTENT:after:status::string                           as status
    from {{ relation }}
    where RECORD_CONTENT:after is not null                            -- deletes (after = null) are not generated
{%- endmacro %}

{#-
  Current state: the latest event per transaction. Newest LSN wins; Kafka offset breaks ties, which also
  removes Debezium's at-least-once duplicates (same LSN, same content).
  `where`: optional filter applied before picking (the real-time path keeps 7 days).
-#}
{% macro latest_per_transaction(events, where=none) -%}
    select *
    from {{ events }}
    {% if where %}where {{ where }}{% endif %}
    qualify row_number() over (partition by transaction_id order by lsn desc, kafka_offset desc) = 1
{%- endmacro %}

{#- Gold: add the customer tier and the product type. Source tiers silver / bronze become 'standard'. -#}
{% macro enrich_transactions(transactions) -%}
    select
        t.transaction_id,
        t.event_ts,
        t.status,
        t.customer_id,
        case when c.tier in ('platinum', 'gold') then c.tier
             when c.tier is not null then 'standard'
        end                                                           as customer_tier,
        t.product_id,
        p.category                                                    as product_type,
        p.product_name,
        t.campaign_id,
        t.quantity,
        t.unit_price,
        t.discount_pct,
        t.gross_amount,
        t.net_amount,
        t.margin_amount,
        t.currency,
        t.payment_method,
        t.channel,
        t.lsn,
        t.kafka_offset,
        t.committed_at
    from {{ transactions }} t
    left join {{ ref('customer') }} c on c.customer_id = t.customer_id
    left join {{ ref('product') }} p on p.product_id = t.product_id
{%- endmacro %}
