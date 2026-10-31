-- KPI 12 · Последняя доступная дата против даты семью днями раньше.
-- Диагностический SELECT, не автоматический приёмный тест.
-- agg_sales_daily пересчитывается целиком; календарное «вчера» здесь не используется.
SET CATALOG default_catalog;
USE analytics;

select
    cur.sales_date,
    cur.store_id,
    cur.store_region,
    cur.channel,
    cur.revenue_amt                                    as latest_amt,
    prev.revenue_amt                                   as week_ago_amt,
    cur.revenue_amt - prev.revenue_amt                 as delta_amt,
    (cur.revenue_amt - prev.revenue_amt) / nullif(prev.revenue_amt, 0) as delta_pct
from agg_sales_daily cur
left join agg_sales_daily prev
    on prev.sales_date = date_sub(cur.sales_date, 7)
   and prev.store_key  = cur.store_key
   and prev.channel    = cur.channel
where cur.sales_date = (select max(sales_date) from agg_sales_daily)
order by delta_pct desc;
