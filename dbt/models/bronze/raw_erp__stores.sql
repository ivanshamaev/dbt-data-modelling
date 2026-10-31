{{ config(
    materialized='incremental',
    schema='iceberg.bronze',
    incremental_strategy='default',
    partition_by=['_ingest_date'],
    partition_type='Expr',
) }}

-- L3.2 · raw_erp__stores: магазины; открытие/закрытие (паттерн №6).
-- L53: сохраняем каждую наблюдённую версию; повтор не меняет её время загрузки.
with incoming as (
    select
        store_id,
        name,
        format,
        city,
        region,
        opened_at,
        closed_at,
        updated_at,
        {{ bronze_tech('erp', 'updated_at') }}
    from {{ source('erp_pg', 'stores') }}
    {{ bronze_lookback('updated_at') }}
)

select
    s.store_id,
    s.name,
    s.format,
    s.city,
    s.region,
    s.opened_at,
    s.closed_at,
    s.updated_at,
    s._batch_id,
    s._loaded_at,
    s._source,
    s._ingest_date
from incoming s
{{ bronze_new_versions([
    'store_id',
    'name',
    'format',
    'city',
    'region',
    'opened_at',
    'closed_at',
    'updated_at'
]) }}
