{{ config(
    materialized='incremental',
    schema='iceberg.med_bronze',
    incremental_strategy='default',
    partition_by=['_ingest_date'],
    partition_type='Expr',
) }}

-- L3.2 · brz_erp__order_lines: строки заказов (гранулярность факта продаж).
-- Watermark: updated_at бампается ретро-правками строк (v2.2 спеки — правка суммы
-- трогает и строку, и шапку: инвариант «сумма строк = total_amount» не расходится).
-- L53: сохраняем каждую наблюдённую версию; повтор не меняет её время загрузки.
with incoming as (
    select
        order_line_id,
        order_id,
        product_id,
        qty,
        unit_price,
        discount_pct,
        line_amount,
        updated_at,
        {{ bronze_tech('erp', 'updated_at') }}
    from {{ source('erp_pg', 'order_lines') }}
    {{ bronze_lookback('updated_at') }}
)

select
    s.order_line_id,
    s.order_id,
    s.product_id,
    s.qty,
    s.unit_price,
    s.discount_pct,
    s.line_amount,
    s.updated_at,
    s._batch_id,
    s._loaded_at,
    s._source,
    s._ingest_date
from incoming s
{{ bronze_new_versions([
    'order_line_id',
    'order_id',
    'product_id',
    'qty',
    'unit_price',
    'discount_pct',
    'line_amount',
    'updated_at'
]) }}
