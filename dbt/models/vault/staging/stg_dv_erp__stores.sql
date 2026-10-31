{{ config(
    materialized='table',
    schema='iceberg.vault_stage',
) }}

{# L4.3 · магазины: закрывающиеся измерения (паттерн №6) — закрытие остаётся #}
{# в строке (closed_at + is_active), история продаж не теряется. #}
with ranked as (
    select
        store_id,
        name,
        format,
        city,
        region,
        opened_at,
        closed_at,
        updated_at,
        _batch_id,
        _loaded_at,
        _source,
        _ingest_date,
        row_number() over (
            partition by store_id
            order by updated_at desc, _loaded_at desc
        ) as rn
    from {{ ref('raw_erp__stores') }}
)

select
    store_id,
    name,
    format,
    city,
    region,
    opened_at,
    closed_at,
    closed_at is not null      as is_closed,
    {{ hash_key('store_id') }} as store_key
from ranked
where rn = 1
