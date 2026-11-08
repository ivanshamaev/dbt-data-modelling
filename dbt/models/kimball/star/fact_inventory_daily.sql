{{ config(
    materialized='incremental',
    incremental_strategy='dynamic_overwrite',
    table_type='DUPLICATE',
    keys=['snap_date', 'store_id', 'product_id'],
    distributed_by=['store_id', 'product_id'],
    partition_by=['snap_date'],
    partition_type='Expr',
    tags=['gold', 'fact'],
) }}

-- L4.4 · fact_inventory_daily: periodic snapshot (состояния, не события).
-- ПОЛУАДДИТИВНОСТЬ (гл. 7): qty_on_hand можно складывать по магазинам/SKU
-- внутри дня, НЕЛЬЗЯ по датам — любая витрина обязана это уважать.
-- Отсутствие строки означает отсутствие наблюдаемого сочетания inventory.
-- Это не нулевой остаток и не доказательство отсутствия продаж; отдельного плана нет.
-- product_key — идентичность; category_id относится к дню снимка.
-- Для отчёта в текущей классификации нужно отдельно соединиться с текущим измерением.
select
    i.snap_date,
    i.store_id,
    i.product_id,
    s.store_key,
    p.product_key,
    p.category_id,
    i.qty_on_hand,
    i.qty_reserved,
    i.qty_on_hand = 0 as is_out_of_stock,
    i._ingest_date
from {{ ref('stg_kim_erp__inventory') }} i
inner join {{ ref('dim_store') }} s
    on i.store_id = s.store_id
inner join {{ ref('dim_product') }} p
    on
        i.product_id = p.product_id
        and p.valid_from <= i.snap_date
        and (p.valid_to is null or i.snap_date < p.valid_to)
{% if is_incremental() %}
    {% if var('reload_from_date', none) %}
        where i.snap_date >= cast('{{ var("reload_from_date") }}' as date)
    {% else %}
    where i.snap_date > coalesce((select max(snap_date) from {{ this }}), date '1970-01-01') - interval 3 day
    {% endif %}
{% endif %}
