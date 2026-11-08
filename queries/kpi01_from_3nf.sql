-- ============================================================================
-- KPI №1 из 3NF-ядра (L4.1): выручка по дням × магазинам × каналам.
-- Запуск: mysql-клиент StarRocks после `make build`.
--
-- СЕМАНТИКА ВЫРУЧКИ (фиксируется здесь; обязана совпасть в fact_sales (L4.4)
-- и vault-март (L5.3) — иначе reconciliation не сойдётся):
--   gross revenue = строки АКТУАЛЬНЫХ версий заказов в статусах
--   paid / shipped / delivered / returned (оплаченные; cancelled и created
--   исключены; возвраты считаются отдельно — KPI №5, net = gross − refunds).
--
-- «Боль» нормализации: 4 join'а для простейшего отчёта (в звезде будет 2–3).
-- ============================================================================

SET CATALOG iceberg;
USE inmon_core;

select
    cast(o.order_ts as date) as sales_date,
    s.store_id,
    s.format                as store_format,
    o.channel,
    count(distinct o.order_id) as orders_cnt,
    sum(l.line_amount)      as revenue_amt
from int_orders o
join int_order_states os
    on os.order_id = o.order_id and os.is_current
join int_order_lines l
    on l.order_id = o.order_id and l.is_current
join int_stores s
    on s.store_id = o.store_id
where os.status in ('paid', 'shipped', 'delivered', 'returned')
group by 1, 2, 3, 4
order by 1, 2, 5 desc;

-- EXPLAIN-выжимку (scan rows/bytes, join-план) снять на стенде M0+ и приложить
-- к гл. 6 — артефакт для сравнения со звездой в гл. 14 (методика — гл. 14).
