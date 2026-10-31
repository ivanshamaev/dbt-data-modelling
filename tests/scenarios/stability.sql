SELECT 'raw_crm__promotions' AS model,cast(promo_id AS varchar) AS entity_id,cast(updated_at AS varchar) AS valid_time,'' AS value,cast(_loaded_at AS varchar) AS insert_time,'' AS superseded_time FROM iceberg.PREFIXbronze.raw_crm__promotions
UNION ALL
SELECT 'raw_erp__customers' AS model,cast(customer_id AS varchar) AS entity_id,cast(updated_at AS varchar) AS valid_time,'' AS value,cast(_loaded_at AS varchar) AS insert_time,'' AS superseded_time FROM iceberg.PREFIXbronze.raw_erp__customers
UNION ALL
SELECT 'raw_erp__order_lines' AS model,cast(order_line_id AS varchar) AS entity_id,cast(updated_at AS varchar) AS valid_time,'' AS value,cast(_loaded_at AS varchar) AS insert_time,'' AS superseded_time FROM iceberg.PREFIXbronze.raw_erp__order_lines
UNION ALL
SELECT 'raw_erp__orders' AS model,cast(order_id AS varchar) AS entity_id,cast(updated_at AS varchar) AS valid_time,'' AS value,cast(_loaded_at AS varchar) AS insert_time,'' AS superseded_time FROM iceberg.PREFIXbronze.raw_erp__orders
UNION ALL
SELECT 'raw_erp__payments' AS model,cast(payment_id AS varchar) AS entity_id,cast(updated_at AS varchar) AS valid_time,'' AS value,cast(_loaded_at AS varchar) AS insert_time,'' AS superseded_time FROM iceberg.PREFIXbronze.raw_erp__payments
UNION ALL
SELECT 'raw_erp__products' AS model,cast(product_id AS varchar) AS entity_id,cast(updated_at AS varchar) AS valid_time,'' AS value,cast(_loaded_at AS varchar) AS insert_time,'' AS superseded_time FROM iceberg.PREFIXbronze.raw_erp__products
UNION ALL
SELECT 'raw_erp__stores' AS model,cast(store_id AS varchar) AS entity_id,cast(updated_at AS varchar) AS valid_time,'' AS value,cast(_loaded_at AS varchar) AS insert_time,'' AS superseded_time FROM iceberg.PREFIXbronze.raw_erp__stores
UNION ALL
SELECT 'brz_crm__promotions' AS model,cast(promo_id AS varchar) AS entity_id,cast(updated_at AS varchar) AS valid_time,'' AS value,cast(_loaded_at AS varchar) AS insert_time,'' AS superseded_time FROM iceberg.PREFIXmed_bronze.brz_crm__promotions
UNION ALL
SELECT 'brz_erp__customers' AS model,cast(customer_id AS varchar) AS entity_id,cast(updated_at AS varchar) AS valid_time,'' AS value,cast(_loaded_at AS varchar) AS insert_time,'' AS superseded_time FROM iceberg.PREFIXmed_bronze.brz_erp__customers
UNION ALL
SELECT 'brz_erp__order_lines' AS model,cast(order_line_id AS varchar) AS entity_id,cast(updated_at AS varchar) AS valid_time,'' AS value,cast(_loaded_at AS varchar) AS insert_time,'' AS superseded_time FROM iceberg.PREFIXmed_bronze.brz_erp__order_lines
UNION ALL
SELECT 'brz_erp__orders' AS model,cast(order_id AS varchar) AS entity_id,cast(updated_at AS varchar) AS valid_time,'' AS value,cast(_loaded_at AS varchar) AS insert_time,'' AS superseded_time FROM iceberg.PREFIXmed_bronze.brz_erp__orders
UNION ALL
SELECT 'brz_erp__payments' AS model,cast(payment_id AS varchar) AS entity_id,cast(updated_at AS varchar) AS valid_time,'' AS value,cast(_loaded_at AS varchar) AS insert_time,'' AS superseded_time FROM iceberg.PREFIXmed_bronze.brz_erp__payments
UNION ALL
SELECT 'brz_erp__products' AS model,cast(product_id AS varchar) AS entity_id,cast(updated_at AS varchar) AS valid_time,'' AS value,cast(_loaded_at AS varchar) AS insert_time,'' AS superseded_time FROM iceberg.PREFIXmed_bronze.brz_erp__products
UNION ALL
SELECT 'brz_erp__stores' AS model,cast(store_id AS varchar) AS entity_id,cast(updated_at AS varchar) AS valid_time,'' AS value,cast(_loaded_at AS varchar) AS insert_time,'' AS superseded_time FROM iceberg.PREFIXmed_bronze.brz_erp__stores
UNION ALL
SELECT 'ac_customer_city',cast(customer_id AS varchar),cast(valid_from AS varchar),cast(value AS varchar),cast(insert_time AS varchar),coalesce(cast(superseded_time AS varchar),'') FROM iceberg.PREFIXanchor_core.ac_customer_city
UNION ALL
SELECT 'ac_customer_segment',cast(customer_id AS varchar),cast(valid_from AS varchar),cast(value AS varchar),cast(insert_time AS varchar),coalesce(cast(superseded_time AS varchar),'') FROM iceberg.PREFIXanchor_core.ac_customer_segment
UNION ALL
SELECT 'ac_order_amount',cast(order_id AS varchar),cast(valid_from AS varchar),cast(value AS varchar),cast(insert_time AS varchar),coalesce(cast(superseded_time AS varchar),'') FROM iceberg.PREFIXanchor_core.ac_order_amount
UNION ALL
SELECT 'ac_order_channel',cast(order_id AS varchar),cast(valid_from AS varchar),cast(value AS varchar),cast(insert_time AS varchar),coalesce(cast(superseded_time AS varchar),'') FROM iceberg.PREFIXanchor_core.ac_order_channel
UNION ALL
SELECT 'ac_order_delivered_at',cast(order_id AS varchar),cast(valid_from AS varchar),cast(value AS varchar),cast(insert_time AS varchar),coalesce(cast(superseded_time AS varchar),'') FROM iceberg.PREFIXanchor_core.ac_order_delivered_at
UNION ALL
SELECT 'ac_order_line_amount',cast(order_line_id AS varchar),cast(valid_from AS varchar),cast(value AS varchar),cast(insert_time AS varchar),coalesce(cast(superseded_time AS varchar),'') FROM iceberg.PREFIXanchor_core.ac_order_line_amount
UNION ALL
SELECT 'ac_order_order_ts',cast(order_id AS varchar),cast(valid_from AS varchar),cast(value AS varchar),cast(insert_time AS varchar),coalesce(cast(superseded_time AS varchar),'') FROM iceberg.PREFIXanchor_core.ac_order_order_ts
UNION ALL
SELECT 'ac_order_paid_at',cast(order_id AS varchar),cast(valid_from AS varchar),cast(value AS varchar),cast(insert_time AS varchar),coalesce(cast(superseded_time AS varchar),'') FROM iceberg.PREFIXanchor_core.ac_order_paid_at
UNION ALL
SELECT 'ac_order_shipped_at',cast(order_id AS varchar),cast(valid_from AS varchar),cast(value AS varchar),cast(insert_time AS varchar),coalesce(cast(superseded_time AS varchar),'') FROM iceberg.PREFIXanchor_core.ac_order_shipped_at
UNION ALL
SELECT 'ac_order_status',cast(order_id AS varchar),cast(valid_from AS varchar),cast(value AS varchar),cast(insert_time AS varchar),coalesce(cast(superseded_time AS varchar),'') FROM iceberg.PREFIXanchor_core.ac_order_status
UNION ALL
SELECT 'ac_promo_mechanics',cast(promo_id AS varchar),cast(valid_from AS varchar),cast(value AS varchar),cast(insert_time AS varchar),coalesce(cast(superseded_time AS varchar),'') FROM iceberg.PREFIXanchor_core.ac_promo_mechanics
ORDER BY 1,2,3,4,5,6;
