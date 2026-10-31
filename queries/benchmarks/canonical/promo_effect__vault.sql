-- Каноническое зерно и меры; сравнивается с тем же вопросом в четырёх контурах.
SELECT order_type, orders_cnt, revenue_amt
FROM iceberg.vault_marts.im_promo_effect
ORDER BY order_type;
