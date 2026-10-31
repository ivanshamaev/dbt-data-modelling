-- L4.4 · бизнес-правило золота №2: сумма строк факта = total_amount заказа
-- (по актуальным версиям, в статусах выручки) — сверка факта со шапкой заказа.
select
    f.order_id,
    max(f.total_amount)  as order_total,
    sum(f.line_amount)   as lines_sum
from {{ ref('fct_sales') }} f
group by 1
having sum(f.line_amount) <> max(f.total_amount)
