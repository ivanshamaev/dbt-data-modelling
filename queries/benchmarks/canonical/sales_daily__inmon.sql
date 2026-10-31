-- Каноническое зерно и меры; сравнивается с тем же вопросом в четырёх контурах.
SELECT sales_date, channel, orders_cnt, revenue_amt
FROM iceberg.inmon_marts.dm_sales_daily
ORDER BY sales_date, channel;
