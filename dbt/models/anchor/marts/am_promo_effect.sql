{{ config(
    materialized='view',
    schema='iceberg.anchor_marts',
    tags=['anchor', 'mart'],
) }}

{# M7.4 · am_promo_effect: KPI №13 из 6NF — участие заказа в промо это tie #}
{# t_order_promo (отдельная таблица связи «многие-ко-многим»); #}
{# витрина отличает promo от organic наличием связи. Механику сравнить с #}
{# km_ (obt: конформный ключ в широкой таблице) и im_ (l_order_promo). #}
select
    case when tp.order_id is not null then 'promo' else 'organic' end as order_type,
    count(distinct wv_o.order_id)                                    as orders_cnt,
    sum(wv_l.line_amount)                                            as revenue_amt
from {{ ref('wv_order_line') }} wv_l
inner join {{ ref('wv_order') }} wv_o
    on wv_o.order_id = wv_l.order_id
left join (
    select distinct order_id
    from {{ ref('t_order_promo') }}
) tp
    on tp.order_id = wv_o.order_id
where wv_o.status in ('paid', 'shipped', 'delivered', 'returned')
group by 1
