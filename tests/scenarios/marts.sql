SET CATALOG default_catalog;
SELECT 'inmon' AS contour,'sales_daily' AS mart,cast(sales_date AS varchar) AS dim1,channel AS dim2,0 AS customers,orders_cnt AS orders,revenue_amt AS amount FROM iceberg.PREFIXinmon_marts.dm_sales_daily
UNION ALL
SELECT 'inmon','customer_ltv',segment,'',customers_cnt,orders_cnt,ltv_amt FROM iceberg.PREFIXinmon_marts.dm_customer_ltv
UNION ALL
SELECT 'inmon','promo_effect',order_type,'',0,orders_cnt,revenue_amt FROM iceberg.PREFIXinmon_marts.dm_promo_effect
UNION ALL
SELECT 'kimball' AS contour,'sales_daily' AS mart,cast(sales_date AS varchar) AS dim1,channel AS dim2,0 AS customers,orders_cnt AS orders,revenue_amt AS amount FROM PREFIXanalytics.km_sales_daily
UNION ALL
SELECT 'kimball','customer_ltv',segment,'',customers_cnt,orders_cnt,ltv_amt FROM PREFIXanalytics.km_customer_ltv
UNION ALL
SELECT 'kimball','promo_effect',order_type,'',0,orders_cnt,revenue_amt FROM PREFIXanalytics.km_promo_effect
UNION ALL
SELECT 'vault' AS contour,'sales_daily' AS mart,cast(sales_date AS varchar) AS dim1,channel AS dim2,0 AS customers,orders_cnt AS orders,revenue_amt AS amount FROM iceberg.PREFIXvault_marts.im_sales_daily
UNION ALL
SELECT 'vault','customer_ltv',segment,'',customers_cnt,orders_cnt,ltv_amt FROM iceberg.PREFIXvault_marts.im_customer_ltv
UNION ALL
SELECT 'vault','promo_effect',order_type,'',0,orders_cnt,revenue_amt FROM iceberg.PREFIXvault_marts.im_promo_effect
UNION ALL
SELECT 'anchor' AS contour,'sales_daily' AS mart,cast(sales_date AS varchar) AS dim1,channel AS dim2,0 AS customers,orders_cnt AS orders,revenue_amt AS amount FROM iceberg.PREFIXanchor_marts.agg_anc_sales_daily
UNION ALL
SELECT 'anchor','customer_ltv',segment,'',customers_cnt,orders_cnt,ltv_amt FROM iceberg.PREFIXanchor_marts.agg_anc_customer_ltv
UNION ALL
SELECT 'anchor','promo_effect',order_type,'',0,orders_cnt,revenue_amt FROM iceberg.PREFIXanchor_marts.agg_anc_promo_effect
UNION ALL
SELECT 'medallion' AS contour,'sales_daily' AS mart,cast(sales_date AS varchar) AS dim1,channel AS dim2,0 AS customers,orders_cnt AS orders,revenue_amt AS amount FROM iceberg.PREFIXmed_gold.gld_sales_daily
UNION ALL
SELECT 'medallion','customer_ltv',segment,'',customers_cnt,orders_cnt,ltv_amt FROM iceberg.PREFIXmed_gold.gld_customer_ltv
UNION ALL
SELECT 'medallion','promo_effect',order_type,'',0,orders_cnt,revenue_amt FROM iceberg.PREFIXmed_gold.gld_promo_effect
ORDER BY 1,2,3,4;
