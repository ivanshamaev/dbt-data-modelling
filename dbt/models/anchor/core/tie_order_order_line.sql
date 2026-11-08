{{ config(
    materialized='table',
    schema='iceberg.anchor_core',
    tags=['anchor'],
) }}

-- L5.4 · tie_order_order_line: tie — N-арная связь (здесь бинарная), insert_time = когда связь стала известна DWH.
select
    order_id,
    order_line_id,
    min(_loaded_at) as insert_time
from {{ ref('raw_erp__order_lines') }}
group by order_id, order_line_id;
