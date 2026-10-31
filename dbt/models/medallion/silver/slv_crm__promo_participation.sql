{{ config(
    materialized='incremental',
    schema='iceberg.med_silver',
    incremental_strategy='dynamic_overwrite',
    partition_by=['_ingest_date'],
    partition_type='Expr',
) }}

-- L4.3 · промо-участия: insert-only поток, приезжающий с лагом sync_ts (№10).
-- Стыковка конвенций CRM -> канон: безликое `id` -> `participation_id`
-- (приложение B). order_no оставляем как есть: орфаны ~1% — данные, плохие
-- по построению. Связь с ERP по точному order_no выполняет
-- собственная gold-витрина; Silver сохраняет в том числе записи без ERP-заказа.
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
from {{ ref('brz_crm__promo_participation') }}
{{ bronze_lookback('_ingest_date', 3) }}
