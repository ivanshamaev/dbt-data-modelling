{{ config(
    materialized='view',
    schema='iceberg.med_gold',
    tags=['medallion', 'med_gold'],
) }}

{# M8.2 · gld_customer_ltv: KPI №7 из medallion — valid-time join к silver-версиям #}
{# сегментов (slv_erp__customers). Здесь это обязанность ЗАПРОСА gold: silver #}
{# хранит версии, но не «запекает» их в ключ (звезда) и не строит PIT (vault). #}
select
    a.segment,
    count(distinct o.customer_id) as customers_cnt,
    count(distinct l.order_id)    as orders_cnt,
    sum(l.line_amount)            as ltv_amt
from {{ ref('slv_erp__order_lines') }} l
inner join {{ ref('slv_erp__orders') }} o
    on
        l.order_id = o.order_id
        and o.is_current
inner join {{ ref('slv_erp__customers') }} a
    on
        o.customer_id = a.customer_id
        and a.valid_from <= cast(o.order_ts as date)
        and (a.valid_to is null or a.valid_to > cast(o.order_ts as date))
where
    l.is_current
    and o.status in ('paid', 'shipped', 'delivered', 'returned')
group by 1
