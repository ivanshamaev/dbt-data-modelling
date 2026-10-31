{{ config(
    materialized='view',
    schema='iceberg.vault_marts',
    tags=['vault', 'mart'],
) }}

{# M6.5 · im_sales_daily: каноническая витрина каталога из Raw Vault + BV. #}
{# Vault-механика: последняя версия транзакционного линка (L32b) join к #}
{# Business Vault (b_order_effective_state) — «эффективный» статус без окон #}
{# по спутникам. Зерно каталога: день × канал (channel — контекст события #}
{# на link, рядом с order_ts). Сверка R4 против dm_/km_/am_/gld_. #}
select
    cast(ol.order_ts as date)   as sales_date,
    ol.channel,
    count(distinct ol.order_hk) as orders_cnt,
    sum(ol.line_amount)         as revenue_amt
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
        channel,
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
            ol.channel,
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
group by 1, 2
