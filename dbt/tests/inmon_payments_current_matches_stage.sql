-- Актуальное состояние платежа должно учитывать коррекции каждого исходного поля.
with current_payments as (
    select payment_id, order_id, paid_ts, method, amount, status, refunded_at
    from {{ ref('int_payments') }}
    where is_current
)

select coalesce(p.payment_id, s.payment_id) as payment_id
from current_payments p
full outer join {{ ref('stg_in_erp__payments') }} s
    on p.payment_id = s.payment_id
where
    p.payment_id is null
    or s.payment_id is null
    or not (p.order_id <=> s.order_id)
    or not (p.paid_ts <=> s.paid_ts)
    or not (p.method <=> s.method)
    or not (p.amount <=> s.amount)
    or not (p.status <=> s.status)
    or not (p.refunded_at <=> s.refunded_at)
