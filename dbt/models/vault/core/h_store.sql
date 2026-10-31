{{ config(
    materialized='incremental',
    schema='iceberg.vault_core',
    incremental_strategy='default',
    tags=['vault'],
) }}

-- L5.2 · h_store: идентичность магазина (открытие/закрытие — атрибуты, не ключ).
with src as (
    select
        store_id,
        {{ hash_key('store_id') }} as store_hk
    from {{ ref('stg_dv_erp__stores') }}
)

select
    src.store_hk,
    src.store_id,
    cast(now() as date) as load_date,
    'erp'               as record_source
from src
{% if is_incremental() %}
    where not exists (
        select 1 from {{ this }} t
        where t.store_hk = src.store_hk
    )
{% endif %}
