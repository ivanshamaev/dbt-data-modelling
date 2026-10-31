-- L66: разовая коррекция ошибочного времени оплаты; исходные строки сохраняются.
-- Исполнять при остановленных загрузках после резервной копии источника.
BEGIN;
SELECT pg_advisory_xact_lock(87206310);
CREATE TABLE IF NOT EXISTS meta.course_order_clock_backup (
 order_id bigint PRIMARY KEY, old_row jsonb NOT NULL, repaired_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS meta.course_payment_clock_backup (
 payment_id bigint PRIMARY KEY, old_row jsonb NOT NULL, repaired_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO meta.course_order_clock_backup(order_id,old_row)
SELECT order_id,to_jsonb(o) FROM erp.orders o WHERE paid_at<order_ts ON CONFLICT DO NOTHING;
INSERT INTO meta.course_payment_clock_backup(payment_id,old_row)
SELECT p.payment_id,to_jsonb(p) FROM erp.payments p INNER JOIN erp.orders o ON o.order_id=p.order_id
WHERE o.paid_at<o.order_ts AND p.paid_ts=o.paid_at ON CONFLICT DO NOTHING;
UPDATE erp.payments p SET paid_ts=o.order_ts+interval '5 minute',
 updated_at=greatest(p.updated_at,(SELECT max(sim_date) FROM meta.simulated_days)::timestamptz+interval '23 hour')
FROM erp.orders o WHERE o.order_id=p.order_id AND o.paid_at<o.order_ts AND p.paid_ts=o.paid_at;
UPDATE erp.orders SET paid_at=order_ts+interval '5 minute',
 updated_at=greatest(updated_at,(SELECT max(sim_date) FROM meta.simulated_days)::timestamptz+interval '23 hour')
WHERE paid_at<order_ts;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM erp.orders WHERE paid_at<order_ts OR shipped_at<paid_at OR delivered_at<shipped_at)
 THEN RAISE EXCEPTION 'L66: порядок событий не восстановлен'; END IF;
END $$;
COMMIT;
