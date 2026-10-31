{{ config(
    materialized='view',
    schema='iceberg.inmon_marts',
    tags=['inmon', 'mart'],
) }}

{# M4.4 · dm_sales_daily: каноническая витрина каталога (docs/design/mart_catalog.md). #}
{# Зерно: день × канал. Inmon-путь: зависимая витрина поверх нормализованного ядра — #}
{# два соединения: текущие позиции, идентичность заказа и его текущий статус. Смысл (paid+, #}
{# актуальные версии строк) — общий для всех контуров, сверяет R4. #}
select
    cast(o.order_ts as date)   as sales_date,
    o.channel,
    count(distinct l.order_id) as orders_cnt,
    sum(l.line_amount)         as revenue_amt
from {{ ref('int_order_lines') }} l
inner join {{ ref('int_orders') }} o
    on l.order_id = o.order_id
inner join {{ ref('int_order_states') }} os
    on
        l.order_id = os.order_id
        and os.is_current
where
    l.is_current
    and os.status in ('paid', 'shipped', 'delivered', 'returned')
group by 1, 2
