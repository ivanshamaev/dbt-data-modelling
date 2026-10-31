-- Следующий день расширяет горизонт PIT; created-заказ не меняет gross-витрины.
INSERT INTO fixture_erp.orders (order_id, order_no, customer_id, store_id, channel, status, order_ts, total_amount, updated_at)
VALUES (106, 'TEST-106', 1, 1, 'shop', 'created', '2026-11-01 10:00+00', 1000, '2026-11-01 10:00+00');
INSERT INTO fixture_erp.order_lines VALUES (207, 106, 1, 1, 1000, 0, 1000, '2026-11-01 10:00+00');
-- Второе наблюдение PR-1 в тот же valid-день: ключ дневной версии остаётся один.
UPDATE fixture_crm.promotions SET ends_at='2026-12-15', updated_at='2026-10-31 22:00+00' WHERE promo_id='PR-1';
