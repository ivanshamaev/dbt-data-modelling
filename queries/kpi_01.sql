-- KPI 1 · Выручка по дням × магазины × каналы; недельной группировки здесь нет.
SET CATALOG default_catalog;
USE analytics;

select
    f.order_date,
    s.store_id,
    s.region          as store_region,
    f.channel,
    count(distinct f.order_id) as orders_cnt,
    sum(f.line_amount)         as revenue_amt
from fct_sales f
join dim_store s on s.store_key = f.store_key
group by 1, 2, 3, 4
order by 1 desc, 2;
