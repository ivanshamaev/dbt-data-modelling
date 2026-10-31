{{ config(
    materialized='table',
    schema='iceberg.med_silver',
) }}

{# Текущее состояние товара из собственной Bronze-истории. #}
{# Silver этого контура не публикует интервальную историю категории. #}
with ranked as (
    select
        product_id,
        sku,
        category_id,
        brand,
        list_price,
        is_active,
        launched_at,
        updated_at,
        _batch_id,
        _loaded_at,
        _source,
        _ingest_date,
        row_number() over (
            partition by product_id
            order by updated_at desc, _loaded_at desc
        ) as rn
    from {{ ref('brz_erp__products') }}
)

select
    product_id,
    sku,
    category_id,
    brand,
    list_price,
    is_active,
    launched_at,
    updated_at,
    {{ hash_key('product_id') }} as product_key
from ranked
where rn = 1
