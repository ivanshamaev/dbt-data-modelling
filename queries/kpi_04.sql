-- KPI 4 · Воронка заказов и среднее время переходов (accumulating snapshot, паттерн №2).
SET CATALOG default_catalog;
USE analytics;

with funnel as (
    select
        count(*)                                               as created_cnt,
        count(paid_at)                                         as paid_cnt,
        count(shipped_at)                                      as shipped_cnt,
        count(delivered_at)                                    as delivered_cnt,
        count(cancelled_at)                                    as cancelled_cnt
    from fact_order_lifecycle
)
select
    created_cnt,
    paid_cnt,
    shipped_cnt,
    delivered_cnt,
    cancelled_cnt,
    avg(lag_create_to_paid_sec) / 60.0              as avg_min_create_to_paid,
    avg(lag_paid_to_shipped_sec) / 60.0             as avg_min_paid_to_shipped,
    avg(lag_shipped_to_delivered_sec) / 60.0        as avg_min_shipped_to_delivered
from fact_order_lifecycle, funnel
group by created_cnt, paid_cnt, shipped_cnt, delivered_cnt, cancelled_cnt;
