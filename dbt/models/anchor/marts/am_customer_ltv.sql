{{ config(
    materialized='view',
    schema='iceberg.anchor_marts',
    tags=['anchor', 'mart'],
) }}

{# M7.4 · am_customer_ltv: KPI №7 из 6NF — valid-time срез ac_customer_segment #}
{# на дату заказа (tie t_customer_order связывает заказ с клиентом). #}
{# Берётся последняя известная интерпретация каждого бизнес-дня; интервалы #}
{# вычисляются в запросе. Таблица атрибута полностью восстанавливается из bronze. #}
with segments as (
    select
        c.customer_id,
        k.value        as segment,
        c.valid_from,
        lead(c.valid_from) over (
            partition by c.customer_id
            order by c.valid_from
        ) as valid_to
    from {{ ref('ac_customer_segment') }} c
    inner join {{ ref('kn_segment') }} k
        on c.value = k.knot_id
    where c.superseded_time is null
)

select
    seg.segment,
    count(distinct tco.customer_id) as customers_cnt,
    count(distinct wv_o.order_id)   as orders_cnt,
    sum(wv_l.line_amount)           as ltv_amt
from {{ ref('wv_order_line') }} wv_l
inner join {{ ref('wv_order') }} wv_o
    on wv_l.order_id = wv_o.order_id
inner join {{ ref('t_customer_order') }} tco
    on wv_o.order_id = tco.order_id
inner join segments seg
    on
        tco.customer_id = seg.customer_id
        and seg.valid_from <= cast(wv_o.order_ts as date)
        and (seg.valid_to is null or seg.valid_to > cast(wv_o.order_ts as date))
where wv_o.status in ('paid', 'shipped', 'delivered', 'returned')
group by 1
