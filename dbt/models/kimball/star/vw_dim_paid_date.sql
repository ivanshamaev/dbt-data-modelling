{{ config(
    materialized='view',
    tags=['gold', 'dim'],
) }}

{# L4.2/L4.3 · role-playing date: дата ОПЛАТЫ. #}
select
    date_day       as paid_date,
    year_number    as paid_year,
    quarter_number as paid_quarter,
    month_number   as paid_month,
    year_month     as paid_year_month,
    week_number    as paid_week,
    is_weekend     as paid_weekend
from {{ ref('dim_date') }}
