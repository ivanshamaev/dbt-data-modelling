{{ config(
    materialized='table',
    table_type='DUPLICATE',
    keys=['order_date', 'order_id'],
    distributed_by=['order_id'],
    partition_by=['order_date'] if target.name == 'iceberg_gold' else ['date_trunc("day", order_date)'],
    partition_type='Expr',
    tags=['gold', 'obt'],
) }}

-- L4.4 · obt_sales: One Big Table — паттерн ПОДАЧИ (гл. 7), не отдельная модель
-- данных: fact_sales + денормализованные атрибуты измерений для фиксированных
-- дашбордов и «одного прохода скана». Когда звезда избыточна, а когда вредна —
-- текст гл. 7–8; сравнение планов запроса — артефакт гл. 14.
--
-- Промо-атрибуты (KPI №13): LEFT JOIN participation × dim_promo по order_no —
-- кросс-источниковая конформность В МОДЕЛИ (паттерн №10). Орфаны CRM сюда
-- НЕ попадают (inner join participation→promotions внутри подзапроса),
-- их доля ограничена тестом в staging — правило «заведомо плохие данные
-- не красят канонический build» (§4).
-- Упрощение «один промо на заказ» (min promo_key) оговорено в гл. 8.
with promo as (
    select
        p.order_no,
        min(prm.promo_key) as promo_key
    from {{ ref('stg_kim_crm__promo_participation') }} p
    inner join {{ ref('dim_promo') }} prm
        on p.promo_id = prm.promo_id and prm.is_current
    group by 1
)

select
    f.order_date,
    f.order_id,
    f.order_line_key,
    f.order_no,
    f.channel,
    f.order_status,
    f.qty,
    f.line_amount,
    -- Денормализованный клиент: дневная версия сегмента уже выбрана SK факта.
    dc.segment,
    dc.city           as customer_city,
    dc.region         as customer_region,
    -- денормализованный товар
    dp.sku,
    dp.brand,
    {% if target.name == 'iceberg_gold' %}cast(null as varchar) as category_l1,{% else %}dp.category_l1,{% endif %}
    {% if target.name == 'iceberg_gold' %}cast(null as varchar) as category_l2,{% else %}dp.category_l2,{% endif %}
    {% if target.name == 'iceberg_gold' %}cat.name as category_l3,{% else %}dp.category_l3,{% endif %}
    -- денормализованный магазин
    ds.city           as store_city,
    ds.region         as store_region,
    ds.format         as store_format,
    -- промо (второй источник)
    pr.promo_key,
    pr.mechanics      as promo_mechanics,
    pr.discount_value as promo_discount_value,
    f.order_updated_at
from {{ ref('fact_sales') }} f
{% if target.name == 'iceberg_gold' %}
{#- L38: переносимое подмножество без internal-PK димов — атрибуты напрямую
    из staging (текущий сегмент/категория; версионная механика — см. fact_sales) -#}
join {{ ref('stg_kim_erp__customers') }} dc on dc.customer_id = f.customer_id
join {{ ref('stg_kim_erp__products') }} dp on dp.product_id = f.product_id
left join {{ ref('stg_kim_erp__categories') }} cat on cat.category_id = dp.category_id
{% else %}
    inner join {{ ref('dim_customer') }} dc on dc.customer_sk_v = f.customer_sk_v
    inner join {{ ref('dim_product') }} dp on dp.product_sk_v = f.product_sk_v
{% endif %}
inner join {{ ref('dim_store') }} ds on ds.store_key = f.store_key
left join promo pp on pp.order_no = f.order_no
left join {{ ref('dim_promo') }} pr
    on pr.promo_key = pp.promo_key and pr.is_current
