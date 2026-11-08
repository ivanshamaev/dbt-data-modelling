{{ config(
    materialized='view',
    tags=['kimball', 'mart'],
) }}

{# M5.5 · km_customer_ltv: KPI №7 из звезды — ГЛАВНАЯ механика измерения: #}
{# fact_sales.customer_sk_v уже указывает на версию сегмента, действовавшую #}
{# в день заказа (SK-разводка при сборке факта). Никаких valid-time окон — #}
{# история «запечена» в ключ. Дешёвый join — плата: широкая dim и SK-дисциплина. #}
select
    c.segment,
    count(distinct f.customer_id) as customers_cnt,
    count(distinct f.order_id)    as orders_cnt,
    sum(f.line_amount)            as ltv_amt
from {{ ref('fact_sales') }} f
inner join {{ ref('dim_customer') }} c
    on c.customer_sk_v = f.customer_sk_v
group by 1
