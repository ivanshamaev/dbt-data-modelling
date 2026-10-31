-- KPI 3 · Средний чек (AOV) по каналам (гранулярность заказа против строки).
SET CATALOG default_catalog;
USE analytics;

select
    channel,
    count(distinct order_id)          as orders_cnt,
    sum(line_amount)                  as revenue_amt,
    sum(line_amount) / count(distinct order_id) as aov_amt
from fct_sales
group by 1
order by aov_amt desc;
