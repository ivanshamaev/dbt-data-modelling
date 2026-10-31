{{ config(
    materialized='view',
    tags=['gold', 'dim'],
) }}

{# L4.2/L4.3 · role-playing date: дата ЗАКАЗА (role-playing через алиасы, #}
{# физическая таблица одна — dim_date). #}
select
    date_day       as order_date,
    year_number    as order_year,
    quarter_number as order_quarter,
    month_number   as order_month,
    year_month     as order_year_month,
    week_number    as order_week,
    is_weekend     as order_weekend
from {{ ref('dim_date') }}
