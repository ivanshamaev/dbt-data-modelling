-- ============================================================================
-- RetailCo: схемы источников ERP (9 таблиц) и CRM (2 таблицы) + meta генератора
-- Денежные суммы — BIGINT в рублях, время — UTC (timestamptz).
-- v4.0: частичные выплаты, точный эффективный процент скидки,
--       причинная CRM-доставка и переносимый складской баланс.
-- Пересоздание с нуля: make sources (drop + create + функции генератора).
-- ============================================================================

DROP SCHEMA IF EXISTS crm    CASCADE;
DROP SCHEMA IF EXISTS erp    CASCADE;
DROP SCHEMA IF EXISTS meta   CASCADE;

CREATE SCHEMA erp;
CREATE SCHEMA crm;
CREATE SCHEMA meta;

-- ---------------------------------------------------------------------------
-- ERP
-- ---------------------------------------------------------------------------

CREATE TABLE erp.stores (
    store_id    integer PRIMARY KEY,
    name        text    NOT NULL,
    format      text    NOT NULL CHECK (format IN ('mall', 'street', 'online')),
    city        text    NOT NULL,
    region      text    NOT NULL,
    opened_at   date    NOT NULL,
    closed_at   date,                          -- закрытие = soft-операция (§2.1)
    updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE erp.categories (
    category_id        integer PRIMARY KEY,
    parent_category_id integer REFERENCES erp.categories(category_id),
    name               text NOT NULL,
    -- 3 уровня: «Напитки → Кофе → Зерно»; уровень выводится обходом, не хранится
    CHECK (category_id <> parent_category_id)
);

CREATE TABLE erp.products (
    product_id   integer PRIMARY KEY,
    sku          text NOT NULL UNIQUE,
    category_id  integer NOT NULL REFERENCES erp.categories(category_id),
    brand        text NOT NULL,
    list_price   bigint NOT NULL CHECK (list_price > 0),   -- рубли
    is_active    boolean NOT NULL DEFAULT true,
    launched_at  date NOT NULL,
    updated_at   timestamptz NOT NULL DEFAULT now()          -- бамп при переносе категории
);

CREATE TABLE erp.customers (
    customer_id   integer PRIMARY KEY,
    segment       text NOT NULL CHECK (segment IN ('standard', 'premium', 'vip')),
    city          text NOT NULL,
    region        text NOT NULL,
    registered_at timestamptz NOT NULL,
    updated_at    timestamptz NOT NULL,
    deleted_at    timestamptz                                -- soft delete, редко
);

CREATE TABLE erp.orders (
    order_id      bigint PRIMARY KEY,
    order_no      text NOT NULL UNIQUE,          -- бизнес-номер: degenerate dimension + ключ стыковки с CRM
    customer_id   integer NOT NULL REFERENCES erp.customers(customer_id),
    store_id      integer NOT NULL REFERENCES erp.stores(store_id),
    channel       text NOT NULL CHECK (channel IN ('shop', 'web', 'app')),
    status        text NOT NULL CHECK (status IN ('created', 'paid', 'shipped', 'delivered', 'cancelled', 'returned')),
    order_ts      timestamptz NOT NULL,
    paid_at       timestamptz,
    shipped_at    timestamptz,
    delivered_at  timestamptz,
    cancelled_at  timestamptz,
    total_amount  bigint NOT NULL DEFAULT 0,     -- = SUM(order_lines.line_amount) (инвариант генератора)
    updated_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE erp.order_lines (
    order_line_id bigint PRIMARY KEY,
    order_id      bigint NOT NULL REFERENCES erp.orders(order_id),
    product_id    integer NOT NULL REFERENCES erp.products(product_id),
    qty           integer NOT NULL CHECK (qty > 0),
    unit_price    bigint NOT NULL CHECK (unit_price >= 0),
    discount_pct  numeric(12,8) NOT NULL DEFAULT 0 CHECK (discount_pct >= 0 AND discount_pct <= 100),
    line_amount   bigint NOT NULL,               -- = round(qty*unit_price*(1-discount_pct/100))
    updated_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE erp.payments (
    payment_id  bigint PRIMARY KEY,
    order_id    bigint NOT NULL REFERENCES erp.orders(order_id),
    paid_ts     timestamptz NOT NULL,
    method      text NOT NULL CHECK (method IN ('card', 'cash', 'online', 'gift')),
    amount      bigint NOT NULL CHECK (amount >= 0),
    status      text NOT NULL CHECK (status IN ('authorized', 'captured', 'partially_refunded', 'refunded')),
    refunded_at timestamptz,
    updated_at  timestamptz NOT NULL DEFAULT now(),
    -- Накопленный возврат денег; amount сохраняет исходное списание.
    refunded_amount bigint NOT NULL DEFAULT 0 CHECK (refunded_amount >= 0 AND refunded_amount <= amount)
);

CREATE TABLE erp.returns (
    return_id     bigint PRIMARY KEY,
    order_line_id bigint NOT NULL REFERENCES erp.order_lines(order_line_id),
    return_ts     timestamptz NOT NULL,
    qty           integer NOT NULL CHECK (qty > 0),            -- может быть < qty строки (частичный возврат)
    reason        text NOT NULL,
    refund_amount bigint NOT NULL CHECK (refund_amount >= 0)
);

-- Миллионы снимков: объём зависит от дат запуска SKU, работы магазинов и ассортимента.
CREATE TABLE erp.inventory (
    snap_date     date NOT NULL,
    store_id      integer NOT NULL REFERENCES erp.stores(store_id),
    product_id    integer NOT NULL REFERENCES erp.products(product_id),
    qty_on_hand   integer NOT NULL CHECK (qty_on_hand >= 0),
    qty_reserved  integer NOT NULL CHECK (qty_reserved >= 0 AND qty_reserved <= qty_on_hand) DEFAULT 0,
    PRIMARY KEY (snap_date, store_id, product_id)
);

-- ---------------------------------------------------------------------------
-- CRM промо-направления: «честный второй источник» — свои ключи, свой ритм
-- ---------------------------------------------------------------------------

CREATE TABLE crm.promotions (
    promo_id        text PRIMARY KEY,            -- свой формат ключей: 'PR-2024-017'
    name            text NOT NULL,
    mechanics       text NOT NULL CHECK (mechanics IN ('percent', 'fixed', 'bundle')),
    discount_value  numeric(10,2) NOT NULL,
    starts_at       date NOT NULL,
    ends_at         date NOT NULL CHECK (ends_at >= starts_at),
    status          text NOT NULL CHECK (status IN ('planned', 'active', 'closed')),
    updated_at      timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE crm.promo_participation (
    id          bigint PRIMARY KEY,
    promo_id    text NOT NULL REFERENCES crm.promotions(promo_id),
    order_no    text NOT NULL,                   -- «CRM знает только номер»: без FK к erp.orders
    attached_at timestamptz NOT NULL,
    sync_ts     timestamptz NOT NULL CHECK (sync_ts >= attached_at)
);

-- ---------------------------------------------------------------------------
-- meta: журнал симуляции, ассортиментная матрица, конфиг генератора, секвенции
-- ---------------------------------------------------------------------------

CREATE TABLE meta.simulated_days (
    sim_date   date PRIMARY KEY,
    applied_at timestamptz NOT NULL DEFAULT now(),
    stats      jsonb
);

CREATE TABLE meta.config (
    k text PRIMARY KEY,
    v text NOT NULL
);

-- Матрица ассортимента: какие SKU продаются/хранятся в каком магазине (~85% покрытия)
CREATE TABLE meta.assortment (
    store_id   integer NOT NULL,
    product_id integer NOT NULL,
    rn         integer,                            -- 1..cnt внутри магазина: O(1) случайный выбор
    PRIMARY KEY (store_id, product_id)
);
CREATE INDEX assortment_store_rn_idx ON meta.assortment(store_id, rn);

CREATE TABLE meta.assortment_cnt (
    store_id integer PRIMARY KEY,
    cnt      integer NOT NULL
);

-- Применённые условия фиксируются при покупке, независимо от задержки CRM.
CREATE TABLE meta.order_promotions (
    order_id bigint PRIMARY KEY REFERENCES erp.orders(order_id),
    promo_id text NOT NULL REFERENCES crm.promotions(promo_id),
    mechanics text NOT NULL,
    discount_value numeric(10,2) NOT NULL,
    attached_at timestamptz NOT NULL,
    sync_due timestamptz NOT NULL CHECK (sync_due >= attached_at)
);

CREATE TABLE meta.order_adjustments (
    order_id bigint PRIMARY KEY REFERENCES erp.orders(order_id),
    discount_pct integer NOT NULL DEFAULT 0 CHECK (discount_pct BETWEEN 0 AND 30),
    updated_at timestamptz NOT NULL
);

-- Внутренний журнал объясняет изменение остатков, не является источником DWH.
CREATE TABLE meta.inventory_movements (
    snap_date date NOT NULL,
    store_id integer NOT NULL REFERENCES erp.stores(store_id),
    product_id integer NOT NULL REFERENCES erp.products(product_id),
    opening_qty integer NOT NULL CHECK (opening_qty >= 0),
    received_qty integer NOT NULL CHECK (received_qty >= 0),
    shipped_qty integer NOT NULL CHECK (shipped_qty >= 0),
    returned_qty integer NOT NULL CHECK (returned_qty >= 0),
    closing_qty integer NOT NULL CHECK (closing_qty >= 0),
    reserved_qty integer NOT NULL CHECK (reserved_qty BETWEEN 0 AND closing_qty),
    PRIMARY KEY (snap_date, store_id, product_id),
    CHECK (closing_qty = opening_qty + received_qty - shipped_qty + returned_qty)
);

CREATE TABLE meta.inventory_balance (
    store_id integer NOT NULL,
    product_id integer NOT NULL,
    qty_on_hand integer NOT NULL,
    qty_reserved integer NOT NULL DEFAULT 0,
    PRIMARY KEY (store_id, product_id)
);

CREATE SEQUENCE meta.seq_order         START 1;   -- order_id
CREATE SEQUENCE meta.seq_order_no      START 1;   -- числовая часть order_no
CREATE SEQUENCE meta.seq_line          START 1;
CREATE SEQUENCE meta.seq_payment       START 1;
CREATE SEQUENCE meta.seq_return        START 1;
CREATE SEQUENCE meta.seq_participation START 1;

-- Индексы под watermark-инжест (bronze читает по updated_at / дате события)
CREATE INDEX orders_order_ts_idx   ON erp.orders (order_ts);
CREATE INDEX orders_status_idx     ON erp.orders (status);
CREATE INDEX orders_paid_idx       ON erp.orders (paid_at);
CREATE INDEX orders_shipped_idx    ON erp.orders (shipped_at);
CREATE INDEX orders_updated_idx    ON erp.orders (updated_at);
CREATE INDEX lines_order_idx       ON erp.order_lines (order_id);
CREATE INDEX lines_updated_idx     ON erp.order_lines (updated_at);
CREATE INDEX payments_updated_idx  ON erp.payments (updated_at);
CREATE INDEX customers_updated_idx ON erp.customers (updated_at);
CREATE INDEX products_updated_idx  ON erp.products (updated_at);
CREATE INDEX returns_ts_idx        ON erp.returns (return_ts);
CREATE INDEX participation_sync_idx ON crm.promo_participation (sync_ts);
CREATE INDEX participation_no_idx  ON crm.promo_participation (order_no);
CREATE INDEX promotions_updated_idx ON crm.promotions (updated_at);

-- Права только-чтения для JDBC-каталога StarRocks
GRANT USAGE ON SCHEMA erp, crm TO retailco_ro;
GRANT SELECT ON ALL TABLES IN SCHEMA erp, crm TO retailco_ro;
ALTER DEFAULT PRIVILEGES IN SCHEMA erp, crm GRANT SELECT ON TABLES TO retailco_ro;
