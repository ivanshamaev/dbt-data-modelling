{{ config(
    materialized='incremental',
    schema='iceberg.vault_core',
    incremental_strategy='default',
    partition_by=['load_date'],
    partition_type='Expr',
    tags=['vault'],
) }}

-- L5.2 · s_promo_crm: спутник CRM — свой record source (правило изоляции источников).
-- Ретро-коррекции акций (№3 из другого источника) видны как версии
-- ends_at/status; продления и досрочные остановки — паттерн для гл. 14.
with stream as (
    select
        promo_id,
        {{ hash_key('promo_id') }} as promo_hk,
        {{ hash_diff(['name', 'mechanics', 'discount_value', 'starts_at', 'ends_at', 'status']) }} as hash_diff,
        name,
        mechanics,
        discount_value,
        starts_at,
        ends_at,
        status,
        cast(updated_at as date)   as effective_from,
        _loaded_at
    from {{ ref('raw_crm__promotions') }}
),

dedup as (
    select
        promo_id,
        promo_hk,
        hash_diff,
        name,
        mechanics,
        discount_value,
        starts_at,
        ends_at,
        status,
        effective_from,
        _loaded_at,
        row_number() over (
            partition by promo_hk, effective_from, hash_diff, _loaded_at
            order by _loaded_at desc
        ) as rn
    from stream
),

changes as (
    select
        promo_id,
        promo_hk,
        hash_diff,
        name,
        mechanics,
        discount_value,
        starts_at,
        ends_at,
        status,
        effective_from,
        _loaded_at,
        lag(hash_diff) over (
            partition by promo_hk
            order by effective_from, _loaded_at
        ) as prev_diff
    from dedup
    where rn = 1
),

new_rows as (
    select
        promo_id,
        promo_hk,
        hash_diff,
        name,
        mechanics,
        discount_value,
        starts_at,
        ends_at,
        status,
        effective_from,
        _loaded_at,
        prev_diff
    from changes
    where prev_diff is null or hash_diff <> prev_diff
)

select
    promo_hk,
    hash_diff,
    name,
    mechanics,
    discount_value,
    starts_at,
    ends_at,
    status,
    _loaded_at as load_ts,
    cast(_loaded_at as date) as load_date,
    'crm'                    as record_source,
    effective_from
from new_rows n
{% if is_incremental() %}
    where not exists (
        select 1 from {{ this }} t
        where t.promo_hk = n.promo_hk
        -- L32: hash_diff В анти-джойне: same-day коррекция (та же effective_from,
        -- другой payload) — ЛЕГИТИМНАЯ версия, потребитель (BV/PIT) берёт последнюю
        -- по load_ts; дедуп — только точных переизлучений
        and t.hash_diff = n.hash_diff
        and t.effective_from = n.effective_from
        and t.load_ts = n._loaded_at
    )
{% endif %}
