-- Каноническое зерно и меры; сравнивается с тем же вопросом в четырёх контурах.
SELECT segment, customers_cnt, orders_cnt, ltv_amt
FROM iceberg.inmon_marts.dm_customer_ltv
ORDER BY segment;
