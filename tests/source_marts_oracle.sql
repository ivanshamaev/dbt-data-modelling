-- Независимый PostgreSQL-эталон: ERP/CRM и сохранённое наблюдение клиентов до дня.
-- До первого наблюдения действует то же явно принятое допущение baseline.
-- Применимость ограничена tests/source_oracle_guard.sql; это не архив всех 60 дней.
WITH eligible AS (
    SELECT o.order_id, o.customer_id, o.order_no, o.order_ts::date AS sales_date,
           o.channel::text AS channel, l.line_amount
    FROM erp.orders o
    INNER JOIN erp.order_lines l ON l.order_id=o.order_id
    WHERE o.status IN ('paid','shipped','delivered','returned')
), dated_customers AS (
    SELECT c.customer_id,
           coalesce(b.segment,c.segment::text) AS before_segment,
           c.segment::text AS after_segment
    FROM erp.customers c
    LEFT JOIN meta.course_customer_baseline_20261031 b ON b.customer_id=c.customer_id
), baseline AS (
    SELECT min(baseline_day) AS baseline_day FROM meta.course_customer_baseline_20261031
), attributed AS (
    SELECT e.order_id,e.customer_id,e.line_amount,
           CASE WHEN e.sales_date<=b.baseline_day THEN c.before_segment ELSE c.after_segment END AS segment
    FROM eligible e
    INNER JOIN dated_customers c ON c.customer_id=e.customer_id
    CROSS JOIN baseline b
), promo_orders AS (
    SELECT DISTINCT order_no AS order_no FROM crm.promo_participation
)
SELECT 'source' AS contour,'sales_daily' AS mart,sales_date::text AS dim1,channel AS dim2,
       0::bigint AS customers,count(DISTINCT order_id) AS orders,sum(line_amount) AS amount
FROM eligible GROUP BY sales_date,channel
UNION ALL
SELECT 'source','customer_ltv',segment,'',count(DISTINCT customer_id),count(DISTINCT order_id),sum(line_amount)
FROM attributed GROUP BY segment
UNION ALL
SELECT 'source','promo_effect',CASE WHEN p.order_no IS NULL THEN 'organic' ELSE 'promo' END,'',
       0,count(DISTINCT e.order_id),sum(e.line_amount)
FROM eligible e
LEFT JOIN promo_orders p ON p.order_no=e.order_no
GROUP BY CASE WHEN p.order_no IS NULL THEN 'organic' ELSE 'promo' END
ORDER BY 1,2,3,4;
