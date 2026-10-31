{{ config(
    materialized='incremental',
    schema='iceberg.med_bronze',
    incremental_strategy='dynamic_overwrite',
    partition_by=['_ingest_date'],
    partition_type='Expr',
) }}

-- L3.2 · brz_crm__promo_participation: участия заказов в промо.
-- Watermark — sync_ts, НЕ attached_at: CRM «догоняет» с лагом 1–3 дня (паттерн №10),
-- и именно момент доставки, а не бизнес-момент, определяет инкремент.
-- ~1% строк — орфаны по order_no (плохие по построению; ловим тестом с порогом
-- в staging, не здесь: bronze не применяет бизнес-правил).
select
    id,
    promo_id,
    order_no,
    attached_at,
    sync_ts,
    {{ bronze_tech('crm', 'sync_ts') }}
from {{ source('crm_pg', 'promo_participation') }}
{{ bronze_lookback('sync_ts') }}
