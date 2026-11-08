{{ config(
    materialized='table',
    schema='iceberg.anchor_core',
    tags=['anchor'],
) }}

-- L5.4 · anc_product: anchor — существование сущности (только ключ + insert_time).
select
    product_id,
    min(_loaded_at) as insert_time
from {{ ref('raw_erp__products') }}
group by 1;
