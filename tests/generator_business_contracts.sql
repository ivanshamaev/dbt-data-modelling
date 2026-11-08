-- PostgreSQL: бизнес-связи источника, а не только совпадение витрин DWH.
SET timezone = 'UTC';
CREATE TEMP VIEW generator_business_violations AS
WITH cutoff AS (
    SELECT (max(sim_date) + 1)::timestamptz AS at FROM meta.simulated_days
), returned AS (
    SELECT l.order_id, sum(r.qty) AS qty, sum(r.refund_amount) AS amount, max(r.return_ts) AS last_at
    FROM erp.returns r JOIN erp.order_lines l USING (order_line_id) GROUP BY l.order_id
), bought AS (
    SELECT order_id, sum(qty) AS qty, sum(line_amount) AS amount FROM erp.order_lines GROUP BY order_id
), payments AS (
    SELECT order_id, sum(amount - refunded_amount) AS net FROM erp.payments GROUP BY order_id
)
SELECT 'order_customer_time' AS rule, count(*) AS violations
FROM erp.orders o JOIN erp.customers c USING (customer_id)
WHERE o.order_ts < c.registered_at OR o.order_ts >= c.deleted_at
UNION ALL
SELECT 'order_store_time', count(*) FROM erp.orders o JOIN erp.stores s USING (store_id)
WHERE o.order_ts::date < s.opened_at OR o.order_ts::date > s.closed_at
UNION ALL
SELECT 'order_store_channel', count(*) FROM erp.orders o JOIN erp.stores s USING (store_id)
WHERE (o.channel = 'shop') = (s.format = 'online')
UNION ALL
SELECT 'line_product_time', count(*) FROM erp.order_lines l JOIN erp.orders o USING (order_id)
JOIN erp.products p USING (product_id) WHERE o.order_ts::date < p.launched_at
UNION ALL
SELECT 'line_assortment', count(*) FROM erp.order_lines l JOIN erp.orders o USING (order_id)
LEFT JOIN meta.assortment a ON a.store_id = o.store_id AND a.product_id = l.product_id WHERE a.product_id IS NULL
UNION ALL
SELECT 'order_total_and_lines', count(*) FROM erp.orders o LEFT JOIN bought b USING (order_id)
WHERE b.order_id IS NULL OR o.total_amount <> b.amount
UNION ALL
SELECT 'line_amount_rule', count(*) FROM erp.order_lines
WHERE line_amount <> round(qty::numeric * unit_price * (100 - discount_pct) / 100)
UNION ALL
SELECT 'payment_net_balance', count(*) FROM erp.orders o LEFT JOIN payments p USING (order_id)
LEFT JOIN returned r USING (order_id)
WHERE o.paid_at IS NOT NULL AND p.net IS DISTINCT FROM
    CASE WHEN o.status = 'cancelled' THEN 0 ELSE o.total_amount - coalesce(r.amount, 0) END
UNION ALL
SELECT 'unpaid_has_payment', count(*) FROM erp.payments p JOIN erp.orders o USING (order_id)
WHERE o.paid_at IS NULL OR p.paid_ts <> o.paid_at
UNION ALL
SELECT 'payment_refund_bounds', count(*) FROM erp.payments
WHERE refunded_amount < 0 OR refunded_amount > amount OR refunded_at < paid_ts OR updated_at < refunded_at
UNION ALL
SELECT 'payment_status_amount', count(*) FROM erp.payments WHERE
    (refunded_amount = 0 AND (status NOT IN ('captured', 'authorized') OR refunded_at IS NOT NULL))
    OR (refunded_amount > 0 AND (refunded_at IS NULL OR status <>
        CASE WHEN refunded_amount = amount THEN 'refunded' ELSE 'partially_refunded' END))
UNION ALL
SELECT 'return_after_delivery', count(*) FROM erp.returns r JOIN erp.order_lines l USING (order_line_id)
JOIN erp.orders o USING (order_id) WHERE o.delivered_at IS NULL OR r.return_ts < o.delivered_at
UNION ALL
SELECT 'return_qty_and_money', count(*) FROM (
    SELECT l.order_line_id FROM erp.order_lines l JOIN erp.returns r USING (order_line_id)
    GROUP BY l.order_line_id, l.qty, l.line_amount
    HAVING sum(r.qty) > l.qty OR sum(r.refund_amount) <> round(l.line_amount::numeric * sum(r.qty) / l.qty)
) invalid
UNION ALL
SELECT 'returned_order_complete', count(*) FROM erp.orders o LEFT JOIN returned r USING (order_id)
JOIN bought b USING (order_id) WHERE (o.status = 'returned') IS DISTINCT FROM (coalesce(r.qty, 0) = b.qty)
    OR (o.status = 'returned' AND o.updated_at < r.last_at)
