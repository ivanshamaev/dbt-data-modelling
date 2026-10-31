{{ config(
    materialized='incremental',
    schema='iceberg.vault_core',
    incremental_strategy='default',
    tags=['vault'],
) }}

-- Связь платёж-заказ: split-платежи имеют разные payment_id.
-- L69: paid_ts — первоначально зарегистрированный контекст пары. Его последующие
-- исправления не версионируются; полный текущий payload доступен в staging.
with src as (
    select
        p.{{ hash_key(['p.payment_id', 'p.order_id']) }} as payment_order_hk,
        p.{{ hash_key('p.payment_id') }}                 as payment_hk,
        p.{{ hash_key('p.order_id') }}                   as order_hk,
        p.payment_id,
        p.paid_ts
    from {{ ref('stg_dv_erp__payments') }} p
)

select
    src.payment_order_hk,
    src.payment_hk,
    src.order_hk,
    src.payment_id,
    src.paid_ts,
    cast(now() as date) as load_date,
    'erp'               as record_source
from src
{% if is_incremental() %}
    where not exists (
        select 1 from {{ this }} t
        where t.payment_order_hk = src.payment_order_hk
    )
{% endif %}
