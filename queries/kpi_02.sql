-- KPI 2 · Топ-10 товаров по выручке за квартал (иерархия категорий, денормализация;
-- фиксированный I квартал 2026 года; категория берётся из версии товара).
SET CATALOG default_catalog;
USE analytics;

select
    p.sku,
    p.brand,
    p.category_l1,
    p.category_l2,
    p.category_l3,
    sum(f.line_amount) as revenue_amt
from fact_sales f
join dim_product p on p.product_sk_v = f.product_sk_v
where f.order_date >= date '2026-01-01'
  and f.order_date <  date '2026-04-01'
group by 1, 2, 3, 4, 5
order by revenue_amt desc
limit 10;
