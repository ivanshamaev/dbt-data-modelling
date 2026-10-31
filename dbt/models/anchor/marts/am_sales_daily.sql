{{ config(
    materialized='view',
    schema='iceberg.anchor_marts',
    tags=['anchor', 'mart'],
) }}

{# M7.4 · am_sales_daily: каноническая витрина каталога из 6NF-ядра. #}
{# Anchor-механика: wide view (генерируется anchor_view-макросом) даёт классическую #}
{# форму заказа; зерно каталога день × канал. Семантика выручки — общая: #}
{# is-current-верование, paid+. Сверка R4 против dm_/km_/im_/gld_. #}
select
    cast(wv_o.order_ts as date)   as sales_date,
    wv_o.channel,
    count(distinct wv_o.order_id) as orders_cnt,
    sum(wv_l.line_amount)         as revenue_amt
from {{ ref('wv_order_line') }} wv_l
inner join {{ ref('wv_order') }} wv_o
    on wv_l.order_id = wv_o.order_id
where wv_o.status in ('paid', 'shipped', 'delivered', 'returned')
group by 1, 2
