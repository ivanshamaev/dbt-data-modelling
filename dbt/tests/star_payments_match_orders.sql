-- Строгая сверка: чистая оплата = исправленная стоимость минус фактические возвраты.
with returns_by_order as (
    select
        l.order_id,
        sum(r.refund_amount) as returned_amt
    from {{ ref('stg_kim_erp__returns') }} r
    inner join {{ ref('stg_kim_erp__order_lines') }} l on r.order_line_id = l.order_line_id
    group by l.order_id
),

payments_by_order as (
    select
        order_no,
        sum(net_payment_amt) as paid_amt
    from {{ ref('fact_payments') }}
    group by order_no
)

select
    o.order_id,
    p.paid_amt,
    case when o.status = 'cancelled' then 0 else o.total_amount - coalesce(r.returned_amt, 0) end as expected_amt
from {{ ref('stg_kim_erp__orders') }} o
left join returns_by_order r on o.order_id = r.order_id
left join payments_by_order p on o.order_no = p.order_no
where
    o.paid_at is not null
    and (
        p.paid_amt is null or p.paid_amt
        <> case when o.status = 'cancelled' then 0 else o.total_amount - coalesce(r.returned_amt, 0) end
    )
