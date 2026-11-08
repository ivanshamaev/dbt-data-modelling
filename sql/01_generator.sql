-- RetailCo 4.0: согласованные бизнес-связи, суммы в рублях, время UTC.
-- seed_history создаёт начальное состояние; simulate_day применяет только следующий день.
-- Изменение договоров источника требует нового изолированного источника и новой Bronze.

CREATE OR REPLACE FUNCTION meta.day_seed(p_date date)
RETURNS double precision LANGUAGE sql AS $$
  SELECT ((hashtext(p_date::text))::numeric / 2147483648.0 + 1.0) / 2.0
$$;

-- Перенумерация ассортимента магазина (rn = 1..cnt; O(1)-выбор по (store_id, rn))
CREATE OR REPLACE FUNCTION meta.renumber_assortment(p_store integer)
RETURNS void LANGUAGE plpgsql SET TimeZone = 'UTC' AS $$
BEGIN
  UPDATE meta.assortment a SET rn = n.rn
  FROM (SELECT ctid, row_number() OVER (ORDER BY product_id) rn
        FROM meta.assortment WHERE store_id = p_store) n
  WHERE a.ctid = n.ctid;

  INSERT INTO meta.assortment_cnt (store_id, cnt)
  SELECT p_store, count(*) FROM meta.assortment WHERE store_id = p_store
  ON CONFLICT (store_id) DO UPDATE SET cnt = EXCLUDED.cnt;
END $$;


