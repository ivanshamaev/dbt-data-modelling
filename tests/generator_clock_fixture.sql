-- Только новая пустая база: минимальное окружение реальной simulate_day.
INSERT INTO meta.config VALUES ('t0','2026-09-01');
INSERT INTO meta.simulated_days(sim_date,stats) VALUES ('2026-09-01','{"fixture":true}');
INSERT INTO erp.stores(store_id,name,format,city,region,opened_at,updated_at)
SELECT i,'Тест '||i,CASE WHEN i=15 THEN 'online' ELSE 'mall' END,'Москва','Центр','2020-01-01','2026-09-01' FROM generate_series(1,15) s(i);
INSERT INTO erp.customers(customer_id,segment,city,region,registered_at,updated_at)
SELECT i,'standard','Москва','Центр','2020-01-01','2026-09-01' FROM generate_series(1,50000) s(i);
INSERT INTO erp.categories VALUES (1,NULL,'Тест');
INSERT INTO erp.products(product_id,sku,category_id,brand,list_price,launched_at,updated_at)
VALUES (1,'TEST',1,'Тест',10000,'2020-01-01','2026-09-01');
INSERT INTO meta.assortment(store_id,product_id,rn) SELECT i,1,1 FROM generate_series(1,15) s(i);
INSERT INTO meta.assortment_cnt SELECT i,1 FROM generate_series(1,15) s(i);
INSERT INTO crm.promotions VALUES ('PR-TEST','Тест','percent',10,'2026-08-01','2026-12-01','active','2026-09-01');
SELECT meta.simulate_day(date '2026-09-02');
SELECT count(*) AS orders,count(paid_at) AS paid,
 count(*) FILTER(WHERE paid_at<order_ts) AS negative_lags,
 count(*) FILTER(WHERE paid_at IS NOT NULL AND paid_at<>order_ts+interval '5 minute') AS wrong_paid_time
FROM erp.orders;
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM erp.orders WHERE paid_at IS NOT NULL) THEN RAISE EXCEPTION 'Не проверена ветка оплаты'; END IF;
 IF EXISTS(SELECT 1 FROM erp.orders WHERE paid_at IS NOT NULL AND paid_at<>order_ts+interval '5 minute') THEN RAISE EXCEPTION 'L66: неверное время оплаты нового заказа'; END IF;
END $$;
