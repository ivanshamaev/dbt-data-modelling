{{ config(
    materialized='table',
    tags=['gold', 'dim'],
) }}

{# L4.3 · dim_product: SCD2 по категории (паттерн №5) + flatten иерархии level1..3. #}
{#  #}
{# Версии строятся из собственной kim_product_category_history, читающей bronze. #}
{# Контур не зависит от int_* или Medallion; сохраняются только наблюдённые версии. #}
{# product_key — идентичность товара, product_sk_v — ключ версии категории. #}
{# Категории статичны (имена не меняются) -> имена flatten'ятся на версию. #}
select
    {{ hash_key(['p.product_id', 'cast(v.valid_from as date)']) }} as product_sk_v,
    p.product_key,
    p.product_id,
    p.sku,
    p.brand,
    p.list_price,
    p.is_active,
    p.launched_at,
    v.category_id,
    c3.name                                                        as category_l1,
    c2.name                                                        as category_l2,
    c1.name                                                        as category_l3,
    cast(v.valid_from as date)                                     as valid_from,
    cast(v.valid_to as date)                                       as valid_to,
    v.is_current
from {{ ref('kim_product_category_history') }} v
inner join {{ ref('stg_kim_erp__products') }} p
    on v.product_id = p.product_id
inner join {{ ref('stg_kim_erp__categories') }} c1
    on v.category_id = c1.category_id
left join {{ ref('stg_kim_erp__categories') }} c2
    on c1.parent_category_id = c2.category_id
left join {{ ref('stg_kim_erp__categories') }} c3
    on c2.parent_category_id = c3.category_id
