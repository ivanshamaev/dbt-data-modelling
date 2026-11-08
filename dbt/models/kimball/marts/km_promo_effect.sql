{{ config(
    materialized='view',
    tags=['kimball', 'mart'],
) }}

{# M5.5 · km_promo_effect: KPI №13 из звезды — конформность order_no → promo_key #}
{# уже сделана МОДЕЛЬЮ (obt_sales), витрина только группирует. Сравнить с #}
{# im_promo_effect (vault: l_order_promo) и agg_anc_promo_effect (anchor: tie_order_promo): #}
{# одна и та же бизнес-стыковка, три разных механизма интеграции источников. #}
select
    case when promo_key is not null then 'promo' else 'organic' end as order_type,
    count(distinct order_id)                                       as orders_cnt,
    sum(line_amount)                                               as revenue_amt
from {{ ref('obt_sales') }}
group by 1
