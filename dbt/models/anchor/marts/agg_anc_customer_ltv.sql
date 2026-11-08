{{ config(
    materialized='view',
    schema='iceberg.anchor_marts',
    tags=['anchor', 'mart'],
) }}

{# M7.4 · agg_anc_customer_ltv: KPI №7 из 6NF — valid-time срез attr_customer_segment #}
{# на дату заказа (tie tie_customer_order связывает заказ с клиентом). #}
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
    from {{ ref('attr_customer_segment') }} c
    inner join {{ ref('knot_segment') }} k
        on c.value = k.knot_id
    where c.superseded_time is null
)

select
    seg.segment,
    count(distinct tco.customer_id) as customers_cnt,
    count(distinct o.order_id)   as orders_cnt,
    sum(ol.line_amount)           as ltv_amt
from {{ ref('latest_anc_order_line') }} ol
inner join {{ ref('latest_anc_order') }} o
    on ol.order_id = o.order_id
inner join {{ ref('tie_customer_order') }} tco
    on o.order_id = tco.order_id
inner join segments seg
    on
        tco.customer_id = seg.customer_id
        and seg.valid_from <= cast(o.order_ts as date)
        and (seg.valid_to is null or seg.valid_to > cast(o.order_ts as date))
where o.status in ('paid', 'shipped', 'delivered', 'returned')
group by 1
