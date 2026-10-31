{{ config(
    materialized='incremental',
    schema='iceberg.vault_stage',
    incremental_strategy='dynamic_overwrite',
    partition_by=['_ingest_date'],
    partition_type='Expr',
) }}

-- L4.3 · возвраты — insert-only поток событий (паттерн №8): история не
-- схлопывается, дедупа нет. Watermark+lookback по _ingest_date (день события);
-- dynamic_overwrite атомарно перезаливает дневные партиции -> идемпотентность
-- повторных прогонов (как в bronze, H4/H19).
select
    return_id,
    order_line_id,
    return_ts,
    qty,
    reason,
    refund_amount,
    _batch_id,
    _loaded_at,
    _source,
    _ingest_date
from {{ ref('raw_erp__returns') }}
{{ bronze_lookback('_ingest_date', 3) }}
