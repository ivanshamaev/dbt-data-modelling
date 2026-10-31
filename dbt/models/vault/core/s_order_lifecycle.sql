{{ config(
    materialized='incremental',
    schema='iceberg.vault_core',
    incremental_strategy='default',
    partition_by=['load_date'],
    partition_type='Expr',
    tags=['vault'],
) }}

-- L5.2 · s_order_lifecycle: статусы как СОБЫТИЯ (№2) — отдельный спутник по темпу изменений.
-- Разделение по темпу изменений: статусы меняются часто, суммы — редко;
-- раздельные спутники не плодят версий друг друга (гл. 9).
with stream as (
    select
        order_id,
        {{ hash_key('order_id') }} as order_hk,
        {{ hash_diff(['status', 'paid_at', 'shipped_at', 'delivered_at', 'cancelled_at']) }} as hash_diff,
        status,
        paid_at,
        shipped_at,
        delivered_at,
        cancelled_at,
        cast(updated_at as date)   as effective_from,
        _loaded_at
    from {{ ref('raw_erp__orders') }}
),

dedup as (
    select
        order_id,
        order_hk,
        hash_diff,
        status,
        paid_at,
        shipped_at,
        delivered_at,
        cancelled_at,
        effective_from,
        _loaded_at,
        row_number() over (
            partition by order_hk, effective_from, hash_diff, _loaded_at
            order by _loaded_at desc
        ) as rn
    from stream
),

changes as (
    select
        order_id,
        order_hk,
        hash_diff,
        status,
        paid_at,
        shipped_at,
        delivered_at,
        cancelled_at,
        effective_from,
        _loaded_at,
        lag(hash_diff) over (
            partition by order_hk
            order by effective_from, _loaded_at
        ) as prev_diff
    from dedup
    where rn = 1
),

new_rows as (
    select
        order_id,
        order_hk,
        hash_diff,
        status,
        paid_at,
        shipped_at,
        delivered_at,
        cancelled_at,
        effective_from,
        _loaded_at,
        prev_diff
    from changes
    where prev_diff is null or hash_diff <> prev_diff
)

select
    order_hk,
    hash_diff,
    status,
    paid_at,
    shipped_at,
    delivered_at,
    cancelled_at,
    _loaded_at as load_ts,
    cast(_loaded_at as date) as load_date,
    'erp'                    as record_source,
    effective_from
from new_rows n
{% if is_incremental() %}
    where not exists (
        select 1 from {{ this }} t
        where t.order_hk = n.order_hk
        -- L32: hash_diff В анти-джойне: same-day коррекция (та же effective_from,
        -- другой payload) — ЛЕГИТИМНАЯ версия, потребитель (BV/PIT) берёт последнюю
        -- по load_ts; дедуп — только точных переизлучений
        and t.hash_diff = n.hash_diff
        and t.effective_from = n.effective_from
        and t.load_ts = n._loaded_at
    )
{% endif %}
