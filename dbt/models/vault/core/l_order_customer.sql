{{ config(
    materialized='incremental',
    schema='iceberg.vault_core',
    incremental_strategy='default',
    tags=['vault'],
) }}

-- L5.2 · l_order_customer: связь «заказ оформлен клиентом» (N:1, неизменна).
-- Без табличного алиаса: src один, ссылки однозначны (sqlfluff AL05 не видит
-- использования алиаса внутри заглушки hash_key — L39).
with src as (
    select
        {{ hash_key(['order_id', 'customer_id']) }} as order_customer_hk,
        {{ hash_key('order_id') }}                  as order_hk,
        {{ hash_key('customer_id') }}               as customer_hk
    from {{ ref('stg_dv_erp__orders') }}
)

select
    src.order_customer_hk,
    src.order_hk,
    src.customer_hk,
    cast(now() as date) as load_date,
    'erp'               as record_source
from src
{% if is_incremental() %}
    where not exists (
        select 1 from {{ this }} t
        where t.order_customer_hk = src.order_customer_hk
    )
{% endif %}
