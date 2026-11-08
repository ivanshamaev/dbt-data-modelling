{{ config(
    materialized='table',
    schema='iceberg.anchor_core',
    tags=['anchor'],
) }}

-- L5.4 · anc_promo (второй источник): anchor — существование сущности (только ключ + insert_time).
select
    promo_id,
    min(_loaded_at) as insert_time
from {{ ref('raw_crm__promotions') }}
group by 1;
