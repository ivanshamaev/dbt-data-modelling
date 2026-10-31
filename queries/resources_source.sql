-- Реальные строки и размер PostgreSQL с индексами/TOAST; не размер сжатого экспорта.
SELECT 'erp.customers' AS relation_name,count(*) AS rows_count,pg_total_relation_size('erp.customers') AS total_bytes FROM erp.customers
UNION ALL SELECT 'erp.categories',count(*),pg_total_relation_size('erp.categories') FROM erp.categories
UNION ALL SELECT 'erp.products',count(*),pg_total_relation_size('erp.products') FROM erp.products
UNION ALL SELECT 'erp.stores',count(*),pg_total_relation_size('erp.stores') FROM erp.stores
UNION ALL SELECT 'erp.orders',count(*),pg_total_relation_size('erp.orders') FROM erp.orders
UNION ALL SELECT 'erp.order_lines',count(*),pg_total_relation_size('erp.order_lines') FROM erp.order_lines
UNION ALL SELECT 'erp.payments',count(*),pg_total_relation_size('erp.payments') FROM erp.payments
UNION ALL SELECT 'erp.returns',count(*),pg_total_relation_size('erp.returns') FROM erp.returns
UNION ALL SELECT 'erp.inventory',count(*),pg_total_relation_size('erp.inventory') FROM erp.inventory
UNION ALL SELECT 'crm.promotions',count(*),pg_total_relation_size('crm.promotions') FROM crm.promotions
UNION ALL SELECT 'crm.promo_participation',count(*),pg_total_relation_size('crm.promo_participation') FROM crm.promo_participation
ORDER BY 1;
