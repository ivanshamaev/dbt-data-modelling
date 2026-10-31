# kpi13 из vault — версия для бенчмарка (день × promo/organic, как в звёздном obt-запросе).
SET CATALOG iceberg;
USE vault_core;

with orders_rev as (
    select ol.order_hk, cast(ol.order_ts as date) as d, ol.line_amount
    from (select * from (select ol.*, row_number() over (partition by order_line_hk order by line_updated_at desc, load_date desc) as rn from l_order_line ol) x where rn = 1) ol
    join b_order_effective_state oes on oes.order_hk = ol.order_hk
    where oes.status in ('paid', 'shipped', 'delivered', 'returned')
),
promo_orders as (
    select distinct order_hk from l_order_promo
)
select
    d,
    case when po.order_hk is not null then 'promo' else 'organic' end as order_type,
    count(distinct r.order_hk) as orders_cnt,
    sum(r.line_amount)         as revenue_amt
from orders_rev r
left join promo_orders po on po.order_hk = r.order_hk
group by 1, 2;
