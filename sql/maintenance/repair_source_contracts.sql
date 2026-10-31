-- Однократная миграция синтетических данных L51/L52, с архивом изменённых записей.
-- Не пересоздаёт источники и не проживает день. Повтор после успешного выполнения ничего не меняет.
BEGIN;
CREATE TABLE IF NOT EXISTS meta.course_repair_l51 (
    order_id bigint NOT NULL,
    original_updated_at timestamptz NOT NULL,
    repaired_updated_at timestamptz NOT NULL,
    saved_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (order_id, original_updated_at)
);
INSERT INTO meta.course_repair_l51 (order_id, original_updated_at, repaired_updated_at)
SELECT order_id, updated_at, greatest(updated_at, order_ts, paid_at, shipped_at, delivered_at, cancelled_at)
FROM erp.orders
WHERE updated_at < greatest(order_ts, paid_at, shipped_at, delivered_at, cancelled_at)
ON CONFLICT DO NOTHING;
UPDATE erp.orders
SET updated_at = greatest(updated_at, order_ts, paid_at, shipped_at, delivered_at, cancelled_at)
WHERE updated_at < greatest(order_ts, paid_at, shipped_at, delivered_at, cancelled_at);

CREATE TABLE IF NOT EXISTS meta.course_repair_l52 (
    return_id bigint PRIMARY KEY,
    original_row jsonb NOT NULL,
    saved_at timestamptz NOT NULL DEFAULT now()
);
CREATE TEMP TABLE course_return_allocation ON COMMIT DROP AS
WITH invalid_lines AS (
    SELECT r.order_line_id
    FROM erp.returns r
    INNER JOIN erp.order_lines l ON l.order_line_id = r.order_line_id
    GROUP BY r.order_line_id
    HAVING sum(r.qty) > max(l.qty)
), ranked AS (
    SELECT r.return_id, r.qty, r.refund_amount, l.qty AS bought_qty,
           coalesce(sum(r.qty) OVER (
               PARTITION BY r.order_line_id ORDER BY r.return_ts, r.return_id
               ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
           ), 0) AS previous_qty
    FROM erp.returns r
    INNER JOIN erp.order_lines l ON l.order_line_id = r.order_line_id
    INNER JOIN invalid_lines bad ON bad.order_line_id = r.order_line_id
)
SELECT return_id, qty AS old_qty, refund_amount AS old_refund,
       greatest(0, least(qty, bought_qty - previous_qty))::integer AS allowed_qty
FROM ranked;
INSERT INTO meta.course_repair_l52 (return_id, original_row)
SELECT r.return_id, to_jsonb(r)
FROM erp.returns r
INNER JOIN course_return_allocation a ON a.return_id = r.return_id
WHERE a.allowed_qty <> a.old_qty
ON CONFLICT DO NOTHING;
SELECT count(*) FILTER (WHERE allowed_qty = 0) AS duplicate_returns_to_remove,
       count(*) FILTER (WHERE allowed_qty > 0 AND allowed_qty < old_qty) AS partial_returns_to_reduce
FROM course_return_allocation;
DELETE FROM erp.returns r USING course_return_allocation a
WHERE a.return_id = r.return_id AND a.allowed_qty = 0;
UPDATE erp.returns r
SET qty = a.allowed_qty,
    refund_amount = round(a.old_refund::numeric * a.allowed_qty / a.old_qty)::bigint
FROM course_return_allocation a
WHERE a.return_id = r.return_id AND a.allowed_qty > 0 AND a.allowed_qty < a.old_qty;
COMMIT;
