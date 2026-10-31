-- ============================================================================
-- KPI №4 ИЗ 3NF-ЯДРА: воронка и время переходов — темпоральный запрос к
-- истории состояний (в звезде это accumulating snapshot, здесь — window по
-- версиям). Один из «пяти ответов» на KPI №4 (гл. 14).
-- ============================================================================

SET CATALOG iceberg;
USE inmon_core;

select
    count(*)                                        as orders_cnt,
    count(os.paid_at)                               as paid_cnt,
    count(os.shipped_at)                            as shipped_cnt,
    count(os.delivered_at)                          as delivered_cnt,
    count(os.cancelled_at)                          as cancelled_cnt,
    avg(timestampdiff(SECOND, o.order_ts, os.paid_at))     / 60.0 as avg_min_create_to_paid,
    avg(timestampdiff(SECOND, os.paid_at, os.shipped_at))  / 60.0 as avg_min_paid_to_shipped,
    avg(timestampdiff(SECOND, os.shipped_at, os.delivered_at)) / 60.0 as avg_min_shipped_to_delivered
from int_orders o
join int_order_states os
    on os.order_id = o.order_id and os.is_current;
