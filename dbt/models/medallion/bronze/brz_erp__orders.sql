{{ config(
    materialized='incremental',
    schema='iceberg.med_bronze',
    incremental_strategy='default',
    partition_by=['_ingest_date'],
    partition_type='Expr',
) }}

-- L3.2 · brz_erp__orders: заказы — главный факт-источник.
-- Watermark: updated_at ловит и переходы статусов (№2), и ретро-правки total_amount (№3),
-- и late-arriving (№7: updated_at опоздавшего заказа = дата события, попадает в окно lookback).
-- order_no сохраняется как бизнес-номер — будущий degenerate dimension и ключ стыковки с CRM.
-- L53: сохраняем каждую наблюдённую версию; повтор не меняет её время загрузки.
with incoming as (
    select
        order_id,
        order_no,
        customer_id,
        store_id,
        channel,
        status,
        order_ts,
        paid_at,
        shipped_at,
        delivered_at,
        cancelled_at,
        total_amount,
        updated_at,
        {{ bronze_tech('erp', 'updated_at') }}
    from {{ source('erp_pg', 'orders') }}
    {{ bronze_lookback('updated_at') }}
)

select
    s.order_id,
    s.order_no,
    s.customer_id,
    s.store_id,
    s.channel,
    s.status,
    s.order_ts,
    s.paid_at,
    s.shipped_at,
    s.delivered_at,
    s.cancelled_at,
    s.total_amount,
    s.updated_at,
    s._batch_id,
    s._loaded_at,
    s._source,
    s._ingest_date
from incoming s
{{ bronze_new_versions([
    'order_id',
    'order_no',
    'customer_id',
    'store_id',
    'channel',
    'status',
    'order_ts',
    'paid_at',
    'shipped_at',
    'delivered_at',
    'cancelled_at',
    'total_amount',
    'updated_at'
]) }}
