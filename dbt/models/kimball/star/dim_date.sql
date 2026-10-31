{{ config(
    materialized='table',
    table_type='PRIMARY',
    keys=['date_day'],
    order_by=['date_day'],
    tags=['gold', 'dim'],
) }}

-- L4.3 · dim_date: календарное измерение, int-генерация (гл. 8 плана).
-- Диапазон: 2023-01-01 (раньше начала истории ~2023-09) … current_date + 1 год
-- (плановые промо CRM заканчиваются в будущем).
-- generate_series(int, int) + date_add — переносимый трюк без рекурсивных CTE;
-- нумерация day_of_week в MySQL-стиле: 1 = воскресенье.
select
    cast(date_add(date '2023-01-01', interval seq day) as date)                       as date_day,
    year(cast(date_add(date '2023-01-01', interval seq day) as date))                 as year_number,
    quarter(cast(date_add(date '2023-01-01', interval seq day) as date))              as quarter_number,
    month(cast(date_add(date '2023-01-01', interval seq day) as date))                as month_number,
    date_format(cast(date_add(date '2023-01-01', interval seq day) as date), '%Y-%m') as year_month,
    week(cast(date_add(date '2023-01-01', interval seq day) as date))                 as week_number,
    dayofweek(cast(date_add(date '2023-01-01', interval seq day) as date))            as day_of_week,
    case when dayofweek(cast(date_add(date '2023-01-01', interval seq day) as date)) in (1, 7)
         then true else false end                                                     as is_weekend
from table(generate_series(
    0,
    datediff(date_add(current_date(), interval 1 year), date '2023-01-01')
)) t(seq)