UNION ALL
SELECT 'order_lifecycle', count(*) FROM erp.orders
WHERE paid_at < order_ts OR shipped_at < paid_at OR delivered_at < shipped_at OR cancelled_at < order_ts
    OR (shipped_at IS NOT NULL AND paid_at IS NULL) OR (delivered_at IS NOT NULL AND shipped_at IS NULL)
    OR updated_at < greatest(order_ts, paid_at, shipped_at, delivered_at, cancelled_at)
UNION ALL
SELECT 'no_future_order_events', count(*) FROM erp.orders CROSS JOIN cutoff
WHERE greatest(order_ts, paid_at, shipped_at, delivered_at, cancelled_at, updated_at) >= cutoff.at
UNION ALL
SELECT 'no_future_payment_events', count(*) FROM erp.payments CROSS JOIN cutoff
WHERE greatest(paid_ts, refunded_at, updated_at) >= cutoff.at
UNION ALL
SELECT 'no_future_return_events', count(*) FROM erp.returns CROSS JOIN cutoff WHERE return_ts >= cutoff.at
UNION ALL
SELECT 'promotion_status_dates', count(*) FROM crm.promotions CROSS JOIN cutoff
WHERE status <> CASE WHEN cutoff.at::date - 1 > ends_at THEN 'closed'
    WHEN cutoff.at::date - 1 >= starts_at THEN 'active' ELSE 'planned' END OR updated_at >= cutoff.at
UNION ALL
SELECT 'crm_delivery_time', count(*) FROM crm.promo_participation CROSS JOIN cutoff
WHERE sync_ts < attached_at OR sync_ts >= cutoff.at
UNION ALL
SELECT 'crm_only_intentional_orphans', count(*) FROM crm.promo_participation pp
LEFT JOIN erp.orders o USING (order_no) WHERE o.order_id IS NULL AND pp.order_no NOT LIKE 'ORD-X%'
UNION ALL
SELECT 'crm_order_promotion_time', count(*) FROM crm.promo_participation pp JOIN erp.orders o USING (order_no)
JOIN crm.promotions p USING (promo_id) WHERE o.order_ts::date NOT BETWEEN p.starts_at AND p.ends_at
    OR pp.attached_at <> o.order_ts
UNION ALL
SELECT 'crm_duplicate_participation', count(*) FROM (
    SELECT promo_id, order_no FROM crm.promo_participation GROUP BY 1, 2 HAVING count(*) > 1
) invalid
UNION ALL
SELECT 'inventory_reserved', count(*) FROM erp.inventory WHERE qty_reserved > qty_on_hand OR qty_reserved < 0 OR qty_on_hand < 0
UNION ALL
SELECT 'inventory_store_product_time', count(*) FROM erp.inventory i
JOIN erp.stores s USING (store_id) JOIN erp.products p USING (product_id)
WHERE i.snap_date < s.opened_at OR i.snap_date > s.closed_at OR i.snap_date < p.launched_at
UNION ALL
SELECT 'inventory_balance_equation', count(*) FROM meta.inventory_movements
WHERE closing_qty <> opening_qty + received_qty - shipped_qty + returned_qty OR reserved_qty > closing_qty
UNION ALL
SELECT 'inventory_day_continuity', count(*) FROM (
    SELECT opening_qty, lag(closing_qty) OVER (PARTITION BY store_id, product_id ORDER BY snap_date) AS previous
    FROM meta.inventory_movements
) movement WHERE previous IS NOT NULL AND opening_qty <> previous
UNION ALL
SELECT 'inventory_matches_movements', count(*) FROM erp.inventory i
LEFT JOIN meta.inventory_movements m USING (snap_date, store_id, product_id)
WHERE m.snap_date IS NULL OR i.qty_on_hand <> m.closing_qty OR i.qty_reserved <> m.reserved_qty;

TABLE generator_business_violations;
DO $$
DECLARE failures jsonb;
BEGIN
    SELECT jsonb_object_agg(rule, violations) INTO failures FROM generator_business_violations WHERE violations <> 0;
    IF failures IS NOT NULL THEN RAISE EXCEPTION 'Нарушены бизнес-связи генератора: %', failures; END IF;
    RAISE NOTICE 'PASS: 28 бизнес-контрактов генератора';
END $$;
