{{ config(
    materialized='incremental',
    schema='iceberg.vault_core',
    incremental_strategy='default',
    partition_by=['load_date'],
    partition_type='Expr',
    tags=['vault'],
) }}

-- L5.2 · s_product_erp: история атрибутов товара; перенос категории (№5) — новая версия отпечатка.
-- Одна таблица на источник (правило «один satellite — один record source»);
-- категория включена в отпечаток: редкие изменения не оправдывают отдельного спутника.
with stream as (
    select
        product_id,
        {{ hash_key('product_id') }} as product_hk,
        {{ hash_diff(['sku', 'brand', 'list_price', 'is_active', 'launched_at', 'category_id']) }} as hash_diff,
        sku,
        brand,
        list_price,
        is_active,
        launched_at,
        category_id,
        cast(updated_at as date)     as effective_from,
        _loaded_at
    from {{ ref('raw_erp__products') }}
),

dedup as (
    select
        product_id,
        product_hk,
        hash_diff,
        sku,
        brand,
        list_price,
        is_active,
        launched_at,
        category_id,
        effective_from,
        _loaded_at,
        row_number() over (
            partition by product_hk, effective_from, hash_diff, _loaded_at
            order by _loaded_at desc
        ) as rn
    from stream
),

changes as (
    select
        product_id,
        product_hk,
        hash_diff,
        sku,
        brand,
        list_price,
        is_active,
        launched_at,
        category_id,
        effective_from,
        _loaded_at,
        lag(hash_diff) over (
            partition by product_hk
            order by effective_from, _loaded_at
        ) as prev_diff
    from dedup
    where rn = 1
),

new_rows as (
    select
        product_id,
        product_hk,
        hash_diff,
        sku,
        brand,
        list_price,
        is_active,
        launched_at,
        category_id,
        effective_from,
        _loaded_at,
        prev_diff
    from changes
    where prev_diff is null or hash_diff <> prev_diff
)

select
    product_hk,
    hash_diff,
    sku,
    brand,
    list_price,
    is_active,
    launched_at,
    category_id,
    _loaded_at as load_ts,
    cast(_loaded_at as date) as load_date,
    'erp'                    as record_source,
    effective_from
from new_rows n
{% if is_incremental() %}
    where not exists (
        select 1 from {{ this }} t
        where t.product_hk = n.product_hk
        -- L32: hash_diff В анти-джойне: same-day коррекция (та же effective_from,
        -- другой payload) — ЛЕГИТИМНАЯ версия, потребитель (BV/PIT) берёт последнюю
        -- по load_ts; дедуп — только точных переизлучений
        and t.hash_diff = n.hash_diff
        and t.effective_from = n.effective_from
        and t.load_ts = n._loaded_at
    )
{% endif %}
