{{ config(
    materialized='table',
    table_type='DUPLICATE',
    keys=['sales_date', 'store_key', 'channel'],
    distributed_by=['store_key'],
    partition_by=['sales_date'] if target.name == 'iceberg_gold' else ['date_trunc("month", sales_date)'],
    partition_type='Expr',
    tags=['gold', 'agg'],
) }}

-- Дневной агрегат по магазину и каналу; полная реконструкция удаляет исчезнувшие группы.
-- KPI №12 сравнивает последнюю доступную дату с датой семью днями раньше.

select
    f.order_date               as sales_date,
    f.store_key,
    f.channel,
    s.store_id,
    s.region                   as store_region,
    count(distinct f.order_id) as orders_cnt,
    sum(f.qty)                 as items_qty,
    sum(f.line_amount)         as revenue_amt,
    max(f.order_updated_at)    as order_updated_at
from {{ ref('fact_sales') }} f
inner join {{ ref('dim_store') }} s on f.store_key = s.store_key

group by 1, 2, 3, 4, 5
