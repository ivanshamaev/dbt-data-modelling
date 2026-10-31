{{ config(
    materialized='view',
    schema='iceberg.inmon_marts',
    tags=['inmon', 'mart'],
) }}

{# M4.4 · dm_promo_effect: KPI №13 из 3NF — кросс-источниковая стыковка #}
{# order_no ↔ CRM (паттерн №10) на входе зависимой витрины Inmon. #}
{# L32 (fan-out, пойман R4 живым прогоном 2026-10-31): заказ в нескольких #}
{# промо (~2.25 в среднем) умножал выручку — участия дедуплируются до флага #}
{# «заказ промо» (та же механика, что t_order_promo в anchor). CRM-орфаны не создают ERP-продаж. #}
select
    case when p.order_no is not null then 'promo' else 'organic' end as order_type,
    count(distinct l.order_id)                                      as orders_cnt,
    sum(l.line_amount)                                              as revenue_amt
from {{ ref('int_order_lines') }} l
inner join {{ ref('int_orders') }} o
    on l.order_id = o.order_id
inner join {{ ref('int_order_states') }} os
    on
        l.order_id = os.order_id
        and os.is_current
left join (
    select distinct order_no
    from {{ ref('stg_in_crm__promo_participation') }}
) p
    on o.order_no = p.order_no
where
    l.is_current
    and os.status in ('paid', 'shipped', 'delivered', 'returned')
group by 1
