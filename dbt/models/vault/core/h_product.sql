{{ config(
    materialized='incremental',
    schema='iceberg.vault_core',
    incremental_strategy='default',
    tags=['vault'],
) }}

-- L5.2 · h_product: идентичность товара; смена категории — дело спутника.
with src as (
    select
        product_id,
        {{ hash_key('product_id') }} as product_hk
    from {{ ref('stg_dv_erp__products') }}
)

select
    src.product_hk,
    src.product_id,
    cast(now() as date) as load_date,
    'erp'               as record_source
from src
{% if is_incremental() %}
    where not exists (
        select 1 from {{ this }} t
        where t.product_hk = src.product_hk
    )
{% endif %}
