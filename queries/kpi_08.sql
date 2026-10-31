-- KPI 8 · Retention-когорты по месяцам регистрации (своя гранулярность,
-- производный датасет). Это количества активных клиентов, не коэффициенты retention.
-- before_registration отдельно показывает продажи до регистрации в синтетике.
SET CATALOG default_catalog;
USE analytics;

with activity as (
    select
        c.customer_id,
        date_format(c.registered_at, '%Y-%m')                  as cohort_month,
        date_format(f.order_date, '%Y-%m')                     as active_month,
        -- L35: period_diff/months_between — MySQL-функции, в StarRocks нет;
        -- точная месячная разница = (y*12+m) − (y*12+m)
        (year(f.order_date) * 12 + month(f.order_date))
          - (year(c.registered_at) * 12 + month(c.registered_at)) as month_no
    from fct_sales f
    join dim_customer c on c.customer_sk_v = f.customer_sk_v
)
select
    cohort_month,
    count(distinct case when month_no < 0 then customer_id end) as before_registration,
    count(distinct case when month_no = 0 then customer_id end) as m0,
    count(distinct case when month_no = 1 then customer_id end) as m1,
    count(distinct case when month_no = 2 then customer_id end) as m2,
    count(distinct case when month_no = 3 then customer_id end) as m3,
    count(distinct case when month_no >= 6 then customer_id end) as m6_plus
from activity
group by 1
order by 1;
