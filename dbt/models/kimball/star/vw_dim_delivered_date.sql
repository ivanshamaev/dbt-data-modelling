{{ config(
    materialized='view',
    tags=['gold', 'dim'],
) }}

{# L4.2/L4.3 · role-playing date: дата ДОСТАВКИ. #}
select
    date_day       as delivered_date,
    year_number    as delivered_year,
    quarter_number as delivered_quarter,
    month_number   as delivered_month,
    year_month     as delivered_year_month,
    week_number    as delivered_week,
    is_weekend     as delivered_weekend
from {{ ref('dim_date') }}
