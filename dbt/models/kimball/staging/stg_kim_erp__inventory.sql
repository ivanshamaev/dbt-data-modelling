{{ config(
    materialized='incremental',
    schema='iceberg.kimball_stage',
    incremental_strategy='dynamic_overwrite',
    partition_by=['_ingest_date'],
    partition_type='Expr',
) }}

-- L4.3 · инвентарь: periodic snapshot — полный дневной поток (33M строк
-- истории), дедупа нет: PK (snap_date, store_id, product_id) уникален в bronze
-- по построению. Инкремент по дням; «дыры» матрицы ассортимента сохраняются —
-- это учебный материал KPI №9, а не баг.
select
    snap_date,
    store_id,
    product_id,
    qty_on_hand,
    qty_reserved,
    _batch_id,
    _loaded_at,
    _source,
    _ingest_date
from {{ ref('raw_erp__inventory') }}
{{ bronze_lookback('_ingest_date', 3) }}
