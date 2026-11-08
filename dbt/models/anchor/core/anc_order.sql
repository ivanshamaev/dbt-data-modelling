{{ config(
    materialized='table',
    schema='iceberg.anchor_core',
    tags=['anchor'],
) }}

-- L5.4 · anc_order: anchor — существование сущности (только ключ + insert_time).
select
    order_id,
    min(_loaded_at) as insert_time
from {{ ref('raw_erp__orders') }}
group by 1;
