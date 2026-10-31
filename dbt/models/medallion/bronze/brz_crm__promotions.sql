{{ config(
    materialized='incremental',
    schema='iceberg.med_bronze',
    incremental_strategy='default',
    partition_by=['_ingest_date'],
    partition_type='Expr',
) }}

-- L3.2 · brz_crm__promotions: промо-акции из второго источника — свои ключи (PR-2024-017),
-- ретро-коррекции сроков/статусов с бампом updated_at (паттерн №3 из CRM).
-- L53: сохраняем каждую наблюдённую версию; повтор не меняет её время загрузки.
with incoming as (
    select
        promo_id,
        name,
        mechanics,
        discount_value,
        starts_at,
        ends_at,
        status,
        updated_at,
        {{ bronze_tech('crm', 'updated_at') }}
    from {{ source('crm_pg', 'promotions') }}
    {{ bronze_lookback('updated_at') }}
)

select
    s.promo_id,
    s.name,
    s.mechanics,
    s.discount_value,
    s.starts_at,
    s.ends_at,
    s.status,
    s.updated_at,
    s._batch_id,
    s._loaded_at,
    s._source,
    s._ingest_date
from incoming s
{{ bronze_new_versions([
    'promo_id',
    'name',
    'mechanics',
    'discount_value',
    'starts_at',
    'ends_at',
    'status',
    'updated_at'
]) }}
