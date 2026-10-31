-- Число различных заказов по дню создания; версии не считаются новыми заказами.
-- Идемпотентность доставки проверяется отдельно по ключам версий и сценарием повтора.
select
    cast(order_ts as date) as order_date,
    count(distinct order_id) as n
from {{ ref('raw_erp__orders') }}
group by 1
having count(distinct order_id) < 5 or count(distinct order_id) > 2000
