{{ config(
    materialized='table',
    schema='iceberg.kimball_stage',
) }}

{# L4.3 · промо-акции CRM: ретро-коррекции сроков/статусов (паттерн №3 из #}
{# второго источника) схлопываются в актуальную версию. Стыковка конвенций: #}
{# promo_id ('PR-2024-017') сохраняем как бизнес-номер + durable promo_key. #}
with ranked as (
    select
        promo_id,
        name,
        mechanics,
        discount_value,
        starts_at,
        ends_at,
        status,
        updated_at,
        _batch_id,
        _loaded_at,
        _source,
        _ingest_date,
        row_number() over (
            partition by promo_id
            order by updated_at desc, _loaded_at desc
        ) as rn
    from {{ ref('raw_crm__promotions') }}
)

select
    promo_id,
    name,
    mechanics,
    discount_value,
    starts_at,
    ends_at,
    status,
    updated_at,
    {{ hash_key('promo_id') }} as promo_key
from ranked
where rn = 1
