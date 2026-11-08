{{ config(
    materialized='table',
    schema='iceberg.inmon_core',
) }}

{# L4.1 · история принадлежности товара категории (паттерн №5): #}
{# «по какой категории считать исторические продажи» — вопрос к этой таблице. #}
{# Та же механика версий, что и int_customer_attributes; перенос ~30 товаров #}
{# за симуляцию виден как вторая версия. #}
with deduped as (
    select
        product_id,
        category_id,
        updated_at,
        row_number() over (
            partition by product_id, cast(updated_at as date)
            order by updated_at desc, _loaded_at desc
        ) as rn
    from {{ ref('raw_erp__products') }}
),

real_changes as (
    select
        product_id,
        category_id,
        updated_at,
        rn,
        lag(category_id) over (
            partition by product_id
            order by updated_at
        ) as prev_category
    from deduped
    where rn = 1
),

changes_only as (
    select
        product_id,
        category_id,
        updated_at
    from real_changes
    where prev_category is null or category_id <> prev_category
),

with_validity as (
    select
        product_id,
        category_id,
        updated_at,
        lead(cast(updated_at as date)) over (
            partition by product_id
            order by updated_at
        )     as valid_to,
        row_number() over (
            partition by product_id
            order by updated_at
        ) = 1 as is_first,
        row_number() over (
            partition by product_id
            order by updated_at desc
        ) = 1 as is_current
    from changes_only
)

select
    product_id,
    category_id,
    {# Temporal baseline (§2.1): первая версия категории валидна «с рождения»
       товара — иначе valid-time join в fact_sales терял 37% строк (урок R2:
       pre-baseline заказы). #}
    case when is_first then date '1970-01-01' else cast(updated_at as date) end as valid_from,
    valid_to,
    is_current
from with_validity
