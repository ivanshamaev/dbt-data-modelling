-- ============================================================================
-- KPI №4 ИЗ ANCHOR: воронка и время переходов — вехи как отдельные
-- 6NF-атрибуты (attr_order_paid_at и т.д.), сведённые широким view latest_anc_order
-- (codegen-макрос). Один из «пяти ответов» на KPI №4 (гл. 14).
-- ============================================================================

SET CATALOG iceberg;
USE anchor_core;

select
    count(*)                                                 as orders_cnt,
    count(paid_at)                                           as paid_cnt,
    count(shipped_at)                                        as shipped_cnt,
    count(delivered_at)                                      as delivered_cnt,
    avg(timestampdiff(SECOND, order_ts, paid_at))            / 60.0 as avg_min_create_to_paid,
    avg(timestampdiff(SECOND, paid_at, shipped_at))          / 60.0 as avg_min_paid_to_shipped,
    avg(timestampdiff(SECOND, shipped_at, delivered_at))     / 60.0 as avg_min_shipped_to_delivered
from latest_anc_order;
