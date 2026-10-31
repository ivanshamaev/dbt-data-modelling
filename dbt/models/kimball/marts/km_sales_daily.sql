{{ config(
    materialized='view',
    tags=['kimball', 'mart'],
) }}

{# M5.5 · km_sales_daily: каноническая витрина каталога из ЗВЕЗДЫ. #}
{# Kimball-механика: фактоцентричная агрегация fct_sales (статусный фильтр #}
{# уже выполнен при сборке факта — где живёт «правда» о статусе, звезда и #}
{# витрина отвечают по-разному: контраст с dm_/im_/am_/gld_ в лекции M5.5). #}
select
    f.order_date             as sales_date,
    f.channel,
    count(distinct f.order_id) as orders_cnt,
    sum(f.line_amount)       as revenue_amt
from {{ ref('fct_sales') }} f
group by 1, 2
