{{ config(
    materialized='view',
    schema='iceberg.inmon_marts',
    tags=['inmon', 'mart'],
) }}

{# M4.4 · dm_customer_ltv: KPI №7 из 3NF — LTV по сегментам НА КОНЕЦ ДНЯ ЗАКАЗА. #}
{# Inmon-механика ответа: valid-time join к версионным атрибутам ядра #}
{# (int_customer_attributes). Контраст гл. 8: звезда решает тот же вопрос #}
{# join'ом по SK строки версии, vault — as-of к спутнику, anchor — valid-time #}
{# срезом. Пять механик, одна цифра — сверка R2/R4. #}
select
    a.segment,
    count(distinct o.customer_id)                        as customers_cnt,
    count(distinct l.order_id)                           as orders_cnt,
    sum(l.line_amount)                                   as ltv_amt
from {{ ref('int_order_lines') }} l
inner join {{ ref('int_orders') }} o
    on l.order_id = o.order_id
inner join {{ ref('int_order_states') }} os
    on
        l.order_id = os.order_id
        and os.is_current
inner join {{ ref('int_customer_attributes') }} a
    on
        o.customer_id = a.customer_id
        and a.valid_from <= cast(o.order_ts as date)
        and (a.valid_to is null or a.valid_to > cast(o.order_ts as date))
where
    l.is_current
    and os.status in ('paid', 'shipped', 'delivered', 'returned')
group by 1
