-- L4.4 · бизнес-правило золота №3 (пороговая версия): платежи оплаченного заказа
-- в сумме равны total_amount.
-- РАСХОЖДЕНИЯ ЛЕГИТИМНЫ ПО ПОСТРОЕНИЮ (L26, живой прогон):
--   (а) ~180 ретро-правок (паттерн №3): платёж зафиксировал старую сумму;
--   (б) ~19K заказов, перешедших в paid ПОСЛЕ дня создания: simulate_day
--       генерирует платежи только для нового окна заказов, междневные
--       переходы остаются без платежей (генераторная реальность).
-- Итого ~4.3% — порог 6%. («заведомо плохие данные не красят build» — §4)
with totals as (
    select
        o.order_id,
        o.total_amount,
        coalesce(sum(p.payment_amt), 0) as payments_sum
    from {{ ref('stg_kim_erp__orders') }} o
    left join {{ ref('fact_payments') }} p on o.order_no = p.order_no
    where o.paid_at is not null
    group by 1, 2
)

select
    round(count(*) / nullif((select count(*) from totals), 0), 4) as mismatch_share,
    count(*) as mismatch_cnt
from totals
where total_amount <> payments_sum
having count(*) / nullif((select count(*) from totals), 0) > 0.06
