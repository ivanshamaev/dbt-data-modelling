{{ config(
    materialized='table',
    table_type='DUPLICATE',
    keys=['return_date', 'return_id'],
    distributed_by=['return_id'],
    partition_by=['return_date'] if target.name == 'iceberg_gold' else ['date_trunc("day", return_date)'],
    partition_type='Expr',
    tags=['gold', 'fact'],
) }}

-- L4.4 · fact_returns (паттерн №8): гранулярность — ВОЗВРАТ СТРОКИ, не заказ.
-- Частичные возвраты — своя семантика: qty ≤ qty строки, refund пропорционален.
-- Категория берётся НА МОМЕНТ ЗАКАЗА (товар куплен в той категории) — product_sk_v
-- из valid-time join по дате заказа, консистентно с fact_sales.
select
    cast(r.return_ts as date) as return_date,
    r.return_id,
    l.order_line_key,
    o.order_key,
    o.order_no,                        -- degenerate dimension
    l.product_id,
    dp.product_sk_v,                   -- категория на момент заказа (№5)
    s.store_key,
    r.qty                     as return_qty,
    l.qty                     as line_qty,
    r.reason,
    r.refund_amount           as refund_amt,
    r.return_ts,
    cast(o.order_ts as date)  as order_date
from {{ ref('stg_kim_erp__returns') }} r
inner join {{ ref('stg_kim_erp__order_lines') }} l
    on r.order_line_id = l.order_line_id
inner join {{ ref('stg_kim_erp__orders') }} o
    on l.order_id = o.order_id
inner join {{ ref('dim_product') }} dp
    on
        l.product_id = dp.product_id
        and dp.valid_from <= cast(o.order_ts as date)
        and (dp.valid_to is null or dp.valid_to > cast(o.order_ts as date))
inner join {{ ref('dim_store') }} s
    on o.store_id = s.store_id
