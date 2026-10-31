{{ config(materialized='table', schema='iceberg.vault_core', tags=['vault', 'bv']) }}

-- Текущее состояние: порядок версий и наблюдений, без искусственного ранга статусов.
with lifecycle as (
    select
        order_hk,
        status,
        paid_at,
        shipped_at,
        delivered_at,
        cancelled_at,
        effective_from,
        load_date,
        row_number() over (
            partition by order_hk
            order by effective_from desc, load_ts desc
        ) as rn
    from {{ ref('s_order_lifecycle') }}
),

amounts as (
    select
        order_hk,
        total_amount,
        effective_from,
        load_date,
        row_number() over (
            partition by order_hk
            order by effective_from desc, load_ts desc
        ) as rn
    from {{ ref('s_order_amounts') }}
)

select
    lc.order_hk,
    lc.status,
    lc.paid_at,
    lc.shipped_at,
    lc.delivered_at,
    lc.cancelled_at,
    am.total_amount,
    greatest(lc.effective_from, am.effective_from) as effective_from,
    greatest(lc.load_date, am.load_date) as load_date
from lifecycle lc
inner join amounts am on lc.order_hk = am.order_hk and am.rn = 1
where lc.rn = 1
