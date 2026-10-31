{{ config(
    materialized='table',
    schema='iceberg.kimball_stage',
) }}

{# L4.3 · заказы: актуальная версия (переходы статусов №2 и правки сумм №3 #}
{# схлопываются в текущее состояние; историю версий держит bronze). #}
{# order_no — бизнес-номер: degenerate dimension в звезде и ключ стыковки #}
{# с CRM (паттерн №10); order_key — durable SK идентичности заказа. #}
with ranked as (
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
        _batch_id,
        _loaded_at,
        _source,
        _ingest_date,
        row_number() over (
            partition by order_id
            order by updated_at desc, _loaded_at desc
        ) as rn
    from {{ ref('raw_erp__orders') }}
)

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
    {{ hash_key('order_id') }} as order_key
from ranked
where rn = 1
