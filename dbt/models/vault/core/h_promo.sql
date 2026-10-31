{{ config(
    materialized='incremental',
    schema='iceberg.vault_core',
    incremental_strategy='default',
    tags=['vault'],
) }}

-- L5.2 · h_promo: ВТОРОЙ ИСТОЧНИК — тот же vault принимает CRM без специальной инфраструктуры (№10).
with src as (
    select
        promo_id,
        {{ hash_key('promo_id') }} as promo_hk
    from {{ ref('stg_dv_crm__promotions') }}
)

select
    src.promo_hk,
    src.promo_id,
    cast(now() as date) as load_date,
    'crm'               as record_source
from src
{% if is_incremental() %}
    where not exists (
        select 1 from {{ this }} t
        where t.promo_hk = src.promo_hk
    )
{% endif %}
