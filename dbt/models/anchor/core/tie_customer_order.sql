{{ config(
    materialized='table',
    schema='iceberg.anchor_core',
    tags=['anchor'],
) }}

-- L5.4 · tie_customer_order: tie — N-арная связь (здесь бинарная), insert_time = когда связь стала известна DWH.
select
    order_id,
    customer_id,
    min(_loaded_at) as insert_time
from {{ ref('raw_erp__orders') }}
group by order_id, customer_id;
