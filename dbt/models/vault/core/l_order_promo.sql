{{ config(
    materialized='incremental',
    schema='iceberg.vault_core',
    incremental_strategy='default',
    tags=['vault'],
) }}

-- L5.2 · l_order_promo: КРОСС-ИСТОЧНИКОВЫЙ LINK (паттерн №10 — главный аргумент DV).
-- Связь «заказ участвовал в промо» УЗНАНА ИЗ CRM (record_source='crm'),
-- а участники связи принадлежат разным системам: order_hk из ERP,
-- promo_hk из CRM. Конформность order_no → order_hk происходит В МОДЕЛИ
-- (не в инфраструктуре); орфаны отфильтрованы inner join'ом (их доля
-- ограничена тестом staging — правило «плохие по построению не красят build»).
-- attached_ts/sync_ts на связи — лаг синхронизации систем виден прямо в vault.
with src as (
    select
        {{ hash_key(['o.order_id', 'pr.promo_id']) }} as order_promo_hk,
        {{ hash_key('o.order_id') }}                  as order_hk,
        {{ hash_key('pr.promo_id') }}                 as promo_hk,
        pp.order_no,
        pp.attached_at,
        pp.sync_ts
    from {{ ref('stg_dv_crm__promo_participation') }} pp
    inner join {{ ref('stg_dv_erp__orders') }} o
        on pp.order_no = o.order_no
    inner join {{ ref('stg_dv_crm__promotions') }} pr
        on pp.promo_id = pr.promo_id
)

select
    src.order_promo_hk,
    src.order_hk,
    src.promo_hk,
    src.order_no,
    src.attached_at,
    src.sync_ts,
    cast(now() as date) as load_date,
    'crm'               as record_source
from src
{% if is_incremental() %}
    where not exists (
        select 1 from {{ this }} t
        where t.order_promo_hk = src.order_promo_hk
    )
{% endif %}