-- Единые операции seed и ежедневной симуляции: один договор бизнес-связей.
CREATE OR REPLACE FUNCTION meta.reprice_orders(p_first bigint, p_last bigint, p_at timestamptz DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SET TimeZone = 'UTC' AS $$
BEGIN
  WITH lines AS MATERIALIZED (
    SELECT l.order_line_id, l.order_id, l.qty::bigint * l.unit_price AS gross,
           (l.qty / 3)::bigint * l.unit_price AS bundle_discount
    FROM erp.order_lines l WHERE l.order_id BETWEEN p_first AND p_last
  ), totals AS (
    SELECT order_id, sum(gross) AS gross, sum(bundle_discount) AS bundle_discount
    FROM lines GROUP BY order_id
  ), targets AS (
    SELECT t.order_id, t.gross,
      LEAST(t.gross, CASE p.mechanics
        WHEN 'percent' THEN round(t.gross * p.discount_value / 100.0)
        WHEN 'fixed' THEN p.discount_value
        WHEN 'bundle' THEN t.bundle_discount ELSE 0 END
        + round(t.gross * COALESCE(a.discount_pct, 0) / 100.0))::bigint AS discount
    FROM totals t LEFT JOIN meta.order_promotions p USING (order_id)
    LEFT JOIN meta.order_adjustments a USING (order_id)
  ), shares AS (
    SELECT l.order_line_id, l.order_id, l.gross, t.discount,
      floor(l.gross * t.discount::numeric / NULLIF(t.gross, 0))::bigint AS base,
      mod(l.gross * t.discount::numeric, NULLIF(t.gross, 0)) AS remainder
    FROM lines l JOIN targets t USING (order_id)
  ), allocated AS (
    SELECT order_line_id, gross,
      COALESCE(base, 0) + CASE WHEN row_number() OVER (PARTITION BY order_id ORDER BY remainder DESC, order_line_id)
        <= discount - sum(COALESCE(base, 0)) OVER (PARTITION BY order_id) THEN 1 ELSE 0 END AS discount
    FROM shares
  )
  UPDATE erp.order_lines l SET line_amount = a.gross - a.discount,
    discount_pct = CASE WHEN a.gross = 0 THEN 0 ELSE round(100.0 * a.discount / a.gross, 8) END,
    updated_at = greatest(l.updated_at, COALESCE(p_at, l.updated_at))
  FROM allocated a WHERE a.order_line_id = l.order_line_id
    AND l.line_amount IS DISTINCT FROM a.gross - a.discount;

  UPDATE erp.orders o SET total_amount = t.amount,
    updated_at = greatest(o.updated_at, COALESCE(p_at, o.updated_at))
  FROM (SELECT order_id, sum(line_amount)::bigint AS amount FROM erp.order_lines
        WHERE order_id BETWEEN p_first AND p_last GROUP BY order_id) t
  WHERE o.order_id = t.order_id AND o.total_amount IS DISTINCT FROM t.amount;
END $$;

CREATE OR REPLACE FUNCTION meta.create_orders(p_day date, p_count integer, p_cutoff timestamptz, p_seen_at timestamptz DEFAULT NULL)
RETURNS integer LANGUAGE plpgsql SET TimeZone = 'UTC' AS $$
DECLARE
  customers integer[]; stores integer[]; first_id bigint; last_id bigint; n integer;
BEGIN
  IF p_count <= 0 THEN RETURN 0; END IF;
  SELECT array_agg(customer_id ORDER BY customer_id) INTO customers FROM erp.customers
  WHERE registered_at <= p_day::timestamptz AND (deleted_at IS NULL OR deleted_at >= (p_day+1)::timestamptz);
  SELECT array_agg(s.store_id ORDER BY s.store_id) INTO stores FROM erp.stores s
  WHERE s.format <> 'online' AND s.opened_at <= p_day AND (s.closed_at IS NULL OR s.closed_at >= p_day)
    AND EXISTS (SELECT 1 FROM meta.assortment a JOIN erp.products p USING (product_id)
                WHERE a.store_id = s.store_id AND p.is_active AND p.launched_at <= p_day);
  IF customers IS NULL OR stores IS NULL THEN RAISE EXCEPTION 'Нет доступных клиентов/магазинов на %', p_day; END IF;
  SELECT COALESCE(max(order_id), 0) + 1 INTO first_id FROM erp.orders;

  WITH draws AS MATERIALIZED (
    SELECT i, random() AS ch, random() AS hr, random() AS cu, random() AS st,
      random() AS pay, random() AS cancel, random() AS cancel_paid
    FROM generate_series(1, p_count) g(i)
  ), stamped AS MATERIALIZED (
    SELECT d.i, d.cu, d.st, d.pay, d.cancel, d.cancel_paid, CASE WHEN ch < 0.55 THEN 'shop' WHEN ch < 0.80 THEN 'web' ELSE 'app' END AS channel,
      p_day::timestamp + make_interval(hours => CASE WHEN hr < 0.15 THEN 8 + floor(random()*4)::int
        WHEN hr < 0.45 THEN 12 + floor(random()*6)::int WHEN hr < 0.90 THEN 18 + floor(random()*4)::int
        ELSE 22 + floor(random()*2)::int END, mins => floor(random()*60)::int) AS created
    FROM draws d
  ), paid AS MATERIALIZED (
    SELECT s.i, s.cu, s.st, s.cancel, s.cancel_paid, s.channel, s.created, CASE WHEN cancel >= 0.03 THEN CASE WHEN pay < 0.4 AND extract(hour FROM created) < 18
      THEN greatest(created + interval '5 minute', p_seen_at) ELSE greatest(p_day::timestamp + interval '1 day' + (9 + random()*9)*interval '1 hour', p_seen_at) END END AS paid
    FROM stamped s
  ), cancelled AS MATERIALIZED (
    SELECT p.i, p.cu, p.st, p.channel, p.created, p.paid, CASE WHEN cancel < 0.03 THEN created + (1 + random()*20)*interval '1 hour'
      WHEN cancel_paid < 0.005 THEN paid + interval '1 hour' END AS cancelled
    FROM paid p
  ), shipped AS MATERIALIZED (
    SELECT c.i, c.cu, c.st, c.channel, c.created, c.paid, c.cancelled, CASE WHEN cancelled IS NULL THEN paid + (2 + random()*28)*interval '1 hour' END AS shipped
    FROM cancelled c
  ), delivered AS MATERIALIZED (
    SELECT s.i, s.cu, s.st, s.channel, s.created, s.paid, s.cancelled, s.shipped, shipped + (6 + random()*66)*interval '1 hour' AS delivered FROM shipped s
  ), visible AS MATERIALIZED (
    SELECT d.i, d.cu, d.st, d.channel, d.created, CASE WHEN paid < p_cutoff THEN paid END AS pa,
      CASE WHEN shipped < p_cutoff THEN shipped END AS sh,
      CASE WHEN delivered < p_cutoff THEN delivered END AS de,
      CASE WHEN cancelled < p_cutoff THEN cancelled END AS ca
    FROM delivered d
  )
  INSERT INTO erp.orders(order_id, order_no, customer_id, store_id, channel, status, order_ts,
                         paid_at, shipped_at, delivered_at, cancelled_at, total_amount, updated_at)
  SELECT nextval('meta.seq_order'), 'ORD-' || lpad(nextval('meta.seq_order_no')::text, 7, '0'),
    customers[1 + floor(cu * array_length(customers, 1))::int],
    CASE WHEN channel = 'shop' THEN stores[1 + floor(st * array_length(stores, 1))::int] ELSE 15 END,
    channel, CASE WHEN ca IS NOT NULL THEN 'cancelled' WHEN de IS NOT NULL THEN 'delivered'
      WHEN sh IS NOT NULL THEN 'shipped' WHEN pa IS NOT NULL THEN 'paid' ELSE 'created' END,
    created, pa, sh, de, ca, 0, greatest(created, pa, sh, de, ca, p_seen_at)
  FROM visible ORDER BY i;
  GET DIAGNOSTICS n = ROW_COUNT;
  SELECT max(order_id) INTO last_id FROM erp.orders;

  WITH available AS MATERIALIZED (
    SELECT a.store_id, array_agg(a.product_id ORDER BY a.product_id) AS products
    FROM meta.assortment a JOIN erp.products p USING (product_id)
    WHERE p.is_active AND p.launched_at <= p_day GROUP BY a.store_id
  ), counts AS MATERIALIZED (
    SELECT o.order_id, o.store_id, o.updated_at, random() AS r FROM erp.orders o
    WHERE o.order_id BETWEEN first_id AND last_id
  ), baskets AS MATERIALIZED (
    SELECT c.order_id, c.store_id, c.updated_at, CASE WHEN r < 0.20 THEN 1 WHEN r < 0.45 THEN 2 WHEN r < 0.72 THEN 3 ELSE 4 + floor(random()*3)::int END AS n
    FROM counts c
  ), draws AS MATERIALIZED (
    SELECT b.order_id, b.updated_at, g.i, a.products, random() AS pick, random() AS quantity,
      0.9 + random()*0.2 AS price FROM baskets b JOIN available a USING (store_id)
    CROSS JOIN LATERAL generate_series(1, b.n) g(i)
  ), chosen AS MATERIALIZED (
    SELECT d.order_id, d.updated_at, d.i, d.price, products[1 + floor(pick * array_length(products, 1))::int] AS product_id,
      CASE WHEN quantity < 0.28 THEN 1 WHEN quantity < 0.58 THEN 2 WHEN quantity < 0.80 THEN 3 ELSE 4 + floor(random()*3)::int END AS qty
    FROM draws d
  ), priced AS MATERIALIZED (
    SELECT c.order_id, c.updated_at, c.i, c.product_id, c.qty, round(p.list_price * c.price)::bigint AS unit_price FROM chosen c JOIN erp.products p USING (product_id)
  )
  INSERT INTO erp.order_lines(order_line_id, order_id, product_id, qty, unit_price, discount_pct, line_amount, updated_at)
  SELECT nextval('meta.seq_line'), order_id, product_id, qty, unit_price, 0, qty::bigint*unit_price, updated_at
  FROM priced ORDER BY order_id, i;

  WITH choices AS MATERIALIZED (
    SELECT o.order_id, o.order_ts, pr.promo_id, pr.mechanics, pr.discount_value, random() AS lag
    FROM erp.orders o CROSS JOIN LATERAL (
      SELECT p.promo_id, p.mechanics, p.discount_value FROM crm.promotions p
      WHERE o.order_ts::date BETWEEN p.starts_at AND p.ends_at
      ORDER BY md5(p.promo_id || o.order_id::text) LIMIT 1
    ) pr WHERE o.order_id BETWEEN first_id AND last_id AND o.order_id % 100 < 15
  )
  INSERT INTO meta.order_promotions(order_id, promo_id, mechanics, discount_value, attached_at, sync_due)
  SELECT order_id, promo_id, mechanics, discount_value, order_ts,
    greatest(order_ts + (1 + lag*2)*interval '1 day', p_seen_at) FROM choices;
  PERFORM meta.reprice_orders(first_id, last_id);
  RETURN n;
END $$;

CREATE OR REPLACE FUNCTION meta.sync_payments()
RETURNS void LANGUAGE plpgsql SET TimeZone = 'UTC' AS $$
BEGIN
  WITH eligible AS MATERIALIZED (
    SELECT o.order_id, o.paid_at, o.total_amount, o.channel, random() AS method_r
    FROM erp.orders o WHERE o.paid_at IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM erp.payments p WHERE p.order_id = o.order_id)
  )
  INSERT INTO erp.payments(payment_id, order_id, paid_ts, method, amount, status, updated_at)
  SELECT nextval('meta.seq_payment'), e.order_id, e.paid_at,
    CASE WHEN g.i = 2 THEN 'gift' WHEN e.channel <> 'shop' THEN 'online'
      WHEN e.method_r < 0.7 THEN 'card' ELSE 'cash' END,
    CASE WHEN e.order_id % 100 >= 7 THEN e.total_amount WHEN g.i = 1 THEN round(e.total_amount*0.6)::bigint
      ELSE e.total_amount - round(e.total_amount*0.6)::bigint END, 'captured', e.paid_at
  FROM eligible e CROSS JOIN LATERAL generate_series(1, CASE WHEN e.order_id % 100 < 7 THEN 2 ELSE 1 END) g(i)
  ORDER BY e.order_id, g.i;

  WITH returns AS (
    SELECT l.order_id, sum(r.refund_amount) AS amount, max(r.return_ts) AS last_at
    FROM erp.returns r JOIN erp.order_lines l USING (order_line_id) GROUP BY l.order_id
  ), totals AS (
    SELECT order_id, sum(amount) AS charged FROM erp.payments GROUP BY order_id
  ), target AS (
    SELECT o.order_id,
      greatest(t.charged - CASE WHEN o.status = 'cancelled' THEN 0 ELSE o.total_amount - COALESCE(r.amount, 0) END, 0) AS refund,
      greatest(o.cancelled_at, r.last_at, a.updated_at) AS at
    FROM erp.orders o JOIN totals t USING (order_id) LEFT JOIN returns r USING (order_id)
    LEFT JOIN meta.order_adjustments a USING (order_id)
  ), allocated AS (
    SELECT p.payment_id, greatest(least(p.amount, t.refund - COALESCE(sum(p.amount) OVER
      (PARTITION BY p.order_id ORDER BY p.payment_id ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0)), 0)::bigint AS refund,
      greatest(t.at, p.paid_ts) AS at FROM erp.payments p JOIN target t USING (order_id)
  )
  UPDATE erp.payments p SET refunded_amount = a.refund,
    status = CASE WHEN a.refund = 0 THEN 'captured' WHEN a.refund = p.amount THEN 'refunded' ELSE 'partially_refunded' END,
    refunded_at = CASE WHEN a.refund > 0 THEN a.at END,
    updated_at = greatest(p.updated_at, a.at)
  FROM allocated a WHERE p.payment_id = a.payment_id AND p.refunded_amount IS DISTINCT FROM a.refund;
END $$;

CREATE OR REPLACE FUNCTION meta.mark_full_returns()
RETURNS void LANGUAGE plpgsql SET TimeZone = 'UTC' AS $$
BEGIN
  WITH returned AS (
    SELECT l.order_id, sum(r.qty) AS qty, max(r.return_ts) AS at
    FROM erp.returns r JOIN erp.order_lines l USING (order_line_id) GROUP BY l.order_id
  ), bought AS (
    SELECT order_id, sum(qty) AS qty FROM erp.order_lines GROUP BY order_id
  )
  UPDATE erp.orders o SET status = 'returned', updated_at = greatest(o.updated_at, r.at)
  FROM returned r JOIN bought b USING (order_id)
  WHERE o.order_id = r.order_id AND r.qty = b.qty AND o.status <> 'returned';
END $$;

CREATE OR REPLACE FUNCTION meta.publish_promotions(p_cutoff timestamptz)
RETURNS integer LANGUAGE plpgsql SET TimeZone = 'UTC' AS $$
DECLARE n integer;
BEGIN
  WITH delivered AS (
    INSERT INTO crm.promo_participation(id, promo_id, order_no, attached_at, sync_ts)
    SELECT nextval('meta.seq_participation'), p.promo_id, o.order_no, p.attached_at, p.sync_due
    FROM meta.order_promotions p JOIN erp.orders o USING (order_id)
    WHERE p.sync_due < p_cutoff AND o.status <> 'cancelled'
      AND NOT EXISTS (SELECT 1 FROM crm.promo_participation c WHERE c.order_no = o.order_no AND c.promo_id = p.promo_id)
    ORDER BY p.sync_due, p.order_id RETURNING id, promo_id, attached_at, sync_ts
  )
  INSERT INTO crm.promo_participation(id, promo_id, order_no, attached_at, sync_ts)
  SELECT nextval('meta.seq_participation'), promo_id, 'ORD-X' || id::text, attached_at, sync_ts
  FROM delivered WHERE id % 100 = 0;
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END $$;

CREATE OR REPLACE FUNCTION meta.snapshot_inventory(p_day date)
RETURNS integer LANGUAGE plpgsql SET TimeZone = 'UTC' AS $$
DECLARE n integer;
BEGIN
  INSERT INTO meta.inventory_balance(store_id, product_id, qty_on_hand, qty_reserved)
  SELECT a.store_id, a.product_id, 20 + floor(random()*180)::int, 0
  FROM meta.assortment a JOIN erp.stores s USING (store_id) JOIN erp.products p USING (product_id)
  WHERE p.is_active AND p.launched_at <= p_day AND s.opened_at <= p_day
    AND (s.closed_at IS NULL OR s.closed_at >= p_day)
  ON CONFLICT (store_id, product_id) DO NOTHING;

  WITH events AS (
    SELECT o.store_id, l.product_id, 0::bigint AS shipped, sum(l.qty) AS reserved, 0::bigint AS returned
    FROM erp.orders o JOIN erp.order_lines l USING (order_id)
    WHERE o.paid_at >= p_day::timestamptz AND o.paid_at < (p_day+1)::timestamptz GROUP BY 1,2
    UNION ALL
    SELECT o.store_id, l.product_id, sum(l.qty), -sum(l.qty), 0 FROM erp.orders o JOIN erp.order_lines l USING (order_id)
    WHERE o.shipped_at >= p_day::timestamptz AND o.shipped_at < (p_day+1)::timestamptz GROUP BY 1,2
    UNION ALL
    SELECT o.store_id, l.product_id, 0, -sum(l.qty), 0 FROM erp.orders o JOIN erp.order_lines l USING (order_id)
    WHERE o.cancelled_at >= p_day::timestamptz AND o.cancelled_at < (p_day+1)::timestamptz
      AND o.paid_at IS NOT NULL AND o.shipped_at IS NULL GROUP BY 1,2
    UNION ALL
    SELECT o.store_id, l.product_id, 0, 0, sum(r.qty) FROM erp.returns r
    JOIN erp.order_lines l USING (order_line_id) JOIN erp.orders o USING (order_id)
    WHERE r.return_ts >= p_day::timestamptz AND r.return_ts < (p_day+1)::timestamptz GROUP BY 1,2
  ), changes AS (
    SELECT store_id, product_id, sum(shipped)::int AS shipped, sum(reserved)::int AS reserved,
      sum(returned)::int AS returned FROM events GROUP BY 1,2
  ), balance AS MATERIALIZED (
    SELECT b.store_id, b.product_id, b.qty_on_hand AS opening, COALESCE(c.shipped,0) AS shipped,
      COALESCE(c.returned,0) AS returned, b.qty_reserved + COALESCE(c.reserved,0) AS reserved,
      b.qty_on_hand + COALESCE(c.returned,0) - COALESCE(c.shipped,0) AS before_receipt
    FROM meta.inventory_balance b LEFT JOIN changes c USING (store_id, product_id)
  ), replenished AS MATERIALIZED (
    SELECT b.store_id, b.product_id, b.opening, b.shipped, b.returned, b.reserved, b.before_receipt, CASE WHEN before_receipt < reserved THEN reserved - before_receipt + 20 + floor(random()*180)::int ELSE 0 END AS received
    FROM balance b
  )
  INSERT INTO meta.inventory_movements(snap_date, store_id, product_id, opening_qty, received_qty,
                                       shipped_qty, returned_qty, closing_qty, reserved_qty)
  SELECT p_day, store_id, product_id, opening, received, shipped, returned, before_receipt + received, reserved
  FROM replenished;

  UPDATE meta.inventory_balance b SET qty_on_hand = m.closing_qty, qty_reserved = m.reserved_qty
  FROM meta.inventory_movements m WHERE m.snap_date = p_day AND b.store_id = m.store_id AND b.product_id = m.product_id;
  INSERT INTO erp.inventory(snap_date, store_id, product_id, qty_on_hand, qty_reserved)
  SELECT m.snap_date, m.store_id, m.product_id, m.closing_qty, m.reserved_qty
  FROM meta.inventory_movements m JOIN erp.stores s USING (store_id)
  WHERE m.snap_date = p_day AND s.opened_at <= p_day AND (s.closed_at IS NULL OR s.closed_at >= p_day);
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END $$;

-- Параметры объёма позволяют проверять настоящий seed на небольшом наборе.
DROP FUNCTION IF EXISTS meta.seed_history(date);
CREATE OR REPLACE FUNCTION meta.seed_history(
  p_t0 date DEFAULT current_date - 60, p_history_days integer DEFAULT 1155,
  p_customers integer DEFAULT 50000, p_products integer DEFAULT 5000, p_daily_orders integer DEFAULT 350)
RETURNS void LANGUAGE plpgsql SET TimeZone = 'UTC' AS $$
DECLARE
  v_hist_start date := p_t0 - p_history_days + 1;
  v_t0_eod timestamptz := (p_t0 + 1)::timestamptz;
  d date; v_count integer;
BEGIN
  PERFORM pg_advisory_xact_lock(87206310);
  PERFORM set_config('TimeZone', 'UTC', true);
  IF p_history_days NOT BETWEEN 7 AND 1155 OR p_customers < 4 OR p_products < 4 OR p_daily_orders < 1 THEN
    RAISE EXCEPTION 'Ожидаются 7..1155 дней, не менее 4 клиентов/товаров и положительный дневной объём';
  END IF;
  PERFORM setseed(0.42);
  PERFORM meta.reset_sources();
  INSERT INTO meta.config VALUES ('t0',p_t0::text), ('history_days',p_history_days::text),
    ('daily_orders',p_daily_orders::text), ('generator_version','4.0.0');
  -- Справочники вставляются ниже; первые четыре товара доступны с начала истории.
  RAISE NOTICE '[seed] stores… %', clock_timestamp();
  -- ---------------------------------------------------------------- stores --
  -- 14 офлайн + 1 онлайн (id 15); открытие 16-го и закрытие одного — в simulate_day
  INSERT INTO erp.stores (store_id, name, format, city, region, opened_at, updated_at)
  VALUES
    (1,  'Москва-Центр',    'mall',   'Москва',         'Центр',          p_t0 - 2800, p_t0 - 2800),
    (2,  'Москва-Север',    'street', 'Москва',         'Центр',          p_t0 - 2650, p_t0 - 2650),
    (3,  'Москва-Юг',       'mall',   'Москва',         'Центр',          p_t0 - 2500, p_t0 - 2500),
    (4,  'СПб-Невский',     'mall',   'Санкт-Петербург','Северо-Запад',   p_t0 - 2400, p_t0 - 2400),
    (5,  'СПб-Приморская',  'street', 'Санкт-Петербург','Северо-Запад',   p_t0 - 2200, p_t0 - 2200),
    (6,  'Екатеринбург-1',  'mall',   'Екатеринбург',   'Урал',           p_t0 - 2100, p_t0 - 2100),
    (7,  'Новосибирск-1',   'mall',   'Новосибирск',    'Сибирь',         p_t0 - 1950, p_t0 - 1950),
    (8,  'Казань-Центр',    'street', 'Казань',         'Поволжье',       p_t0 - 1800, p_t0 - 1800),
    (9,  'Нижний-Новгород', 'mall',   'Нижний Новгород','Поволжье',       p_t0 - 1650, p_t0 - 1650),
    (10, 'Ростов-на-Дону',  'mall',   'Ростов-на-Дону', 'Юг',             p_t0 - 1500, p_t0 - 1500),
    (11, 'Краснодар-1',     'street', 'Краснодар',      'Юг',             p_t0 - 1350, p_t0 - 1350),
    (12, 'Самара-1',        'mall',   'Самара',         'Поволжье',       p_t0 - 1200, p_t0 - 1200),
    (13, 'Воронеж-1',       'street', 'Воронеж',        'Центр',          p_t0 - 1100, p_t0 - 1100),
    (14, 'Пермь-1',         'mall',   'Пермь',          'Урал',           p_t0 - 1000, p_t0 - 1000),
    (15, 'ONLINE',          'online', 'Интернет',       'Интернет',       p_t0 - 1155, p_t0 - 1155);

  RAISE NOTICE '[seed] categories… %', clock_timestamp();
  -- ------------------------------------------------------------- categories --
  -- 3 уровня: 25 корней × 4 подкатегории × 2 группы ≈ 325 строк (~350 по спеке)
  INSERT INTO erp.categories (category_id, parent_category_id, name)
  WITH roots(k, nm) AS (VALUES
    (1,'Напитки'),(2,'Молочное'),(3,'Выпечка'),(4,'Овощи и фрукты'),(5,'Мясо и рыба'),
    (6,'Заморозка'),(7,'Бакалея'),(8,'Консервация'),(9,'Кондитерские'),(10,'Снеки'),
    (11,'Бытовая химия'),(12,'Гигиена'),(13,'Уход за домом'),(14,'Корма'),(15,'Товары для детей'),
    (16,'Канцелярия'),(17,'Электроника'),(18,'Ткани'),(19,'Сезонные'),(20,'Украшения'),
    (21,'Спорт'),(22,'Автотовары'),(23,'Сад'),(24,'Игрушки'),(25,'Прочее')),
  l2 AS (SELECT 100 + (k - 1) * 4 + n AS category_id, k
         FROM roots CROSS JOIN generate_series(1, 4) n),
  l3 AS (SELECT 1000 + (row_number() OVER (ORDER BY l.category_id, n))::int AS category_id,
                l.category_id AS parent
         FROM l2 l CROSS JOIN generate_series(1, 2) n)
  SELECT k, NULL::integer, nm FROM roots
  UNION ALL
  SELECT category_id, k, 'Подкатегория ' || category_id FROM l2
  UNION ALL
  SELECT category_id, parent, 'Группа ' || category_id FROM l3;

  RAISE NOTICE '[seed] products… %', clock_timestamp();
  -- --------------------------------------------------------------- products --
  -- Исправление M0 (L12): некоррелированный LATERAL с random() = InitPlan
  -- (перерисовывается только на воркер) → все товары в одной категории.
  -- Розыгрыши делаются в select list внешнего потока строк (per-row),
  -- категория — детерминированный array-index по листовым категориям.
  INSERT INTO erp.products (product_id, sku, category_id, brand, list_price, is_active, launched_at, updated_at)
  SELECT g,
         'SKU-' || lpad(g::text, 5, '0'),
         leaf.category_id,
         (ARRAY['Aresa','Belltra','Cortez','Dolce','Evita','Fargo','Grania','Hollis','Inara','Jordan',
                'Krafto','Lumen','Mira','Nordia','Orbis','Prima','Quinta','Rolva','Sirena','Talco'])
             [1 + floor(b.r_brand * 20)::int],
         (50 + floor(b.r_price * b.r_price * 14950))::bigint,   -- смещение к дешёвым
         (g <= 4 OR b.r_act < 0.5),                                          -- ~2500 активных
         v_hist_start + CASE WHEN g <= 4 THEN 0 ELSE floor(b.r_launch * (p_history_days-1))::int END,
         v_hist_start + CASE WHEN g <= 4 THEN 0 ELSE floor(b.r_launch * (p_history_days-1))::int END
  FROM (SELECT g,
               random() AS r_cat, random() AS r_brand, random() AS r_price,
               random() AS r_act,  random() AS r_launch
        FROM generate_series(1, p_products) g) b
  CROSS JOIN LATERAL (                    -- коррелирован по b — InitPlan невозможен
    SELECT cats.arr[1 + floor(b.r_cat * array_length(cats.arr, 1))::int] AS category_id
    FROM (SELECT array_agg(c.category_id ORDER BY c.category_id) AS arr
          FROM erp.categories c
          WHERE c.parent_category_id IS NOT NULL
            AND NOT EXISTS (SELECT 1 FROM erp.categories ch
                            WHERE ch.parent_category_id = c.category_id)) cats
  ) leaf;

  RAISE NOTICE '[seed] customers… %', clock_timestamp();
  -- -------------------------------------------------------------- customers --
  -- Исправление M0 (L12): все registered_at в одну дату (InitPlan lateral).
  -- Розыгрыши в select list внешнего потока; город/регион — парные массивы
  -- по ОДНОМУ индексу (согласованная пара city+region на клиента).
  INSERT INTO erp.customers (customer_id, segment, city, region, registered_at, updated_at)
  SELECT g,
         CASE WHEN b.r_s1 < 0.80 THEN 'standard'
              WHEN b.r_s2 < 0.75 THEN 'premium' ELSE 'vip' END,
         (ARRAY['Москва','Санкт-Петербург','Екатеринбург','Новосибирск','Казань',
                'Нижний Новгород','Ростов-на-Дону','Краснодар','Самара','Воронеж',
                'Пермь','Волгоград'])[idx],
         (ARRAY['Центр','Северо-Запад','Урал','Сибирь','Поволжье',
                'Поволжье','Юг','Юг','Поволжье','Центр',
                'Урал','Юг'])[idx],
         CASE WHEN g <= 4 THEN v_hist_start - interval '1 day' ELSE (v_hist_start - interval '3 year') + b.r_ts * (p_t0::timestamp - (v_hist_start - interval '3 year')) END,
         CASE WHEN g <= 4 THEN v_hist_start - interval '1 day' ELSE (v_hist_start - interval '3 year') + b.r_ts * (p_t0::timestamp - (v_hist_start - interval '3 year')) END
  FROM (SELECT g,
               random() AS r_s1, random() AS r_s2,
               random() AS r_ts, random() AS r_city
        FROM generate_series(1, p_customers) g) b
  CROSS JOIN LATERAL (
    SELECT 1 + floor(b.r_city * 12)::int AS idx
  ) i;

  RAISE NOTICE '[seed] assortment… %', clock_timestamp();
  -- ------------------------------------------------- ассортиментная матрица --
  INSERT INTO meta.assortment (store_id, product_id)
  SELECT s.store_id, p.product_id
  FROM erp.stores s CROSS JOIN erp.products p
  WHERE s.format <> 'online' AND p.is_active AND p.launched_at <= p_t0 AND (p.product_id <= 4 OR random() < 0.85);
  INSERT INTO meta.assortment (store_id, product_id)
  SELECT 15, p.product_id FROM erp.products p WHERE p.is_active AND p.launched_at <= p_t0;
  PERFORM meta.renumber_assortment(s.store_id) FROM (SELECT DISTINCT store_id FROM meta.assortment) s;

  RAISE NOTICE '[seed] promotions… %', clock_timestamp();
  -- ------------------------------------------------------------- promotions --
  -- Исправление M0 (L12): все акции в один день (InitPlan lateral). Розыгрыши
  -- во внешнем потоке, laterals коррелированы по b — InitPlan невозможен.
  -- L64: будущая дата старта акции не сдвигает updated_at дальше T0;
  -- иначе общий watermark bronze пропускает изменения первых дней симуляции.
  INSERT INTO crm.promotions (promo_id, name, mechanics, discount_value, starts_at, ends_at, status, updated_at)
  SELECT 'PR-' || EXTRACT(YEAR FROM tt.st)::int || '-' || lpad(g::text, 3, '0'),
         'Акция ' || g || '-' || EXTRACT(YEAR FROM tt.st)::int,
         mec.mechanics,
         CASE mec.mechanics WHEN 'percent' THEN 5 + floor(b.r_dv * 25)
                            WHEN 'fixed'   THEN 5000 + floor(b.r_dv * 45000)
                            ELSE 1 END::numeric(10,2),
         tt.st::date,
         (tt.st + (7 + floor(b.r_dur * 53)) * interval '1 day')::date,
         CASE WHEN (tt.st + (7 + floor(b.r_dur * 53)) * interval '1 day')::date < p_t0 THEN 'closed'
              WHEN tt.st::date > p_t0 THEN 'planned'
              ELSE 'active' END,
         least(tt.st, p_t0::timestamptz)
  FROM (SELECT g,
               random() AS r_st, random() AS r_dur,
               random() AS r_m1, random() AS r_m2, random() AS r_dv
        FROM generate_series(1, 60) g) b
  CROSS JOIN LATERAL (
    SELECT v_hist_start + (b.r_st * (p_history_days+70)) * interval '1 day' AS st) tt
  CROSS JOIN LATERAL (
    SELECT CASE WHEN b.r_m1 < 0.6 THEN 'percent'
                WHEN b.r_m2 < 0.5 THEN 'fixed' ELSE 'bundle' END AS mechanics) mec;



  FOR d IN SELECT g::date FROM generate_series(v_hist_start, p_t0, interval '1 day') g LOOP
    v_count := round(p_daily_orders * CASE extract(dow FROM d) WHEN 0 THEN 1.25 WHEN 6 THEN 1.3 WHEN 5 THEN 1.15 ELSE 1 END
      * (0.8 + 0.4 * (d-v_hist_start)::numeric / p_history_days))::integer;
    PERFORM meta.create_orders(d, v_count, v_t0_eod);
    IF (d-v_hist_start)%100=0 THEN RAISE NOTICE '[seed] заказы: %',d; END IF;
  END LOOP;

  WITH draws AS MATERIALIZED (
    SELECT l.order_line_id, l.qty, l.line_amount,
      o.delivered_at + (1 + random()*25)*interval '1 day' AS return_ts,
      LEAST(l.qty, 1 + (random()<0.35)::integer) AS qty_returned, random() AS selected,
      1 + floor(random()*5)::integer AS reason
    FROM erp.order_lines l JOIN erp.orders o USING (order_id) WHERE o.delivered_at IS NOT NULL
  )
  INSERT INTO erp.returns(return_id, order_line_id, return_ts, qty, reason, refund_amount)
  SELECT nextval('meta.seq_return'), order_line_id, return_ts, qty_returned,
    (ARRAY['defect','wrong_item','changed_mind','damaged_delivery','late_delivery'])[reason],
    round(line_amount::numeric * qty_returned / qty)::bigint
  FROM draws WHERE selected < 0.04 AND return_ts < v_t0_eod ORDER BY return_ts, order_line_id;
  PERFORM meta.mark_full_returns();
  PERFORM meta.sync_payments();
  PERFORM meta.publish_promotions(v_t0_eod);
  FOR d IN SELECT g::date FROM generate_series(v_hist_start, p_t0, interval '1 day') g LOOP
    PERFORM meta.snapshot_inventory(d);
    IF (d-v_hist_start)%100=0 THEN RAISE NOTICE '[seed] остатки: %',d; END IF;
  END LOOP;
  INSERT INTO meta.simulated_days(sim_date,stats) VALUES(p_t0,jsonb_build_object('seed',true,'generator_version','4.0.0'));
END $$;

CREATE OR REPLACE FUNCTION meta.simulate_day(p_date date)
RETURNS jsonb LANGUAGE plpgsql SET TimeZone = 'UTC' AS $$
DECLARE
  v_t0 date; v_next_day date; v_day_start timestamptz := p_date::timestamp;
  v_ts timestamptz := p_date::timestamp + interval '9 hour';
  v_cutoff timestamptz := (p_date+1)::timestamptz;
  v_daily integer; v_n integer; v_ord bigint; v_fixed integer := 0;
  v_stats jsonb := '{}'::jsonb;
BEGIN
  PERFORM pg_advisory_xact_lock(87206310);
  PERFORM set_config('TimeZone', 'UTC', true);
  SELECT v::date INTO v_t0 FROM meta.config WHERE k='t0';
  IF v_t0 IS NULL THEN RAISE EXCEPTION 'сначала выполните meta.seed_history()'; END IF;
  IF EXISTS(SELECT 1 FROM meta.simulated_days WHERE sim_date=p_date) THEN
    RAISE EXCEPTION 'день % уже прожит; перезалив дня — операция DWH, не генератора (§2.5)',p_date;
  END IF;
  SELECT max(sim_date)+1 INTO v_next_day FROM meta.simulated_days;
  IF p_date IS DISTINCT FROM v_next_day THEN RAISE EXCEPTION 'ожидался следующий день %, получен %',v_next_day,p_date; END IF;
  PERFORM setseed(meta.day_seed(p_date));
  SELECT COALESCE((SELECT v::integer FROM meta.config WHERE k='daily_orders'),350) INTO v_daily;

  -- Объявленные события магазинов применяются до выбора магазина новой покупки.
  IF p_date=v_t0+15 THEN
    INSERT INTO erp.stores(store_id,name,format,city,region,opened_at,updated_at)
    VALUES(16,'Москва-Восток','mall','Москва','Центр',p_date,v_ts);
    INSERT INTO meta.assortment(store_id,product_id)
    SELECT 16,product_id FROM erp.products WHERE is_active AND (product_id<=4 OR random()<0.6);
    PERFORM meta.renumber_assortment(16);
  END IF;
  IF p_date=v_t0+45 THEN UPDATE erp.stores SET closed_at=p_date,updated_at=v_ts WHERE store_id=13; END IF;

  IF p_date=v_t0+20 THEN
    UPDATE crm.promotions SET ends_at=ends_at+14,updated_at=v_ts
    WHERE promo_id=(SELECT promo_id FROM crm.promotions WHERE starts_at<=p_date AND ends_at>=p_date ORDER BY random() LIMIT 1);
  END IF;
  IF p_date=v_t0+35 THEN
    UPDATE crm.promotions SET ends_at=p_date-1,updated_at=v_ts
    WHERE promo_id=(SELECT promo_id FROM crm.promotions WHERE starts_at<p_date AND ends_at>=p_date ORDER BY random() LIMIT 1);
  END IF;
  UPDATE crm.promotions SET status=CASE WHEN p_date>ends_at THEN 'closed' WHEN p_date>=starts_at THEN 'active' ELSE 'planned' END,
    updated_at=v_ts
  WHERE status<>CASE WHEN p_date>ends_at THEN 'closed' WHEN p_date>=starts_at THEN 'active' ELSE 'planned' END;

  UPDATE erp.orders SET status='delivered',delivered_at=v_day_start+(10+random()*8)*interval '1 hour'
  WHERE status='shipped' AND shipped_at<v_day_start-interval '20 hour' AND random()<0.8;
  GET DIAGNOSTICS v_n=ROW_COUNT; v_stats:=v_stats||jsonb_build_object('delivered',v_n);
  UPDATE erp.orders SET status='shipped',shipped_at=v_day_start+(9+random()*6)*interval '1 hour'
  WHERE status='paid' AND paid_at<v_day_start-interval '10 hour' AND random()<0.85;
  GET DIAGNOSTICS v_n=ROW_COUNT; v_stats:=v_stats||jsonb_build_object('shipped',v_n);
  UPDATE erp.orders SET status='paid',paid_at=v_day_start+(9+random()*9)*interval '1 hour'
  WHERE status='created' AND order_ts<v_day_start-interval '6 hour' AND random()<0.9;
  GET DIAGNOSTICS v_n=ROW_COUNT; v_stats:=v_stats||jsonb_build_object('paid',v_n);
  UPDATE erp.orders SET status='cancelled',cancelled_at=v_day_start+(9+random()*9)*interval '1 hour'
  WHERE status='created' AND order_ts<v_day_start-interval '6 hour' AND random()<0.05;
  GET DIAGNOSTICS v_n=ROW_COUNT; v_stats:=v_stats||jsonb_build_object('cancelled',v_n);

  WITH draws AS MATERIALIZED (
    SELECT l.order_line_id,l.qty,l.line_amount,
      LEAST(l.qty-COALESCE(r.qty,0),1+(random()<0.35)::integer)::integer AS rq,
      COALESCE(r.qty,0) AS previous_qty,COALESCE(r.amount,0) AS previous_amount,
      v_ts+random()*interval '8 hour' AS at,random() AS selected,1+floor(random()*5)::integer AS reason
    FROM erp.order_lines l JOIN erp.orders o USING(order_id)
    LEFT JOIN(SELECT order_line_id,sum(qty) AS qty,sum(refund_amount) AS amount FROM erp.returns GROUP BY order_line_id) r USING(order_line_id)
    WHERE o.status='delivered' AND o.delivered_at>=v_day_start-interval '12 day' AND o.delivered_at<v_day_start
  )
  INSERT INTO erp.returns(return_id,order_line_id,return_ts,qty,reason,refund_amount)
  SELECT nextval('meta.seq_return'),order_line_id,at,rq,
    (ARRAY['defect','wrong_item','changed_mind','damaged_delivery','late_delivery'])[reason],
    round(line_amount::numeric*(previous_qty+rq)/qty)::bigint-previous_amount
  FROM draws WHERE selected<0.04 AND rq>0 ORDER BY order_line_id;
  GET DIAGNOSTICS v_n=ROW_COUNT; v_stats:=v_stats||jsonb_build_object('returns_new',v_n);

  -- =============================== 4. Смены сегмента/города (~30/день, №1)
  UPDATE erp.customers SET
    segment = CASE segment
      WHEN 'standard' THEN CASE WHEN random() < 0.85 THEN 'premium' ELSE 'vip' END
      WHEN 'premium'  THEN CASE WHEN random() < 0.55 THEN 'vip' ELSE 'standard' END
      ELSE CASE WHEN random() < 0.7 THEN 'premium' ELSE 'standard' END END,
    updated_at = v_ts
  WHERE customer_id IN (SELECT customer_id FROM erp.customers
                        WHERE deleted_at IS NULL ORDER BY random() LIMIT 20);
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_stats := v_stats || jsonb_build_object('segment_changes', v_n);

  UPDATE erp.customers cu SET city = pr.c, region = pr.r, updated_at = v_ts
  FROM (SELECT customer_id, floor(random()*12)::int + 1 AS idx
        FROM erp.customers WHERE deleted_at IS NULL ORDER BY random() LIMIT 10) s
  JOIN (VALUES (1,'Москва','Центр'),(2,'Санкт-Петербург','Северо-Запад'),(3,'Екатеринбург','Урал'),
        (4,'Новосибирск','Сибирь'),(5,'Казань','Поволжье'),(6,'Нижний Новгород','Поволжье'),
        (7,'Ростов-на-Дону','Юг'),(8,'Краснодар','Юг'),(9,'Самара','Поволжье'),(10,'Воронеж','Центр'),
        (11,'Пермь','Урал'),(12,'Волгоград','Юг')) pr(i, c, r) ON pr.i = s.idx
  WHERE cu.customer_id = s.customer_id;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_stats := v_stats || jsonb_build_object('city_moves', v_n);

  -- редкий soft delete (~1 клиент в 12 дней, паттерн №4)
  IF random() < 1.0/12 THEN
    UPDATE erp.customers SET deleted_at = v_ts, updated_at = v_ts
    WHERE customer_id = (SELECT customer_id FROM erp.customers
                         WHERE deleted_at IS NULL ORDER BY random() LIMIT 1);
  END IF;

  -- перенос товара между категориями (~1/2 дня, паттерн №5)
  IF random() < 0.5 THEN
    UPDATE erp.products p SET category_id = c.category_id, updated_at = v_ts
    FROM (SELECT category_id FROM erp.categories c2
          WHERE NOT EXISTS (SELECT 1 FROM erp.categories ch WHERE ch.parent_category_id = c2.category_id)
          ORDER BY random() LIMIT 1) c
    WHERE p.product_id = (SELECT product_id FROM erp.products WHERE is_active
                          ORDER BY random() LIMIT 1)
      AND c.category_id <> p.category_id;
  END IF;




  -- Рост объёма seed продолжается без искусственного провала на границе T0.
  v_n:=round(v_daily*1.2*CASE extract(dow FROM p_date) WHEN 0 THEN 1.25 WHEN 6 THEN 1.3 WHEN 5 THEN 1.15 ELSE 1 END)::integer;
  v_n:=meta.create_orders(p_date,v_n,v_cutoff);
  v_n:=v_n+meta.create_orders(p_date-1,2,v_cutoff,v_ts);
  v_stats:=v_stats||jsonb_build_object('new_orders',v_n,'late_arriving',2);

  FOR v_ord IN SELECT order_id FROM erp.orders
    WHERE status IN('paid','shipped') AND order_ts>p_date-30 AND paid_at<v_day_start
    ORDER BY random() LIMIT 3 LOOP
    INSERT INTO meta.order_adjustments(order_id,discount_pct,updated_at) VALUES(v_ord,5,v_day_start+interval '20 hour')
    ON CONFLICT(order_id) DO UPDATE SET discount_pct=LEAST(30,meta.order_adjustments.discount_pct+5),updated_at=EXCLUDED.updated_at;
    PERFORM meta.reprice_orders(v_ord,v_ord,v_day_start+interval '20 hour');
    v_fixed:=v_fixed+1;
  END LOOP;
  v_stats:=v_stats||jsonb_build_object('amount_fixes',v_fixed);

  PERFORM meta.mark_full_returns();
  UPDATE erp.orders SET updated_at=greatest(updated_at,order_ts,paid_at,shipped_at,delivered_at,cancelled_at)
  WHERE updated_at<greatest(order_ts,paid_at,shipped_at,delivered_at,cancelled_at);
  PERFORM meta.sync_payments();
  v_n:=meta.snapshot_inventory(p_date);
  v_stats:=v_stats||jsonb_build_object('inventory_rows',v_n);
  PERFORM meta.publish_promotions(v_cutoff);
  INSERT INTO meta.simulated_days(sim_date,stats) VALUES(p_date,v_stats);
  RETURN v_stats;
END $$;

CREATE OR REPLACE FUNCTION meta.reset_sources()
RETURNS void LANGUAGE plpgsql SET TimeZone = 'UTC' AS $$
BEGIN
  PERFORM pg_advisory_xact_lock(87206310);
  TRUNCATE meta.inventory_movements,meta.inventory_balance,meta.order_adjustments,meta.order_promotions,
    erp.inventory,erp.returns,erp.payments,erp.order_lines,erp.orders,erp.customers,erp.products,
    erp.categories,erp.stores,crm.promo_participation,crm.promotions,meta.simulated_days,meta.assortment,meta.assortment_cnt,meta.config;
  PERFORM setval('meta.seq_order',1,false),setval('meta.seq_order_no',1,false),setval('meta.seq_line',1,false),
    setval('meta.seq_payment',1,false),setval('meta.seq_return',1,false),setval('meta.seq_participation',1,false);
END $$;
