{{ config(
    materialized='view',
    schema='iceberg.vault_marts',
    tags=['vault', 'mart'],
) }}

{# Полное LTV по последнему известному состоянию сегмента дня заказа.
   Это текущая интерпретация истории: дневные наблюдения выбираются по load_ts.
   Прямой as-of использует всю историю; отдельный PIT охватывает только 180 дней.
   Сравнение двух механик в kpi07_from_vault.sql ограничено одним диапазоном. #}
with last_lines as (
    select
        order_line_hk,
        order_hk,
        line_amount,
        order_ts,
        row_number() over (
            partition by order_line_hk
            order by line_updated_at desc, load_date desc
        ) as rn
    from {{ ref('l_order_line') }}
),

segments as (
    select
        customer_hk,
        segment,
        effective_from,
        lead(effective_from) over (
            partition by customer_hk
            order by effective_from
        ) as next_from
    from (
        select
            c.customer_hk,
            c.segment,
            c.effective_from,
            row_number() over (
                partition by c.customer_hk, c.effective_from
                order by c.load_ts desc
            ) as rn
        from {{ ref('s_customer_erp') }} c
    ) d
    where rn = 1
)

select
    s.segment,
    count(distinct lc.customer_hk) as customers_cnt,
    count(distinct ol.order_hk)    as orders_cnt,
    sum(ol.line_amount)            as ltv_amt
from last_lines ol
inner join {{ ref('b_order_effective_state') }} oes
    on ol.order_hk = oes.order_hk
inner join {{ ref('l_order_customer') }} lc
    on ol.order_hk = lc.order_hk
inner join segments s
    on
        lc.customer_hk = s.customer_hk
        and s.effective_from <= cast(ol.order_ts as date)
        and (s.next_from is null or s.next_from > cast(ol.order_ts as date))
where
    ol.rn = 1
    and oes.status in ('paid', 'shipped', 'delivered', 'returned')
group by 1
