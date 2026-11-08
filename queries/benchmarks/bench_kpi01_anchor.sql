# kpi01 из anchor — версия для бенчмарка (день × канал, фрагмент ядра).
SET CATALOG iceberg;
USE anchor_core;

select
    cast(o.order_ts as date)   as sales_date,
    o.channel,
    count(distinct o.order_id) as orders_cnt,
    sum(ol.line_amount)         as revenue_amt
from latest_anc_order_line ol
join latest_anc_order o on o.order_id = ol.order_id
where o.status in ('paid', 'shipped', 'delivered', 'returned')
group by 1, 2;
