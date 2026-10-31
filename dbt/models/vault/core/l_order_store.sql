{{ config(
    materialized='incremental',
    schema='iceberg.vault_core',
    incremental_strategy='default',
    tags=['vault'],
) }}

-- L5.2 · l_order_store: связь «заказ принят магазином» (N:1; онлайн = store 15).
-- Без табличного алиаса: src один, ссылки однозначны (sqlfluff AL05 не видит
-- использования алиаса внутри заглушки hash_key — L39).
with src as (
    select
        {{ hash_key(['order_id', 'store_id']) }} as order_store_hk,
        {{ hash_key('order_id') }}               as order_hk,
        {{ hash_key('store_id') }}               as store_hk
    from {{ ref('stg_dv_erp__orders') }}
)

select
    src.order_store_hk,
    src.order_hk,
    src.store_hk,
    cast(now() as date) as load_date,
    'erp'               as record_source
from src
{% if is_incremental() %}
    where not exists (
        select 1 from {{ this }} t
        where t.order_store_hk = src.order_store_hk
    )
{% endif %}
