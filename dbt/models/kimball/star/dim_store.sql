{{ config(
    materialized='table',
    tags=['gold', 'dim'],
) }}

{# L4.3 · dim_store: «закрывающееся измерение» (паттерн №6) БЕЗ SCD2 — #}
{# жизненный цикл уже закодирован в opened_at/closed_at (одно событие за 3 года: #}
{# анти-«SCD2-мания», согласовано с int_stores и гл. 7). #}
select
    store_key,
    store_id,
    name,
    format,
    city,
    region,
    opened_at,
    closed_at,
    closed_at is null as is_active,
    opened_at         as valid_from,
    closed_at         as valid_to
from {{ ref('stg_kim_erp__stores') }}
