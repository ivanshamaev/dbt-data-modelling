-- KPI 7 · ГЛАВНЫЙ ВОПРОС-МАРКЕР: LTV по сегментам, сегмент по последнему известному состоянию ДНЯ ЗАКАЗА
-- (паттерн №1). В звезде решается САМ JOIN'ом: fact_sales.customer_sk_v уже
-- указывает на версию сегмента, действовавшую в день заказа (SK-разводка
-- при сборке факта). Тот же вопрос в PIT-механике — vault (гл. 10), в
-- valid-time — Anchor (гл. 11); три SQL бок-о-бок — гл. 14.
SET CATALOG default_catalog;
USE analytics;

select
    c.segment,
    count(distinct f.order_id) as orders_cnt,
    sum(f.line_amount)         as ltv_amt,
    sum(f.line_amount) / count(distinct f.customer_id) as ltv_per_customer
from fact_sales f
join dim_customer c on c.customer_sk_v = f.customer_sk_v
group by 1
order by ltv_amt desc;
