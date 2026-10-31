-- Полнота окна PIT и разрешимость указателя в единственную версию спутника.
with horizon as (
    select max(cast(order_ts as date)) as last_date
    from {{ ref('stg_dv_erp__orders') }}
),
coverage as (
    select
        h.customer_hk,
        d.last_date,
        count(p.as_of_date) as days_count,
        min(p.as_of_date) as first_day,
        max(p.as_of_date) as last_day
    from {{ ref('h_customer') }} h
    cross join horizon d
    left join {{ ref('pit_customer') }} p on p.customer_hk = h.customer_hk
    group by h.customer_hk, d.last_date
)
select 'coverage' as violation, customer_hk
from coverage
where
    (last_date is null and days_count <> 0)
    or (last_date is not null and (
        days_count <> 180
        or first_day <> date_sub(last_date, interval 179 day)
        or last_day <> last_date
    ))
union all
select 'unresolved_pointer' as violation, p.customer_hk
from {{ ref('pit_customer') }} p
left join {{ ref('s_customer_erp') }} s
    on s.customer_hk = p.customer_hk
    and s.effective_from = p.s_customer_erp_eff_from
    and s.hash_diff = p.s_customer_erp_diff
    and s.load_ts = p.s_customer_erp_load_ts
where s.customer_hk is null
