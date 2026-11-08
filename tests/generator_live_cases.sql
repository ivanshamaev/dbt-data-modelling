DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM erp.orders WHERE store_id=16) THEN RAISE EXCEPTION 'Новый магазин не получает продажи'; END IF;
 IF EXISTS(SELECT 1 FROM erp.orders WHERE store_id=13 AND order_ts::date>date '2026-10-16') THEN RAISE EXCEPTION 'Продажа после закрытия магазина'; END IF;
 IF (SELECT count(DISTINCT qty) FROM erp.order_lines)<4 THEN RAISE EXCEPTION 'Случайные количества выродились'; END IF;
 IF (SELECT count(DISTINCT n) FROM (SELECT count(*) n FROM erp.order_lines GROUP BY order_id) baskets)<4 THEN RAISE EXCEPTION 'Случайные корзины выродились'; END IF;
 IF NOT EXISTS(SELECT 1 FROM erp.payments WHERE method='gift') THEN RAISE EXCEPTION 'Не проверены split-платежи'; END IF;
 IF NOT EXISTS(SELECT 1 FROM erp.payments WHERE status='partially_refunded') THEN RAISE EXCEPTION 'Не проверены частичные выплаты'; END IF;
 IF NOT EXISTS(SELECT 1 FROM crm.promo_participation WHERE order_no LIKE 'ORD-X%') THEN RAISE EXCEPTION 'Исчез учебный сценарий сирот CRM'; END IF;
 RAISE NOTICE 'PASS: открытие/закрытие, разнообразие корзин, split, частичные выплаты и намеренные сироты CRM';
END $$;
