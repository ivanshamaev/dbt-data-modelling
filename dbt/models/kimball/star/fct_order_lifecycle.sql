{#INSERT в PRIMARY KEY = upsert строки заказа #}
{{ config(
    materialized='incremental',
    incremental_strategy='default',
    table_type='PRIMARY',
    keys=['order_key'],
    order_by=['order_key'],
    tags=['gold', 'fct'],
) }}

-- L4.4 · fct_order_lifecycle: ACCUMULATING SNAPSHOT (паттерн №2) — одна строка
-- на заказ, «дырки заполняются» по мере прогресса: created→paid→shipped→delivered.
-- KPI №4 (воронка и время переходов) — прямой SELECT отсюда.
-- Инкрементальность: идемпотентный upsert всех заказов, включая старые переходы;
-- лаги пересчитываются на каждой эмиссии заново — строка всегда консистентна.
select
    o.order_key,
    o.order_no,                                        -- degenerate dimension
    dc.customer_sk_v,
    s.store_key,
    o.channel,
    o.status                                            as current_status,
    o.order_ts,
    o.paid_at,
    o.shipped_at,
    o.delivered_at,
    o.cancelled_at,
    cast(o.order_ts as date)                            as order_date,
    cast(o.paid_at as date)                             as paid_date,
    cast(o.delivered_at as date)                        as delivered_date,
    timestampdiff(second, o.order_ts, o.paid_at)        as lag_create_to_paid_sec,
    timestampdiff(second, o.paid_at, o.shipped_at)      as lag_paid_to_shipped_sec,
    timestampdiff(second, o.shipped_at, o.delivered_at) as lag_shipped_to_delivered_sec,
    o.updated_at                                        as order_updated_at
from {{ ref('stg_kim_erp__orders') }} o
inner join {{ ref('dim_customer') }} dc
    on
        o.customer_id = dc.customer_id
        and dc.valid_from <= cast(o.order_ts as date)
        and (dc.valid_to is null or dc.valid_to > cast(o.order_ts as date))
inner join {{ ref('dim_store') }} s
    on o.store_id = s.store_id
