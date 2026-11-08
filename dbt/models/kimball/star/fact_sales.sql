{{ config(
    materialized='table',
    table_type='DUPLICATE',
    keys=['order_date', 'order_id'],
    distributed_by=['order_id'],
    partition_by=['order_date'] if target.name == 'iceberg_gold' else ['date_trunc("day", order_date)'],
    partition_type='Expr',
    tags=['gold', 'fact'],
) }}

-- L4.4 · fact_sales: transaction fact на гранулярности СТРОКИ заказа (гл. 8).
--
-- СЕМАНТИКА ВЫРУЧКИ — зафиксирована в queries/kpi01_from_3nf.sql и ОБЯЗАНА
-- совпадать во всех пяти контурах: is_current-версии, статусы заказа
-- paid/shipped/delivered/returned (created/cancelled исключены; возвраты —
-- отдельный факт, net = gross − refunds).
--
-- SK-разводка (сердце KPI №7): customer_sk_v и product_sk_v = версии
-- измерений, ДЕЙСТВУЮЩИЕ на дату заказа (valid_time join) — «последнее известное состояние сегмента/категории
-- в день заказа» решаются ключом, без оконных функций на лету.
--
-- L54: полный пересчёт учебного факта; старая дата, смена статуса и пустой
-- день учитываются без частичной перезаписи. Цена — полный скан источника.

with orders as (
    select
        order_id,
        order_key,
        order_no,
        customer_id,
        store_id,
        channel,
        status,
        order_ts,
        total_amount,
        updated_at
    from {{ ref('stg_kim_erp__orders') }}

)

select
    cast(o.order_ts as date) as order_date,
    o.order_id,
    o.order_key,
    l.order_line_key,
    o.order_no,                                    -- degenerate dimension
    o.customer_id,
    {% if target.name == 'iceberg_gold' %}
    dc.customer_key as customer_sk_v,               -- durable-SK (без версии): см. L38
    {% else %}
        dc.customer_sk_v,                              -- сегмент на конец дня заказа (№1)
    {% endif %}
    l.product_id,
    {% if target.name == 'iceberg_gold' %}
    dp.product_key as product_sk_v,                 -- durable-SK (без версии): см. L38
    {% else %}
        dp.product_sk_v,                               -- категория на день заказа (№5)
    {% endif %}
    s.store_key,
    o.channel,
    l.qty,
    l.unit_price,
    l.discount_pct,
    l.line_amount,
    o.total_amount,                                -- для теста «сумма строк = тотал»
    o.status                 as order_status,
    o.updated_at             as order_updated_at
from orders o
inner join {{ ref('stg_kim_erp__order_lines') }} l
    on l.order_id = o.order_id
{% if target.name == 'iceberg_gold' %}
{#- L38 (gold-on-iceberg): SCD2-версии dim_customer/dim_product живут в internal
    PRIMARY KEY-механике (H12) и в external НЕ собираются — здесь факт строится
    на durable-SK (hash business-ключа, без версии). Главный тезис гл. 13:
    переносимость кончается там, где просвечивает механика платформы —
    «хочешь Iceberg — меняй механику, а не только каталог». -#}
join {{ ref('stg_kim_erp__customers') }} dc
    on dc.customer_id = o.customer_id
join {{ ref('stg_kim_erp__products') }} dp
    on dp.product_id = l.product_id
{% else %}
    inner join {{ ref('dim_customer') }} dc
        on
            dc.customer_id = o.customer_id
            and dc.valid_from <= cast(o.order_ts as date)
            and (dc.valid_to is null or dc.valid_to > cast(o.order_ts as date))
    inner join {{ ref('dim_product') }} dp
        on
            dp.product_id = l.product_id
            and dp.valid_from <= cast(o.order_ts as date)
            and (dp.valid_to is null or dp.valid_to > cast(o.order_ts as date))
{% endif %}
inner join {{ ref('dim_store') }} s
    on s.store_id = o.store_id
where o.status in ('paid', 'shipped', 'delivered', 'returned')
