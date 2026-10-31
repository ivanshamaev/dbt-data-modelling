{{ config(
    materialized='incremental',
    schema='iceberg.vault_core',
    incremental_strategy='default',
    tags=['vault'],
) }}

-- L5.2 · h_order: идентичность заказа (order_no — degenerate, живёт в связях/спутниках).
with src as (
    select
        order_id,
        {{ hash_key('order_id') }} as order_hk
    from {{ ref('stg_dv_erp__orders') }}
)

select
    src.order_hk,
    src.order_id,
    cast(now() as date) as load_date,
    'erp'               as record_source
from src
{% if is_incremental() %}
    where not exists (
        select 1 from {{ this }} t
        where t.order_hk = src.order_hk
    )
{% endif %}
