{{ config(
    materialized='table',
    table_type='DUPLICATE',
    keys=['paid_date', 'payment_id'],
    distributed_by=['payment_id'],
    partition_by=['paid_date'] if target.name == 'iceberg_gold' else ['date_trunc("day", paid_date)'],
    partition_type='Expr',
    tags=['gold', 'fact'],
) }}

-- L4.4 · fact_payments (паттерн №9): своя гранулярность — ПЛАТЕЖ.
-- Сплиты card+gift = две строки (генератор: ~7% заказов, детерминировано
-- order_id % 100 < 7); refund-переходы входят в полную реконструкцию факта.
-- Инвариант источника (L2.2): сумма платежей оплаченного заказа = total_amount
-- — проверяется singular-тестом star_payments_match_orders.
select
    cast(p.paid_ts as date) as paid_date,
    p.payment_id,
    o.order_key,
    o.order_no,                        -- degenerate dimension
    p.method,
    p.amount                as payment_amt,
    p.status                as payment_status,
    p.refunded_at,
    p.paid_ts,
    p.updated_at            as payment_updated_at
from {{ ref('stg_kim_erp__payments') }} p
inner join {{ ref('stg_kim_erp__orders') }} o
    on p.order_id = o.order_id
