{#append-only: внешняя идемпотентность анти-join'ом #}
{{ config(
    materialized='incremental',
    schema='iceberg.vault_core',
    incremental_strategy='default',
    partition_by=['load_date'],
    partition_type='Expr',
    tags=['vault'],
) }}

-- L5.2 · s_customer_erp: история атрибутов клиента (№1), insert-only.
--
-- РЕАЛИЗОВАННАЯ ЗАГРУЗКА СПУТНИКА:
--   1) читаем ПОТОК bronze (не staging-снимок!) — «сырые» состояния по updated_at;
--   2) hash_diff по атрибутам: бамп updated_at БЕЗ смены хешируемых атрибутов
--      НЕ создаёт версию — сравнением отпечатка с lag();
--   3) append-only: в {{ this }} уходит только то, чего ещё нет (анти-join
--      по (hk, hash_diff, effective_from, load_ts)) — H3: unique_key в external не работает,
--      дедупликация строго SQL-side; повторный build без новых данных = 0 строк.
--
-- Времена: load_ts — первая доставка наблюдения в bronze; load_date —
-- дата этой доставки для партиционирования; effective_from — бизнес-день.
with stream as (
    select
        customer_id,
        {{ hash_key('customer_id') }}                                                 as customer_hk,
        {{ hash_diff(['segment', 'city', 'region', 'registered_at', 'deleted_at']) }} as hash_diff,
        segment,
        city,
        region,
        registered_at,
        deleted_at,
        cast(updated_at as date)                                                      as effective_from,
        _loaded_at
    from {{ ref('raw_erp__customers') }}
),

dedup as (
    select
        customer_id,
        customer_hk,
        hash_diff,
        segment,
        city,
        region,
        registered_at,
        deleted_at,
        effective_from,
        _loaded_at,
        row_number() over (
            partition by customer_hk, effective_from, hash_diff, _loaded_at
            order by _loaded_at desc
        ) as rn
    from stream
),

changes as (
    select
        customer_id,
        customer_hk,
        hash_diff,
        segment,
        city,
        region,
        registered_at,
        deleted_at,
        effective_from,
        _loaded_at,
        lag(hash_diff) over (
            partition by customer_hk
            order by effective_from, _loaded_at
        ) as prev_diff
    from dedup
    where rn = 1
),

new_rows as (
    select
        customer_id,
        customer_hk,
        hash_diff,
        segment,
        city,
        region,
        registered_at,
        deleted_at,
        effective_from,
        _loaded_at,
        prev_diff
    from changes
    where prev_diff is null or hash_diff <> prev_diff
),
{# L31+L34: temporal baseline (§2.1) — первая версия валидна «с рождения», как в
   int_customer_attributes/ac_customer_segment; иначе as-of join в KPI №7 теряет
   pre-baseline заказы. Floor ОБЯЗАН жить в CTE ДО анти-джойна: алиас SELECT-списка
   невидим в WHERE, и анти-джойн сравнивал raw-дату с сохранённым floor → never match
   → каждый прогон аппендил полный набор (4×50K дублей на живом прогоне). #}
baseline as (
    select
        customer_hk,
        hash_diff,
        segment,
        city,
        region,
        registered_at,
        deleted_at,
        _loaded_at as load_ts,
        cast(_loaded_at as date)                                                   as load_date,
        'erp'                                                                      as record_source,
        case when prev_diff is null then date '1970-01-01' else effective_from end as effective_from
    from new_rows
)

select
    customer_hk,
    hash_diff,
    segment,
    city,
    region,
    registered_at,
    deleted_at,
    load_ts,
    load_date,
    record_source,
    effective_from
from baseline n
{% if is_incremental() %}
    where not exists (
        select 1 from {{ this }} t
        where t.customer_hk = n.customer_hk
        -- L32: hash_diff В анти-джойне: same-day коррекция (та же effective_from,
        -- другой payload) — ЛЕГИТИМНАЯ версия, потребитель (BV/PIT) берёт последнюю
        -- по load_ts; дедуп — только точных переизлучений
        and t.hash_diff = n.hash_diff
        and t.effective_from = n.effective_from
        and t.load_ts = n.load_ts
    )
{% endif %}
