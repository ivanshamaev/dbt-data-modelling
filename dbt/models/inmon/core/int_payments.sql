{{ config(
    materialized='table',
    schema='iceberg.inmon_core',
) }}

{# L4.1 · платежи: версии полного payload, включая сумму и время (паттерн №9). #}
{# Сплиты — отдельные строки платежей (своя гранулярность, будущий fact_payments). #}
with deduped as (
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
        row_number() over (
            partition by payment_id, updated_at
            order by _loaded_at desc
        ) as rn
    from {{ ref('raw_erp__payments') }}
),

real_changes as (
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
        concat_ws(
            '~',
            coalesce(cast(order_id as varchar), '-'),
            coalesce(cast(paid_ts as varchar), '-'),
            coalesce(cast(method as varchar), '-'),
            coalesce(cast(amount as varchar), '-'),
            coalesce(cast(status as varchar), '-'),
            coalesce(cast(refunded_amount as varchar), '-'),
            coalesce(cast(refunded_at as varchar), '-')
        )     as signature,
        lag(concat_ws(
            '~',
            coalesce(cast(order_id as varchar), '-'),
            coalesce(cast(paid_ts as varchar), '-'),
            coalesce(cast(method as varchar), '-'),
            coalesce(cast(amount as varchar), '-'),
            coalesce(cast(status as varchar), '-'),
            coalesce(cast(refunded_amount as varchar), '-'),
            coalesce(cast(refunded_at as varchar), '-')
        ))
            over (
                partition by payment_id
                order by updated_at
            ) as prev_signature
    from deduped
    where rn = 1
),

changes_only as (
    select
        payment_id,
        order_id,
        paid_ts,
        method,
        amount,
        status,
        refunded_amount,
        refunded_at,
        updated_at
    from real_changes
    where prev_signature is null or signature <> prev_signature
),

with_validity as (
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
        lead(updated_at) over (
            partition by payment_id
            order by updated_at
        )     as valid_to,
        row_number() over (
            partition by payment_id
            order by updated_at desc
        ) = 1 as is_current
    from changes_only
)

select
    payment_id,
    order_id,
    paid_ts,
    method,
    amount,
    status,
    refunded_amount,
    refunded_at,
    updated_at as valid_from,
    valid_to,
    is_current
from with_validity
