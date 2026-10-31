-- KPI 13 · Сравнение выручки и AOV заказов с промо и без; причинный эффект не измеряется,
-- по механикам скидок (кросс-источниковый join erp × crm, паттерн №10 —
-- диагностический отчёт; точную сверку обеспечивают отдельные гейты). Считаем из obt_sales, где конформность
-- order_no → promo_key уже сделана МОДЕЛЬЮ (не инфраструктурой).
SET CATALOG default_catalog;
USE analytics;

with flagged as (
    select
        order_id,
        order_date,
        case when promo_key is not null then 'promo' else 'organic' end as order_type,
        coalesce(promo_mechanics, 'none')                               as mechanics,
        line_amount
    from obt_sales
)
select
    mechanics,
    order_type,
    count(distinct order_id) as orders_cnt,
    sum(line_amount)         as revenue_amt,
    sum(line_amount) / count(distinct order_id) as aov_amt
from flagged
group by 1, 2
order by 1, 2;
