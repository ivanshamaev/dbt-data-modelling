{{ config(
    materialized='view',
    schema='iceberg.anchor_marts',
    tags=['anchor', 'mart'],
) }}

{# M7.4 · agg_anc_sales_daily: каноническая витрина каталога из 6NF-ядра. #}
{# Anchor-механика: wide view (генерируется anchor_view-макросом) даёт классическую #}
{# форму заказа; зерно каталога день × канал. Семантика выручки — общая: #}
{# is-current-верование, paid+. Сверка R4 против dm_/km_/im_/gld_. #}
select
    cast(o.order_ts as date)   as sales_date,
    o.channel,
    count(distinct o.order_id) as orders_cnt,
    sum(ol.line_amount)         as revenue_amt
from {{ ref('latest_anc_order_line') }} ol
inner join {{ ref('latest_anc_order') }} o
    on ol.order_id = o.order_id
where o.status in ('paid', 'shipped', 'delivered', 'returned')
group by 1, 2
