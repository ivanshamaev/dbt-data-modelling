-- Каноническое зерно и меры; сравнивается с тем же вопросом в четырёх контурах.
SELECT order_type, orders_cnt, revenue_amt
FROM iceberg.anchor_marts.agg_anc_promo_effect
ORDER BY order_type;
