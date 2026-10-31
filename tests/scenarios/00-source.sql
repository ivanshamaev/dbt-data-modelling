-- Изолированный маленький источник; рабочие erp/crm не изменяются.
CREATE SCHEMA IF NOT EXISTS fixture_erp;
CREATE SCHEMA IF NOT EXISTS fixture_crm;
CREATE TABLE IF NOT EXISTS fixture_erp.stores (LIKE erp.stores INCLUDING ALL);
CREATE TABLE IF NOT EXISTS fixture_erp.categories (LIKE erp.categories INCLUDING ALL);
CREATE TABLE IF NOT EXISTS fixture_erp.products (LIKE erp.products INCLUDING ALL);
CREATE TABLE IF NOT EXISTS fixture_erp.customers (LIKE erp.customers INCLUDING ALL);
CREATE TABLE IF NOT EXISTS fixture_erp.orders (LIKE erp.orders INCLUDING ALL);
CREATE TABLE IF NOT EXISTS fixture_erp.order_lines (LIKE erp.order_lines INCLUDING ALL);
CREATE TABLE IF NOT EXISTS fixture_erp.payments (LIKE erp.payments INCLUDING ALL);
CREATE TABLE IF NOT EXISTS fixture_erp.returns (LIKE erp.returns INCLUDING ALL);
CREATE TABLE IF NOT EXISTS fixture_erp.inventory (LIKE erp.inventory INCLUDING ALL);
CREATE TABLE IF NOT EXISTS fixture_crm.promotions (LIKE crm.promotions INCLUDING ALL);
CREATE TABLE IF NOT EXISTS fixture_crm.promo_participation (LIKE crm.promo_participation INCLUDING ALL);
TRUNCATE fixture_erp.stores, fixture_erp.categories, fixture_erp.products, fixture_erp.customers, fixture_erp.orders, fixture_erp.order_lines, fixture_erp.payments, fixture_erp.returns, fixture_erp.inventory, fixture_crm.promotions, fixture_crm.promo_participation;
GRANT USAGE ON SCHEMA fixture_erp, fixture_crm TO retailco_ro;
GRANT SELECT ON ALL TABLES IN SCHEMA fixture_erp, fixture_crm TO retailco_ro;
INSERT INTO fixture_erp.stores VALUES (1, 'Учебный магазин', 'street', 'Москва', 'Центр', '2025-01-01', NULL, '2026-10-01');
INSERT INTO fixture_erp.categories VALUES (1, NULL, 'Техника'), (2, 1, 'Устройства'), (3, 2, 'Телефоны'), (4, 2, 'Другие');
INSERT INTO fixture_erp.products VALUES
 (1, 'SKU-1', 3, 'Учебный', 10000, true, '2025-01-01', '2026-10-01'),
 (2, 'SKU-2', 3, 'Учебный', 10000, true, '2025-01-01', '2026-10-01');
INSERT INTO fixture_erp.customers VALUES
 (1, 'standard', 'Москва', 'Центр', '2025-01-01', '2026-10-01', NULL),
 (2, 'premium', 'Москва', 'Центр', '2025-01-01', '2026-10-01', NULL);
INSERT INTO fixture_erp.orders (order_id, order_no, customer_id, store_id, channel, status, order_ts, paid_at, total_amount, updated_at) VALUES
 (101, 'TEST-101', 1, 1, 'shop', 'paid', '2026-10-10 12:00+00', '2026-10-10 13:00+00', 30000, '2026-10-31 08:00+00'),
 (102, 'TEST-102', 1, 1, 'web', 'created', '2026-10-28 12:00+00', NULL, 40000, '2026-10-28 12:00+00'),
 (103, 'TEST-103', 2, 1, 'shop', 'paid', '2026-10-29 12:00+00', '2026-10-29 13:00+00', 5000, '2026-10-29 13:00+00'),
 (104, 'TEST-104', 2, 1, 'web', 'paid', '2026-10-31 12:00+00', '2026-10-31 13:00+00', 10000, '2026-10-31 13:00+00');
INSERT INTO fixture_erp.order_lines VALUES
 (201, 101, 1, 2, 10000, 0, 20000, '2026-10-31 08:00+00'),
 (202, 101, 2, 1, 10000, 0, 10000, '2026-10-10 12:00+00'),
 (203, 102, 1, 4, 10000, 0, 40000, '2026-10-28 12:00+00'),
 (204, 103, 2, 1, 10000, 50, 5000, '2026-10-29 12:00+00'),
 (205, 104, 2, 1, 10000, 0, 10000, '2026-10-31 12:00+00');
INSERT INTO fixture_erp.payments (payment_id, order_id, paid_ts, method, amount, status, updated_at) VALUES
 (301, 101, '2026-10-10 13:00+00', 'card', 30000, 'captured', '2026-10-31 08:00+00'),
 (303, 103, '2026-10-29 13:00+00', 'card', 5000, 'captured', '2026-10-29 13:00+00'),
 (304, 104, '2026-10-31 13:00+00', 'card', 10000, 'captured', '2026-10-31 13:00+00');
INSERT INTO fixture_erp.inventory VALUES ('2026-10-10', 1, 1, 5, 0), ('2026-10-31', 1, 1, 5, 0);
INSERT INTO fixture_crm.promotions VALUES
 ('PR-1', 'Первая', 'percent', 10, '2026-10-01', '2026-11-30', 'active', '2026-10-31 08:00+00'),
 ('PR-2', 'Вторая', 'fixed', 100, '2026-10-01', '2026-11-30', 'active', '2026-10-01');
INSERT INTO fixture_crm.promo_participation VALUES
 (1, 'PR-1', 'TEST-101', '2026-10-10', '2026-10-11'),
 (2, 'PR-2', 'TEST-101', '2026-10-10', '2026-10-12');
