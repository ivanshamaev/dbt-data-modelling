-- ============================================================================
-- queries/oltp_vs_olap.sql · Замер «почему аналитический запрос «в лоб» по ERP
-- — это анти-паттерн» (гл. 2, L1.2).
--
-- Запуск (стенд поднят, seed выполнен):
--   make -C . shell? нет — напрямую в контейнер PG:
--   docker exec -i retailco-postgres psql -U postgres -d retailco \
--     < queries/oltp_vs_olap.sql
--
-- Две части: (A) точечный OLTP-запрос — то, для чего ERP спроектирован;
-- (B) аналитический скан с EXPLAIN (ANALYZE, BUFFERS) — то, что хочет BI.
-- ============================================================================

\echo '=== A · OLTP: точечное чтение заказа по номеру (индекс, миллисекунды) ==='
EXPLAIN (ANALYZE, BUFFERS, TIMING OFF)
SELECT o.order_id, o.status, o.order_ts, c.segment, count(ol.order_line_id), sum(ol.line_amount)
FROM erp.orders o
JOIN erp.customers c USING (customer_id)
JOIN erp.order_lines ol USING (order_id)
WHERE o.order_no = 'ORD-0469369'  -- реальный номер на стенде (взят последний по order_ts)
GROUP BY 1, 2, 3, 4;

\echo ''
\echo '=== B · OLAP: выручка по сегментам × месяцам за год (скан ~1.3M строк) ==='
EXPLAIN (ANALYZE, BUFFERS, TIMING OFF)
SELECT c.segment,
       date_trunc('month', o.order_ts) AS month,
       sum(ol.line_amount)             AS revenue
FROM erp.orders o
JOIN erp.order_lines ol USING (order_id)
JOIN erp.customers  c  USING (customer_id)
WHERE o.order_ts >= now() - interval '1 year'
GROUP BY 1, 2
ORDER BY 1, 2;

\echo ''
\echo '=== Контроль: объёмы, которые трогает запрос B ==='
SELECT (SELECT count(*) FROM erp.orders)      AS orders_cnt,
       (SELECT count(*) FROM erp.order_lines) AS lines_cnt,
       (SELECT count(*) FROM erp.customers)   AS customers_cnt;
