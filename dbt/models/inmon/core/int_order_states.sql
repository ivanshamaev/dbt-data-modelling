{{ config(
    materialized='table',
    schema='iceberg.inmon_core',
) }}

{# L4.1 · история состояний заказа (паттерны №2 и №3): статусный трек #}
{# created→paid→shipped→delivered (+ cancelled/returned) и версии total_amount. #}
{# Каждая bronze-версия = снимок мутирующих полей на момент updated_at; #}
{# KPI №4 (время между этапами) отвечает прямо отсюда — таймстемпы этапов #}
{# проставляются в момент перехода. #}
with deduped as (
    select
        order_id,
        status,
        total_amount,
        paid_at,
        shipped_at,
        delivered_at,
        cancelled_at,
        updated_at,
        row_number() over (
            partition by order_id, updated_at
            order by _loaded_at desc
        ) as rn
    from {{ ref('raw_erp__orders') }}
),

real_changes as (
    select
        order_id,
        status,
        total_amount,
        paid_at,
        shipped_at,
        delivered_at,
        cancelled_at,
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
        status,
        total_amount,
        paid_at,
        shipped_at,
        delivered_at,
        cancelled_at,
        updated_at
    from real_changes
    where prev_signature is null or signature <> prev_signature
),

with_validity as (
    select
        order_id,
        status,
        total_amount,
        paid_at,
        shipped_at,
        delivered_at,
        cancelled_at,
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
    status,
    total_amount,
    paid_at,
    shipped_at,
    delivered_at,
    cancelled_at,
    updated_at as valid_from,
    valid_to,
    is_current
from with_validity
