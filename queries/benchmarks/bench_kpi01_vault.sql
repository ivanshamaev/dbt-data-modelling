# kpi01 из vault — версия для бенчмарка (im_sales_daily уже агрегирован по дням;
# для честного сравнения с другими ядрами считаем сырую выручку поверх звеньев).
SET CATALOG iceberg;
USE vault_core;

select
    cast(ol.order_ts as date) as sales_date,
    ls.store_hk,
    count(distinct ol.order_hk) as orders_cnt,
    sum(ol.line_amount)         as revenue_amt
from (select * from (select ol.*, row_number() over (partition by order_line_hk order by line_updated_at desc, load_date desc) as rn from l_order_line ol) x where rn = 1) ol
join l_order_store ls on ls.order_hk = ol.order_hk
join b_order_effective_state oes on oes.order_hk = ol.order_hk
where oes.status in ('paid', 'shipped', 'delivered', 'returned')
group by 1, 2;
