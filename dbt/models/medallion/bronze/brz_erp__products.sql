{{ config(
    materialized='incremental',
    schema='iceberg.med_bronze',
    incremental_strategy='default',
    partition_by=['_ingest_date'],
    partition_type='Expr',
) }}

-- L3.2 · brz_erp__products: товары; перенос категории бампает updated_at (паттерн №5).
-- L53: сохраняем каждую наблюдённую версию; повтор не меняет её время загрузки.
with incoming as (
    select
        product_id,
        sku,
        category_id,
        brand,
        list_price,
        is_active,
        launched_at,
        updated_at,
        {{ bronze_tech('erp', 'updated_at') }}
    from {{ source('erp_pg', 'products') }}
    {{ bronze_lookback('updated_at') }}
)

select
    s.product_id,
    s.sku,
    s.category_id,
    s.brand,
    s.list_price,
    s.is_active,
    s.launched_at,
    s.updated_at,
    s._batch_id,
    s._loaded_at,
    s._source,
    s._ingest_date
from incoming s
{{ bronze_new_versions([
    'product_id',
    'sku',
    'category_id',
    'brand',
    'list_price',
    'is_active',
    'launched_at',
    'updated_at'
]) }}
