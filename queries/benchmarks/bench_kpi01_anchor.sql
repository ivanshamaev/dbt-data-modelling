# kpi01 из anchor — версия для бенчмарка (день × канал, фрагмент ядра).
SET CATALOG iceberg;
USE anchor_core;

select
    cast(wv_o.order_ts as date)   as sales_date,
    wv_o.channel,
    count(distinct wv_o.order_id) as orders_cnt,
    sum(wv_l.line_amount)         as revenue_amt
from wv_order_line wv_l
join wv_order wv_o on wv_o.order_id = wv_l.order_id
where wv_o.status in ('paid', 'shipped', 'delivered', 'returned')
group by 1, 2;
