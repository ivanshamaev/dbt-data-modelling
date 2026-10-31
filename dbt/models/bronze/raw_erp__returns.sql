{{ config(
    materialized='incremental',
    schema='iceberg.bronze',
    incremental_strategy='dynamic_overwrite',
    partition_by=['_ingest_date'],
    partition_type='Expr',
) }}

-- L3.2 · raw_erp__returns: возвраты строк — insert-only событие (паттерн №8),
-- watermark по дате события return_ts.
-- ⚠ M0-10: «returns» — потенциальное ключевое слово в парсере StarRocks;
-- если CREATE/SELECT упадёт — включить quoting.identifier для этого source
-- или переименовать таблицу источника (правка спеки §2.2).
select
    return_id,
    order_line_id,
    return_ts,
    qty,
    reason,
    refund_amount,
    {{ bronze_tech('erp', 'return_ts') }}
from {{ source('erp_pg', 'returns') }}
{{ bronze_lookback('return_ts') }}
