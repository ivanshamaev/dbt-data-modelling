-- Строгая проверка исправляемых L51/L52/L64/L66: ненулевой код psql при нарушении.
SELECT count(*) AS orders_with_old_watermark
FROM erp.orders
WHERE updated_at < greatest(order_ts,paid_at,shipped_at,delivered_at,cancelled_at);
SELECT count(*) AS lines_with_excess_returns
FROM (
    SELECT r.order_line_id FROM erp.returns r
    INNER JOIN erp.order_lines l ON l.order_line_id=r.order_line_id
    GROUP BY r.order_line_id HAVING sum(r.qty)>max(l.qty)
) violations;
-- Запланированная дата акции не является временем изменения её записи.
SELECT count(*) AS promotions_with_future_watermark
FROM crm.promotions
WHERE updated_at >= (SELECT max(sim_date)+1 FROM meta.simulated_days);
SELECT count(*) AS orders_with_reversed_lifecycle
FROM erp.orders WHERE paid_at<order_ts OR shipped_at<paid_at OR delivered_at<shipped_at;
DO $$
BEGIN
    IF EXISTS(SELECT 1 FROM erp.orders WHERE paid_at<order_ts OR shipped_at<paid_at OR delivered_at<shipped_at)
    THEN RAISE EXCEPTION 'L66: обратный порядок lifecycle-событий'; END IF;
    IF EXISTS (
        SELECT 1 FROM erp.orders
        WHERE updated_at < greatest(order_ts,paid_at,shipped_at,delivered_at,cancelled_at)
    ) THEN RAISE EXCEPTION 'L51: watermark отстаёт от события'; END IF;
    IF EXISTS (
        SELECT r.order_line_id FROM erp.returns r
        INNER JOIN erp.order_lines l ON l.order_line_id=r.order_line_id
        GROUP BY r.order_line_id HAVING sum(r.qty)>max(l.qty)
    ) THEN RAISE EXCEPTION 'L52: возвращено больше купленного'; END IF;
    IF EXISTS (
        SELECT 1 FROM crm.promotions
        WHERE updated_at >= (SELECT max(sim_date)+1 FROM meta.simulated_days)
    ) THEN RAISE EXCEPTION 'L64: время изменения промо находится после конца виртуального дня'; END IF;
END $$;
SELECT count(*) AS lived_days,min(sim_date) AS first_day,max(sim_date) AS last_day FROM meta.simulated_days;
