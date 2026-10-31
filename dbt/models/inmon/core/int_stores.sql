{{ config(
    materialized='table',
    schema='iceberg.inmon_core',
) }}

{# L4.1 · магазины: атрибуты меняются слишком редко для отдельной таблицы истории #}
{# (закрытие — единственное событие, паттерн №6) — осознанное решение против #}
{# «SCD2-мании»: история жизни уже закодирована в opened_at/closed_at. #}
select
    store_id,
    store_key,
    name,
    format,
    city,
    region,
    opened_at,
    closed_at,
    closed_at is not null as is_closed
from {{ ref('stg_in_erp__stores') }}
