{{ config(
    materialized='incremental',
    schema='iceberg.med_bronze',
    incremental_strategy='default',
    partition_by=['_ingest_date'],
    partition_type='Expr',
) }}

-- L3.2 · brz_erp__payments: платежи; сплиты ~7%, возвраты меняют status/refunded_amount/refunded_at
-- с бампом updated_at (паттерн №9).
-- L53: сохраняем каждую наблюдённую версию; повтор не меняет её время загрузки.
with incoming as (
    select
        payment_id,
        order_id,
        paid_ts,
        method,
        amount,
        status,
        refunded_amount,
        refunded_at,
        updated_at,
        {{ bronze_tech('erp', 'updated_at') }}
    from {{ source('erp_pg', 'payments') }}
    {{ bronze_lookback('updated_at') }}
)

select
    s.payment_id,
    s.order_id,
    s.paid_ts,
    s.method,
    s.amount,
    s.status,
    s.refunded_amount,
    s.refunded_at,
    s.updated_at,
    s._batch_id,
    s._loaded_at,
    s._source,
    s._ingest_date
from incoming s
{{ bronze_new_versions([
    'payment_id',
    'order_id',
    'paid_ts',
    'method',
    'amount',
    'status',
    'refunded_amount',
    'refunded_at',
    'updated_at'
]) }}
