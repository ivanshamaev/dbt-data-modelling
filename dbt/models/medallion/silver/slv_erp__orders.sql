{{ config(
    materialized='table',
    schema='iceberg.med_silver',
    tags=['medallion', 'med_silver'],
) }}

{# M8.2 · slv_erp__orders: silver-сущность «заказ» контура medallion — #}
{# ВЕРСИОНИРОВАННАЯ (в отличие от staging-снимков ядер): трек наблюдённых статусов #}
{# и сумм (паттерны №2/№3), развёрнутый из med_bronze. Контракт silver: #}
{# «последний payload на updated_at, интервалы наблюдённых изменений» — #}
{# историю разворачивает silver, а не ядро методологии (контраст с inmon_core). #}
{# Постоянные при рождении поля (order_no/customer_id/store_id/channel/order_ts) #}
{# переносятся в каждую версию — silver остаётся entity-shaped, без 3NF-расщепления. #}
with deduped as (
    select
        order_id,
        order_no,
        customer_id,
        store_id,
        channel,
        status,
        total_amount,
        paid_at,
        shipped_at,
        delivered_at,
        cancelled_at,
        order_ts,
        updated_at,
        row_number() over (
            partition by order_id, updated_at
            order by _loaded_at desc
        ) as rn
    from {{ ref('brz_erp__orders') }}
),

real_changes as (
    select
        order_id,
        order_no,
        customer_id,
        store_id,
        channel,
        status,
        total_amount,
        paid_at,
        shipped_at,
        delivered_at,
        cancelled_at,
        order_ts,
        updated_at,
        concat_ws(
            '~',
            coalesce(cast(status as varchar), '-'),
            coalesce(cast(total_amount as varchar), '-'),
            coalesce(cast(paid_at as varchar), '-'),
            coalesce(cast(shipped_at as varchar), '-'),
            coalesce(cast(delivered_at as varchar), '-'),
            coalesce(cast(cancelled_at as varchar), '-')
        )     as signature,
        lag(concat_ws(
            '~',
            coalesce(cast(status as varchar), '-'),
            coalesce(cast(total_amount as varchar), '-'),
            coalesce(cast(paid_at as varchar), '-'),
            coalesce(cast(shipped_at as varchar), '-'),
            coalesce(cast(delivered_at as varchar), '-'),
            coalesce(cast(cancelled_at as varchar), '-')
        ))
            over (
                partition by order_id
                order by updated_at
            ) as prev_signature
    from deduped
    where rn = 1
),

changes_only as (
    select
        order_id,
        order_no,
        customer_id,
        store_id,
        channel,
        status,
        total_amount,
        paid_at,
        shipped_at,
        delivered_at,
        cancelled_at,
        order_ts,
        updated_at
    from real_changes
    where prev_signature is null or signature <> prev_signature
),

with_validity as (
    select
        order_id,
        order_no,
        customer_id,
        store_id,
        channel,
        status,
        total_amount,
        paid_at,
        shipped_at,
        delivered_at,
        cancelled_at,
        order_ts,
        updated_at,
        lead(updated_at) over (
            partition by order_id
            order by updated_at
        )     as valid_to,
        row_number() over (
            partition by order_id
            order by updated_at desc
        ) = 1 as is_current
    from changes_only
)

select
    order_id,
    order_no,
    customer_id,
    store_id,
    channel,
    status,
    total_amount,
    paid_at,
    shipped_at,
    delivered_at,
    cancelled_at,
    order_ts,
    updated_at as valid_from,
    valid_to,
    is_current
from with_validity
