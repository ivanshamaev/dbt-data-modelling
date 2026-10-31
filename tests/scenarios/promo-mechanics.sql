SELECT 'vault' AS contour, mechanics, order_type, orders_cnt, revenue_amt
FROM iceberg.PREFIXvault_marts.im_promo
UNION ALL
SELECT 'kimball', COALESCE(promo_mechanics,'none'),
       CASE WHEN promo_key IS NULL THEN 'organic' ELSE 'promo' END,
       COUNT(DISTINCT order_id), SUM(line_amount)
FROM PREFIXanalytics.obt_sales
GROUP BY 2,3
ORDER BY 1,2,3;
