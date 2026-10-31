{{ config(
    materialized='incremental',
    schema='iceberg.inmon_stage',
    incremental_strategy='dynamic_overwrite',
    partition_by=['_ingest_date'],
    partition_type='Expr',
) }}

-- L4.3 · промо-участия: insert-only поток, приезжающий с лагом sync_ts (№10).
-- Стыковка конвенций CRM -> канон: безликое `id` -> `participation_id`
-- (приложение B). order_no оставляем как есть: орфаны ~1% — данные, плохие
-- по построению; кросс-источниковая конформность (order_no -> order_key)
-- происходит В МОДЕЛИ vault/звезды, не в staging и не в инфраструктуре.
select
    id as participation_id,
    promo_id,
    order_no,
    attached_at,
    sync_ts,
    _batch_id,
    _loaded_at,
    _source,
    _ingest_date
from {{ ref('raw_crm__promo_participation') }}
{{ bronze_lookback('_ingest_date', 3) }}
