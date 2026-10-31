{{ config(
    materialized='incremental',
    schema='iceberg.med_bronze',
    incremental_strategy='default',
    partition_by=['_ingest_date'],
    partition_type='Expr',
) }}

-- L3.2 · brz_erp__customers: сырьё клиентов ERP.
-- Watermark: updated_at (каждая смена сегмента/города/soft delete бампает его — контракт L2.2).
-- Паттерны: №1 (SCD-клиента), №4 (soft delete).
-- L53: сохраняем каждую наблюдённую версию; повтор не меняет её время загрузки.
with incoming as (
    select
        customer_id,
        segment,
        city,
        region,
        registered_at,
        updated_at,
        deleted_at,
        {{ bronze_tech('erp', 'updated_at') }}
    from {{ source('erp_pg', 'customers') }}
    {{ bronze_lookback('updated_at') }}
)

select
    s.customer_id,
    s.segment,
    s.city,
    s.region,
    s.registered_at,
    s.updated_at,
    s.deleted_at,
    s._batch_id,
    s._loaded_at,
    s._source,
    s._ingest_date
from incoming s
{{ bronze_new_versions([
    'customer_id',
    'segment',
    'city',
    'region',
    'registered_at',
    'updated_at',
    'deleted_at'
]) }}
