{{ config(
    materialized='view',
    schema='iceberg.vault_marts',
    tags=['vault', 'mart'],
) }}

{# M6.5 · im_promo_effect: каноническая витрина промо-эффективности — #}
{# свёртка im_promo (механика × тип) до зерна каталога (order_type). #}
{# Механика интеграции — l_order_promo: кросс-источниковый линк ERP × CRM #}
{# (приёмный тест мультиисточниковости KPI №13, паттерн №10). #}
select
    order_type,
    sum(orders_cnt)  as orders_cnt,
    sum(revenue_amt) as revenue_amt
from {{ ref('im_promo') }}
group by 1
