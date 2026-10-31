{{ config(
    materialized='view',
    schema='iceberg.med_gold',
    tags=['medallion', 'med_gold'],
) }}

{# M8.2 · gld_sales_daily: каноническая витрина каталога из medallion-контура. #}
{# Medallion-механика: gold читает ТОЛЬКО silver (контракт слоя) — актуальные #}
{# версии сущностей из истории silver. Gold применяет контракт продаж; те же цифры, что у #}
{# dm_/km_/im_/am_ (R4): один смысл — пять конвейеров. #}
select
    cast(o.order_ts as date)   as sales_date,
    o.channel,
    count(distinct l.order_id) as orders_cnt,
    sum(l.line_amount)         as revenue_amt
from {{ ref('slv_erp__order_lines') }} l
inner join {{ ref('slv_erp__orders') }} o
    on
        l.order_id = o.order_id
        and o.is_current
where
    l.is_current
    and o.status in ('paid', 'shipped', 'delivered', 'returned')
group by 1, 2
