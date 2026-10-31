{{ config(
    materialized='table',
    schema='iceberg.kimball_stage',
) }}

{# L4.1 · история атрибутов клиента (время-вариантное 3NF-ядро, паттерн №1). #}
{# Разворачиваем поток изменений bronze в версионные строки: valid_from/valid_to, #}
{# is_current. Таблица полностью реконструируется из сохранённых наблюдений bronze. #}
{#  #}
{# Две чистки потока: #}
{# 1) последнее наблюдение (customer_id, день updated_at) — страховка от перезаливов окна; #}
{# 2) «тихие версии» отбрасываются: soft delete бампает updated_at, НЕ меняя #}
{# сегмент/город — такие версии не создаются (анти-«SCD2-мания», L1.2). #}
{#  #}
{# Temporal baseline (§2.1): первая версия каждого клиента = состояние на момент #}
{# запуска DWH; более ранняя история не существует по построению источников. #}
with deduped as (
    select
        customer_id,
        segment,
        city,
        region,
        updated_at,
        row_number() over (
            partition by customer_id, cast(updated_at as date)
            order by updated_at desc, _loaded_at desc
        ) as rn
    from {{ ref('raw_erp__customers') }}
),

real_changes as (
    select
        customer_id,
        segment,
        city,
        region,
        updated_at,
        rn,
        concat_ws(
            '~',
            coalesce(cast(segment as varchar), '-'),
            coalesce(city, '-'),
            coalesce(region, '-')
        )     as signature,
        lag(concat_ws(
            '~',
            coalesce(cast(segment as varchar), '-'),
            coalesce(city, '-'),
            coalesce(region, '-')
        ))
            over (
                partition by customer_id
                order by updated_at
            ) as prev_signature
    from deduped
    where rn = 1
),

changes_only as (
    select
        customer_id,
        segment,
        city,
        region,
        updated_at
    from real_changes
    where
        prev_signature is null  {# первая версия — всегда #}
        or signature <> prev_signature
    {# реальное изменение атрибутов #}
),

with_validity as (
    select
        customer_id,
        segment,
        city,
        region,
        updated_at,
        lead(cast(updated_at as date)) over (
            partition by customer_id
            order by updated_at
        )     as valid_to,
        row_number() over (
            partition by customer_id
            order by updated_at
        ) = 1 as is_first,
        row_number() over (
            partition by customer_id
            order by updated_at desc
        ) = 1 as is_current
    from changes_only
)

select
    customer_id,
    segment,
    city,
    region,
    {# Temporal baseline (§2.1): первую наблюдённую версию считаем валидной
       «с рождения сущности» — заказы старше первой версии не выпадают из
       факта при valid-time join (урок R2: звезда теряла 8% выручки).
       floor '1970-01-01' = «верно настолько, насколько нам известно». #}
    case when is_first then date '1970-01-01' else cast(updated_at as date) end as valid_from,
    valid_to,
    is_current
from with_validity
