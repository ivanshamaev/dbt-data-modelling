{{ config(
    materialized='table',
    schema='iceberg.vault_core',
    tags=['vault', 'pit'],
) }}

-- L56: 180 бизнес-дней до последнего заказа включительно; поздние версии учитываются.
-- Полная реконструкция ограниченного окна, без зависимости от старого max(PIT).
-- L63: таблица БЕЗ партиций. Iceberg OVERWRITE партиционированной таблицы
-- сохраняет отсутствующие во входе партиции даже с dynamic_overwrite=FALSE.
with horizon as (
    select max(cast(order_ts as date)) as last_date from {{ ref('stg_dv_erp__orders') }}
),
dates as (
    select cast(date_sub(h.last_date, interval i day) as date) as as_of_date
    from horizon h
    cross join table(generate_series(0, 179)) t(i)
    where h.last_date is not null
),
grid as (
    select d.as_of_date, h.customer_hk
    from dates d
    cross join {{ ref('h_customer') }} h
),
ranked as (
    select
        g.as_of_date,
        g.customer_hk,
        s.hash_diff as s_customer_erp_diff,
        s.effective_from as s_customer_erp_eff_from,
        s.load_ts as s_customer_erp_load_ts,
        row_number() over (
            partition by g.customer_hk, g.as_of_date
            order by s.effective_from desc, s.load_ts desc
        ) as rn
    from grid g
    left join {{ ref('s_customer_erp') }} s
        on s.customer_hk = g.customer_hk and s.effective_from <= g.as_of_date
)
select as_of_date, customer_hk, s_customer_erp_diff, s_customer_erp_eff_from, s_customer_erp_load_ts
from ranked
where rn = 1
