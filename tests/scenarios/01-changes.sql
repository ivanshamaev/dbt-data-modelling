-- Старая сумма, поздняя оплата/CRM, смена сегмента и новый заказ.
UPDATE fixture_erp.order_lines SET discount_pct=10, line_amount=18000, updated_at='2026-10-31 09:00+00' WHERE order_line_id=201;
UPDATE fixture_erp.orders SET total_amount=28000, updated_at='2026-10-31 09:00+00' WHERE order_id=101;
UPDATE fixture_erp.payments SET amount=28000, updated_at='2026-10-31 09:00+00' WHERE payment_id=301;
UPDATE fixture_erp.orders SET status='paid', paid_at='2026-10-31 10:00+00', updated_at='2026-10-31 10:00+00' WHERE order_id=102;
UPDATE fixture_erp.customers SET segment='vip', updated_at='2026-10-31 09:00+00' WHERE customer_id=1;
INSERT INTO fixture_erp.orders (order_id,order_no,customer_id,store_id,channel,status,order_ts,paid_at,total_amount,updated_at)
VALUES (105,'TEST-105',1,1,'shop','paid','2026-10-31 12:00+00','2026-10-31 13:00+00',2000,'2026-10-31 13:00+00');
INSERT INTO fixture_erp.order_lines VALUES (206,105,2,1,2000,0,2000,'2026-10-31 12:00+00');
INSERT INTO fixture_erp.payments (payment_id,order_id,paid_ts,method,amount,status,updated_at) VALUES
 (302,102,'2026-10-31 10:00+00','card',40000,'captured','2026-10-31 10:00+00'),
 (305,105,'2026-10-31 13:00+00','card',2000,'captured','2026-10-31 13:00+00');
INSERT INTO fixture_crm.promo_participation VALUES (3,'PR-1','TEST-102','2026-10-28','2026-10-31');
