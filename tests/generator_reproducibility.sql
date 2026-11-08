-- Сравниваем всё содержимое 11 исходных таблиц, без служебного applied_at журнала.
CREATE TEMP VIEW source_digest AS
SELECT md5(string_agg(payload, E'\n' ORDER BY payload)) AS digest FROM (
 SELECT 'stores:'||row_to_json(t)::text payload FROM erp.stores t
 UNION ALL SELECT 'categories:'||row_to_json(t)::text FROM erp.categories t
 UNION ALL SELECT 'products:'||row_to_json(t)::text FROM erp.products t
 UNION ALL SELECT 'customers:'||row_to_json(t)::text FROM erp.customers t
 UNION ALL SELECT 'orders:'||row_to_json(t)::text FROM erp.orders t
 UNION ALL SELECT 'lines:'||row_to_json(t)::text FROM erp.order_lines t
 UNION ALL SELECT 'payments:'||row_to_json(t)::text FROM erp.payments t
 UNION ALL SELECT 'returns:'||row_to_json(t)::text FROM erp.returns t
 UNION ALL SELECT 'inventory:'||row_to_json(t)::text FROM erp.inventory t
 UNION ALL SELECT 'promotions:'||row_to_json(t)::text FROM crm.promotions t
 UNION ALL SELECT 'participation:'||row_to_json(t)::text FROM crm.promo_participation t
) source;
CREATE TEMP TABLE first_digest AS SELECT digest FROM source_digest;
SET timezone = 'America/New_York';
SELECT meta.seed_history(date '2026-09-01',14,40,12,8);
SET timezone = 'UTC';
DO $$ BEGIN
 IF (SELECT digest FROM first_digest)<>(SELECT digest FROM source_digest) THEN RAISE EXCEPTION 'Невоспроизводимый seed / зависимость от TZ'; END IF;
 RAISE NOTICE 'PASS: воспроизводимость seed и независимость от TZ';
END $$;
