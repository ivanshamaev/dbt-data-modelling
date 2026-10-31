{{ config(
    materialized='view',
    schema='iceberg.vault_marts',
    tags=['vault', 'mart'],
) }}

{# L5.3 · im_promo: KPI №13 ИЗ VAULT — кросс-источниковый join через l_order_promo #}
{# (приёмный тест мультиисточниковости): выручка/AOV заказов с промо против без. #}
{# Сравнить стоимость этого ответа в звезде (obt_sales) и здесь — материал гл. 14. #}
with orders_rev as (
    select
        ol.order_hk,
        ol.line_amount
    from (
        select
            order_line_hk,
            line_hash,
            order_hk,
            product_hk,
            order_line_id,
            qty,
            unit_price,
            discount_pct,
            line_amount,
            order_ts,
            line_updated_at,
            load_date,
            record_source
        from (
            select
                ol.order_line_hk,
                ol.line_hash,
                ol.order_hk,
                ol.product_hk,
                ol.order_line_id,
                ol.qty,
                ol.unit_price,
                ol.discount_pct,
                ol.line_amount,
                ol.order_ts,
                ol.line_updated_at,
                ol.load_date,
                ol.record_source,
                row_number() over (
                    partition by ol.order_line_hk
                    order by ol.line_updated_at desc, ol.load_date desc
                ) as rn
            from {{ ref('l_order_line') }} ol
        ) x
        where rn = 1
    ) ol
    inner join {{ ref('b_order_effective_state') }} oes
        on ol.order_hk = oes.order_hk
    where oes.status in ('paid', 'shipped', 'delivered', 'returned')
),

promo_orders as (
    {# L32 (fanout): заказ в нескольких промо умножал выручку (avg 2.25×);
       упрощение «один промо на заказ» оговорено — берём детерминированно min #}
    select
        order_hk,
        min(promo_hk) as promo_hk
    from {{ ref('l_order_promo') }}
    group by 1
),

promo_mech as (
    {# текущая механика промо: последняя версия спутника #}
    select
        promo_hk,
        mechanics
    from (
        select
            promo_hk,
            mechanics,
            row_number() over (
                partition by promo_hk
                order by effective_from desc, load_ts desc
            ) as rn
        from {{ ref('s_promo_crm') }}
    ) x
    where rn = 1
)

select
    coalesce(pm.mechanics, 'none')                                    as mechanics,
    case when po.order_hk is not null then 'promo' else 'organic' end as order_type,
    count(distinct r.order_hk)                                        as orders_cnt,
    sum(r.line_amount)                                                as revenue_amt,
    sum(r.line_amount) / count(distinct r.order_hk)                   as aov_amt
from orders_rev r
left join promo_orders po on r.order_hk = po.order_hk
left join promo_mech pm on po.promo_hk = pm.promo_hk
group by 1, 2
