{{ config(
    materialized='incremental',
    schema='iceberg.vault_core',
    incremental_strategy='dynamic_overwrite',
    partition_by=['snap_date'],
    partition_type='Expr',
    tags=['vault'],
) }}

-- Снимки на зерне день × магазин × товар, учебная адаптация с префиксом s.
-- hash_diff сохранён как отпечаток; он не управляет change-capture загрузкой.
-- Одинаковые количества разных дней остаются разными наблюдениями.
-- Идемпотентность — замена полных выбранных snap_date; отдельного
-- родительского link store-product в текущей модели нет.
select
    {{ hash_key(['i.store_id', 'i.product_id']) }}       as store_product_hk,
    {{ hash_key('i.store_id') }}                         as store_hk,
    {{ hash_key('i.product_id') }}                       as product_hk,
    {{ hash_diff(['i.qty_on_hand', 'i.qty_reserved']) }} as hash_diff,
    i.snap_date,
    i.qty_on_hand,
    i.qty_reserved,
    cast(_loaded_at as date)                             as load_date,
    'erp'                                                as record_source,
    i.snap_date                                          as effective_from
from {{ ref('stg_dv_erp__inventory') }} i
{# L33: watermark ЛИТЕРАЛОМ через run_query — скалярный подзапрос к целевой
   таблице внутри INSERT OVERWRITE поверх external-scan отвергается планировщиком
   («Only support use correlated columns…»). Паттерн = H19-fallback. #}
{%- if is_incremental() %}
    {% if var('reload_from_date', none) %}
    where snap_date >= cast('{{ var("reload_from_date") }}' as date)
    {% else %}
    {%- set wm = run_query('select max(snap_date) from ' ~ this).columns[0].values()[0] or '1970-01-01' %}
    where snap_date > cast('{{ wm }}' as date) - interval {{ var('lookback_days', 3) }} day
    {% endif %}
{%- endif %}
