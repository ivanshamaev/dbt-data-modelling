{{ config(
    materialized='incremental',
    schema='iceberg.bronze',
    incremental_strategy='dynamic_overwrite',
    partition_by=['_ingest_date'],
    partition_type='Expr',
) }}

-- L3.2 · raw_erp__inventory: ежедневные снапшоты остатков — insert-only по дню,
-- watermark по snap_date (дата события = дата снапшота, партиция совпадает 1:1).
-- Самая тяжёлая bronze-таблица (~33 млн строк за историю): первый билд одним CTAS.
select
    snap_date,
    store_id,
    product_id,
    qty_on_hand,
    qty_reserved,
    {{ bronze_tech('erp', 'snap_date') }}
from {{ source('erp_pg', 'inventory') }}
{{ bronze_lookback('snap_date') }}
