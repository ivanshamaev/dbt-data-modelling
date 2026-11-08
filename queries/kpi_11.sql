-- KPI 11 · Выручка по регионам магазина и региону клиента (два разных измерения географии).
SET CATALOG default_catalog;
USE analytics;

select
    s.region  as store_region,
    c.region  as customer_region,
    sum(f.line_amount) as revenue_amt
from fact_sales f
join dim_store   s on s.store_key    = f.store_key
join dim_customer c on c.customer_sk_v = f.customer_sk_v
group by 1, 2
order by revenue_amt desc;
