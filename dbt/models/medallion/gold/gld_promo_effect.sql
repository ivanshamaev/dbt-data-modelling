{{ config(
    materialized='view',
    schema='iceberg.med_gold',
    tags=['medallion', 'med_gold'],
) }}

{# M8.2 · gld_promo_effect: KPI №13 из medallion — кросс-источниковая стыковка #}
{# делается в gold-запросе: silver обеих систем (slv_erp__orders × #}
{# slv_crm__promo_participation) по order_no. L32 (fan-out, пойман R4): #}
{# участия дедуплируются до флага «заказ промо»; CRM-орфаны не создают ERP-продаж. #}
select
    case when p.order_no is not null then 'promo' else 'organic' end as order_type,
    count(distinct l.order_id)                                      as orders_cnt,
    sum(l.line_amount)                                              as revenue_amt
from {{ ref('slv_erp__order_lines') }} l
inner join {{ ref('slv_erp__orders') }} o
    on
        l.order_id = o.order_id
        and o.is_current
left join (
    select distinct order_no
    from {{ ref('slv_crm__promo_participation') }}
) p
    on o.order_no = p.order_no
where
    l.is_current
    and o.status in ('paid', 'shipped', 'delivered', 'returned')
group by 1
