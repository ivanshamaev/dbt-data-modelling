-- ============================================================================
-- tests/source_contract_*.sql · Контракты ИСТОЧНИКОВ (гл. 3, L2.2).
-- Исполняются на PostgreSQL (вне dbt): генератор обязан держать инварианты,
-- на которых строится будущее reconciliation витрин.
--
-- Запуск: docker exec -i retailco-postgres psql -U postgres -d retailco \
--           < tests/source_contract_no_orphan_lines.sql
-- Каждый файл возвращает НАРУШАЮЩИЕ строки: пустой результат = контракт соблюдён.
-- ============================================================================

-- 1 · Сироты ссылочной целостности: строка/платёж/возврат без родителя.
-- Инвариант: 0 строк (проверено 2026-10-24: 0).
SELECT 'line_without_order' AS violation, count(*)
FROM erp.order_lines l LEFT JOIN erp.orders o USING (order_id)
WHERE o.order_id IS NULL
UNION ALL
SELECT 'payment_without_order', count(*)
FROM erp.payments p LEFT JOIN erp.orders o USING (order_id)
WHERE o.order_id IS NULL
UNION ALL
SELECT 'return_without_line', count(*)
FROM erp.returns r LEFT JOIN erp.order_lines l USING (order_line_id)
WHERE l.order_line_id IS NULL
UNION ALL
SELECT 'order_without_customer', count(*)
FROM erp.orders o LEFT JOIN erp.customers c USING (customer_id)
WHERE c.customer_id IS NULL;
