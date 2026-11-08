-- Контролируемые примеры: запускаются только в отдельной пустой тестовой базе.
SET timezone = 'UTC';
INSERT INTO erp.stores VALUES (1,'Тест','mall','Москва','Центр','2020-01-01',NULL,'2026-01-01');
INSERT INTO erp.categories VALUES (1,NULL,'Тест');
INSERT INTO erp.products(product_id,sku,category_id,brand,list_price,launched_at,updated_at)
VALUES (1,'TEST',1,'Тест',100,'2020-01-01','2026-01-01');
INSERT INTO erp.customers VALUES (1,'standard','Москва','Центр','2020-01-01','2026-01-01',NULL);
INSERT INTO meta.assortment VALUES (1,1,1);
INSERT INTO crm.promotions VALUES
('FIX','Тест','fixed',101,'2026-01-01','2026-12-31','active','2026-01-01'),
('PCT','Тест','percent',10,'2026-01-01','2026-12-31','active','2026-01-01'),
('BND','Тест','bundle',1,'2026-01-01','2026-12-31','active','2026-01-01');
INSERT INTO erp.orders(order_id,order_no,customer_id,store_id,channel,status,order_ts,updated_at)
SELECT i,'TEST-'||i,1,1,'shop','created','2026-01-01 08:00+00','2026-01-01 08:00+00' FROM generate_series(1,4) g(i);
INSERT INTO erp.order_lines VALUES
(1,1,1,1,100,0,100,'2026-01-01'),(2,1,1,1,200,0,200,'2026-01-01'),
(3,2,1,1,101,0,101,'2026-01-01'),(4,3,1,7,100,0,700,'2026-01-01'),
(5,4,1,2,100,49.5,101,'2026-01-01');
INSERT INTO meta.order_promotions VALUES
(1,'FIX','fixed',101,'2026-01-01 08:00+00','2026-01-02'),
(2,'PCT','percent',10,'2026-01-01 08:00+00','2026-01-02'),
(3,'BND','bundle',1,'2026-01-01 08:00+00','2026-01-02');
SELECT meta.reprice_orders(1,3);
DO $$ BEGIN
 IF (SELECT array_agg(line_amount ORDER BY order_line_id) FROM erp.order_lines WHERE order_id<=3) <> ARRAY[66,133,91,500]::bigint[]
 THEN RAISE EXCEPTION 'Неверное распределение fixed/percent/bundle'; END IF;
END $$;
-- Известный созданный заказ становится оплаченным: платёж обязателен.
UPDATE erp.orders SET status='paid',paid_at='2026-01-01 09:00+00',total_amount=101,updated_at='2026-01-01 09:00+00' WHERE order_id=4;
SELECT meta.sync_payments();
DO $$ BEGIN
 IF (SELECT sum(amount) FROM erp.payments WHERE order_id=4)<>101
 THEN RAISE EXCEPTION 'Нет оплаты междневного перехода'; END IF;
END $$;
UPDATE erp.orders SET status='delivered',shipped_at='2026-01-01 10:00+00',delivered_at='2026-01-01 11:00+00',updated_at='2026-01-01 11:00+00' WHERE order_id=4;
-- 101 рубль за две единицы: первый возврат 51, второй 50, а не два раза 51.
INSERT INTO erp.returns VALUES (1,5,'2026-01-02 10:00+00',1,'defect',round(101::numeric/2));
SELECT meta.mark_full_returns();
SELECT meta.sync_payments();
DO $$ BEGIN
 IF (SELECT status FROM erp.orders WHERE order_id=4)<>'delivered'
 OR (SELECT sum(refunded_amount) FROM erp.payments WHERE order_id=4)<>51
 OR (SELECT sum(amount-refunded_amount) FROM erp.payments WHERE order_id=4)<>50
 OR EXISTS(SELECT 1 FROM erp.payments WHERE refunded_at<'2026-01-02 10:00+00')
 THEN RAISE EXCEPTION 'Неверный частичный возврат или время выплаты'; END IF;
END $$;
INSERT INTO erp.returns VALUES (2,5,'2026-01-03 10:00+00',1,'defect',round(101::numeric*2/2)-51);
SELECT meta.mark_full_returns();
SELECT meta.sync_payments();
DO $$ BEGIN
 IF (SELECT status FROM erp.orders WHERE order_id=4)<>'returned'
 OR (SELECT sum(refunded_amount) FROM erp.payments WHERE order_id=4)<>101
 OR (SELECT sum(amount-refunded_amount) FROM erp.payments WHERE order_id=4)<>0
 THEN RAISE EXCEPTION 'Неверный полный возврат со split-оплатой'; END IF;
END $$;
-- Ретро-скидка возвращает переплату, исходное списание остаётся 91.
UPDATE erp.orders SET status='paid',paid_at='2026-01-01 09:00+00',updated_at='2026-01-01 09:00+00' WHERE order_id=2;
SELECT meta.sync_payments();
INSERT INTO meta.order_adjustments VALUES (2,5,'2026-01-02 20:00+00');
SELECT meta.reprice_orders(2,2,'2026-01-02 20:00+00');
SELECT meta.sync_payments();
DO $$ BEGIN
 IF (SELECT sum(amount) FROM erp.payments WHERE order_id=2)<>91
 OR (SELECT sum(refunded_amount) FROM erp.payments WHERE order_id=2)<>5
 THEN RAISE EXCEPTION 'Ретро-скидка переписала списание или не вернула переплату'; END IF;
END $$;
-- Остаток: 10 -> отгрузка 2 -> возврат 1 -> возврат 1. Резерв заказа 2 = 1.
INSERT INTO meta.inventory_balance VALUES (1,1,10,0);
SELECT meta.snapshot_inventory('2026-01-01');
SELECT meta.snapshot_inventory('2026-01-02');
SELECT meta.snapshot_inventory('2026-01-03');
DO $$ BEGIN
 IF (SELECT array_agg(qty_on_hand ORDER BY snap_date) FROM erp.inventory)<>ARRAY[8,9,10]
 OR EXISTS(SELECT 1 FROM erp.inventory WHERE qty_reserved<>1)
 THEN RAISE EXCEPTION 'Остаток не следует отгрузке/возвратам или неверный резерв'; END IF;
 RAISE NOTICE 'PASS: скидки, междневная оплата, частичный/полный возврат, округление, split, ретро-скидка, движения остатков';
END $$;
