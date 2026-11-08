{{ config(
    materialized='view',
    schema='iceberg.anchor_marts',
    tags=['anchor', 'mart'],
) }}

{# M7.4 · agg_anc_promo_effect: KPI №13 из 6NF — участие заказа в промо это tie #}
{# tie_order_promo (отдельная таблица связи «многие-ко-многим»); #}
{# витрина отличает promo от organic наличием связи. Механику сравнить с #}
{# km_ (obt: конформный ключ в широкой таблице) и im_ (l_order_promo). #}
select
    case when tp.order_id is not null then 'promo' else 'organic' end as order_type,
    count(distinct o.order_id)                                    as orders_cnt,
    sum(ol.line_amount)                                            as revenue_amt
from {{ ref('latest_anc_order_line') }} ol
inner join {{ ref('latest_anc_order') }} o
    on o.order_id = ol.order_id
left join (
    select distinct order_id
    from {{ ref('tie_order_promo') }}
) tp
    on tp.order_id = o.order_id
where o.status in ('paid', 'shipped', 'delivered', 'returned')
group by 1
