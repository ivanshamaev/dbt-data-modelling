-- A→B→A внутри ОДНОГО effective_from; ещё одна смена сегмента того же дня; категория; частичные возвраты.
UPDATE fixture_erp.order_lines SET discount_pct=0,line_amount=20000,updated_at='2026-10-31 18:00+00' WHERE order_line_id=201;
UPDATE fixture_erp.orders SET total_amount=30000,status='returned',updated_at='2026-10-31 21:00+00' WHERE order_id=101;
UPDATE fixture_erp.payments SET amount=30000,status='refunded',refunded_at='2026-10-31 21:00+00',updated_at='2026-10-31 21:00+00' WHERE payment_id=301;
UPDATE fixture_erp.customers SET segment='premium',updated_at='2026-10-31 15:00+00' WHERE customer_id=1;
UPDATE fixture_erp.products SET category_id=4,updated_at='2026-10-31 17:00+00' WHERE product_id=2;
INSERT INTO fixture_erp.returns VALUES
 (401,201,'2026-10-31 19:00+00',1,'partial',10000),
 (402,201,'2026-10-31 20:00+00',1,'partial',10000);
