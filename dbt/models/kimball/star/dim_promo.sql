{{ config(
    materialized='table',
    tags=['gold', 'dim'],
) }}

{# L4.3 · dim_promo из CRM со SCD2: продления и досрочные остановки акций #}
{# (паттерн №3 из второго источника) видны как версии. #}
{# CRM не имеет int_-ядра (рамка §8.12: ровно 1 dim) — версию разворачиваем #}
{# прямо из bronze-потока raw_crm__promotions той же механикой, что int_-слой: #}
{# L62: последнее наблюдение каждого бизнес-дня (promo_id, date(updated_at)) -> сигнатуры -> фильтр «тихих версий» -> valid_from/to. #}
with deduped as (
    select
        promo_id,
        name,
        mechanics,
        discount_value,
        starts_at,
        ends_at,
        status,
        updated_at,
        row_number() over (
            partition by promo_id, cast(updated_at as date)
            order by updated_at desc, _loaded_at desc
        ) as rn
    from {{ ref('raw_crm__promotions') }}
),

real_changes as (
    select
        promo_id,
        name,
        mechanics,
        discount_value,
        starts_at,
        ends_at,
        status,
        updated_at,
        rn,
        concat_ws(
            '~',
            coalesce(cast(name as varchar), '-'),
            coalesce(cast(mechanics as varchar), '-'),
            coalesce(cast(discount_value as varchar), '-'),
            coalesce(cast(starts_at as varchar), '-'),
            coalesce(cast(ends_at as varchar), '-'),
            coalesce(cast(status as varchar), '-')
        )     as signature,
        lag(concat_ws(
            '~',
            coalesce(cast(name as varchar), '-'),
            coalesce(cast(mechanics as varchar), '-'),
            coalesce(cast(discount_value as varchar), '-'),
            coalesce(cast(starts_at as varchar), '-'),
            coalesce(cast(ends_at as varchar), '-'),
            coalesce(cast(status as varchar), '-')
        ))
            over (
                partition by promo_id
                order by updated_at
            ) as prev_signature
    from deduped
    where rn = 1
),

changes_only as (
    select
        promo_id,
        name,
        mechanics,
        discount_value,
        starts_at,
        ends_at,
        status,
        updated_at
    from real_changes
    where prev_signature is null or signature <> prev_signature
),

with_validity as (
    select
        promo_id,
        name,
        mechanics,
        discount_value,
        starts_at,
        ends_at,
        status,
        updated_at,
        lead(updated_at) over (
            partition by promo_id
            order by updated_at
        )     as valid_to,
        row_number() over (
            partition by promo_id
            order by updated_at desc
        ) = 1 as is_current
    from changes_only
)

select
    {{ hash_key(['promo_id', 'cast(updated_at as date)']) }} as promo_sk_v,
    {{ hash_key('promo_id') }}                               as promo_key,
    promo_id,
    name,
    mechanics,
    discount_value,
    starts_at,
    ends_at,
    status,
    cast(updated_at as date)                                 as valid_from,
    cast(valid_to as date)                                   as valid_to,
    is_current
from with_validity
