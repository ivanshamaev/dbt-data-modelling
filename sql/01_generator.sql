-- ============================================================================
-- RetailCo: генератор «проживание истории» (план §2.5)
--
--   meta.seed_history()      — backfill ~3 лет истории обоих источников до T0
--                              (T0 = current_date - 60 по умолчанию)
--   meta.simulate_day(date)  — прожить один день; повтор на прожитую дату = ошибка
--   meta.reset_sources()     — очистить все данные и журнал (dev)
--
-- Инженерные гарантии (§2.5):
--   1) Консистентность: SUM(order_lines.line_amount) = orders.total_amount;
--      сумма returns.qty по строке <= line.qty;
--      платежи допускают учебные расхождения L26 (порог проверяется отдельно);
--      refund пропорционален доле возвращённого.
--   2) Идемпотентность по датам: журнал meta.simulated_days; день применяется
--      целиком (одна транзакция) и не переигрывается. «Перезалив дня» — операция
--      DWH (гл. 13), а не генератора.
--   3) Watermark-контракт: каждое изменение источника бампает updated_at.
--
-- setseed() фиксирует последовательность случайных чисел. Воспроизводимость
-- также требует одинакового состояния источников, последовательностей и порядка исполнения SQL.
--
-- Объём/время (M0: замерить и вписать в README): orders ≈ 404k, lines ≈ 1.15M,
-- payments ≈ 430k, returns ≈ 45k, inventory ≈ 33M, participation ≈ 60k.
-- Ожидание: seed ~10–15 минут на 4 CPU / 16 GB.
--
-- Допущение (отклонение от §2.2, допустимое для обучения): is_active=false
-- товары не имеют продаж в истории («когда-либо продававшиеся» смоделированы
-- как «есть в справочнике, продаж нет»); активные ~2500 SKU покрывают все KPI.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Хелперы
-- ----------------------------------------------------------------------------

-- Псевдослучайное зерно от даты: детерминизм simulate_day
CREATE OR REPLACE FUNCTION meta.day_seed(p_date date)
RETURNS double precision LANGUAGE sql AS $$
  SELECT ((hashtext(p_date::text))::numeric / 2147483648.0 + 1.0) / 2.0
$$;

-- Перенумерация ассортимента магазина (rn = 1..cnt; O(1)-выбор по (store_id, rn))
CREATE OR REPLACE FUNCTION meta.renumber_assortment(p_store integer)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  UPDATE meta.assortment a SET rn = n.rn
  FROM (SELECT ctid, row_number() OVER (ORDER BY product_id) rn
        FROM meta.assortment WHERE store_id = p_store) n
  WHERE a.ctid = n.ctid;

  INSERT INTO meta.assortment_cnt (store_id, cnt)
  SELECT p_store, count(*) FROM meta.assortment WHERE store_id = p_store
  ON CONFLICT (store_id) DO UPDATE SET cnt = EXCLUDED.cnt;
END $$;

-- ----------------------------------------------------------------------------
-- seed_history(): три года истории до T0
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION meta.seed_history(p_t0 date DEFAULT current_date - 60)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE
  v_hist_start date := p_t0 - 1154;                       -- 1155 дней (~3 года)
  v_t0_eod     timestamptz := p_t0 + interval '1 day';    -- конец суток T0
  v_start date; v_end date;
  v_prev_max bigint; v_first bigint; v_last bigint;
BEGIN
  -- разгон.bulk-вставок учебного стенда (сессия одноразовая — утечка допустима)
  EXECUTE 'SET synchronous_commit = off';
  EXECUTE 'SET maintenance_work_mem = ''512MB''';
  RAISE NOTICE '[seed] start %', clock_timestamp();
  PERFORM setseed(0.42);

  DELETE FROM meta.config; TRUNCATE meta.simulated_days;
  INSERT INTO meta.config VALUES ('t0', p_t0::text);

  TRUNCATE erp.inventory, erp.returns, erp.payments, erp.order_lines, erp.orders,
           erp.customers, erp.products, erp.categories, erp.stores,
           crm.promo_participation, crm.promotions, meta.assortment, meta.assortment_cnt;
  PERFORM setval('meta.seq_order',1,false), setval('meta.seq_order_no',1,false),
           setval('meta.seq_line',1,false), setval('meta.seq_payment',1,false),
           setval('meta.seq_return',1,false), setval('meta.seq_participation',1,false);

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
  -- Багфикк M0 (L12): некоррелированный LATERAL с random() = InitPlan
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
         b.r_act < 0.5,                                          -- ~2500 активных
         v_hist_start + floor(b.r_launch * 1000)::int,
         v_hist_start + floor(b.r_launch * 1000)::int
  FROM (SELECT g,
               random() AS r_cat, random() AS r_brand, random() AS r_price,
               random() AS r_act,  random() AS r_launch
        FROM generate_series(1, 5000) g) b
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
  -- Багфикк M0 (L12): все registered_at в одну дату (InitPlan lateral).
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
         (v_hist_start - interval '3 year') + (b.r_ts * 1600) * interval '1 day',
         (v_hist_start - interval '3 year') + (b.r_ts * 1600) * interval '1 day'
  FROM (SELECT g,
               random() AS r_s1, random() AS r_s2,
               random() AS r_ts, random() AS r_city
        FROM generate_series(1, 50000) g) b
  CROSS JOIN LATERAL (
    SELECT 1 + floor(b.r_city * 12)::int AS idx
  ) i;

  RAISE NOTICE '[seed] assortment… %', clock_timestamp();
  -- ------------------------------------------------- ассортиментная матрица --
  INSERT INTO meta.assortment (store_id, product_id)
  SELECT s.store_id, p.product_id
  FROM erp.stores s CROSS JOIN erp.products p
  WHERE s.format <> 'online' AND p.is_active AND p.launched_at <= p_t0 AND random() < 0.85;
  INSERT INTO meta.assortment (store_id, product_id)
  SELECT 15, p.product_id FROM erp.products p WHERE p.is_active AND p.launched_at <= p_t0;
  PERFORM meta.renumber_assortment(s.store_id) FROM (SELECT DISTINCT store_id FROM meta.assortment) s;

  RAISE NOTICE '[seed] promotions… %', clock_timestamp();
  -- ------------------------------------------------------------- promotions --
  -- Багфикк M0 (L12): все акции в один день (InitPlan lateral). Розыгрыши
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
         CASE WHEN (tt.st + interval '30 day')::date < p_t0 THEN 'closed'
              WHEN tt.st::date > p_t0 THEN 'planned'
              ELSE 'active' END,
         least(tt.st, p_t0::timestamptz)
  FROM (SELECT g,
               random() AS r_st, random() AS r_dur,
               random() AS r_m1, random() AS r_m2, random() AS r_dv
        FROM generate_series(1, 60) g) b
  CROSS JOIN LATERAL (
    SELECT v_hist_start + (b.r_st * 1225) * interval '1 day' AS st) tt
  CROSS JOIN LATERAL (
    SELECT CASE WHEN b.r_m1 < 0.6 THEN 'percent'
                WHEN b.r_m2 < 0.5 THEN 'fixed' ELSE 'bundle' END AS mechanics) mec;

  -- ============================ заказы по 30-дневным окнам ==================
  v_start := v_hist_start;
  WHILE v_start <= p_t0 LOOP
    v_end := LEAST(v_start + 29, p_t0);
    RAISE NOTICE '[seed] window %..% %', v_start, v_end, clock_timestamp();
    SELECT COALESCE(max(order_id), 0) INTO v_prev_max FROM erp.orders;

    -- стадии: день×объём → каналы/часы → таймстемп → жизненный цикл → вставка
    WITH days AS (
      SELECT d::date AS d,
             round(350 * (CASE EXTRACT(dow FROM d) WHEN 0 THEN 1.25 WHEN 6 THEN 1.3
                                                   WHEN 5 THEN 1.15 ELSE 1.0 END)
                   * (0.80 + 0.40 * ((d::date - v_hist_start)::numeric / 1155.0)))::int AS n
      FROM generate_series(v_start, v_end, interval '1 day') d
    ),
    raw AS (
      SELECT c.d, random() AS ch_r, random() AS hour_r, random() AS r3, random() AS r4
      FROM days c CROSS JOIN LATERAL generate_series(1, c.n) g(i)
    ),
    ch AS (
      SELECT r.*,
             CASE WHEN r.ch_r < 0.60 - 0.05 * ((r.d - v_hist_start)::numeric / 1155.0) THEN 'shop'
                  WHEN r.ch_r < 0.85 THEN 'web' ELSE 'app' END AS channel,
             CASE WHEN r.hour_r < 0.15 THEN 8 + floor(random()*4)::int
                  WHEN r.hour_r < 0.45 THEN 12 + floor(random()*6)::int
                  WHEN r.hour_r < 0.90 THEN 18 + floor(random()*4)::int
                  ELSE 22 + floor(random()*2)::int END AS hour
      FROM raw r
    ),
    ts AS (
      SELECT c.*, (c.d + make_interval(hours => c.hour, mins => floor(random()*60)::int,
                                                  secs => floor(random()*60)::int)) AS order_ts
      FROM ch c
    ),
    lc1 AS (  -- paid_at / cancelled_at
      SELECT t.*,
             CASE WHEN t.d > p_t0 - 3 AND t.hour < 18 AND t.r3 < 0.4
                    THEN t.order_ts + make_interval(mins => 3 + floor(random()*40)::int)
                  WHEN t.d <= p_t0 - 3 AND t.r3 >= 0.03
                    THEN t.order_ts + make_interval(mins => 3 + floor(random()*60)::int) END AS paid_at,
             CASE WHEN t.d <= p_t0 - 3 AND t.r3 < 0.03
                    THEN t.order_ts + make_interval(hours => 1 + floor(random()*20)::int)
                  WHEN t.d <= p_t0 - 3 AND t.r3 >= 0.03 AND t.r4 < 0.005
                    THEN t.order_ts + make_interval(hours => 2 + floor(random()*30)::int) END AS cancelled_at
      FROM ts t
    ),
    lc2 AS (  -- shipped_at
      SELECT l.*,
             CASE WHEN l.paid_at IS NOT NULL AND l.cancelled_at IS NULL
                    THEN l.paid_at + make_interval(hours => 2 + floor(random()*28)::int) END AS shipped_at
      FROM lc1 l
    ),
    lc3 AS (  -- delivered_at: история доставляется, последние 3 дня — в полёте
      SELECT l.*,
             CASE WHEN l.shipped_at IS NOT NULL AND l.d <= p_t0 - 3
                    THEN l.shipped_at + make_interval(hours => 6 + floor(random()*66)::int) END AS delivered_at
      FROM lc2 l
    )
    INSERT INTO erp.orders (order_id, order_no, customer_id, store_id, channel, status,
                            order_ts, paid_at, shipped_at, delivered_at, cancelled_at, total_amount, updated_at)
    SELECT nextval('meta.seq_order'),
           'ORD-' || lpad(nextval('meta.seq_order_no')::text, 7, '0'),
           1 + floor(random() * 50000)::int,
           CASE WHEN c.channel = 'shop' THEN 1 + floor(random() * 14)::int ELSE 15 END,
           c.channel,
           CASE WHEN c.cancelled_at IS NOT NULL THEN 'cancelled'
                WHEN c.paid_at IS NULL THEN 'created'
                WHEN c.shipped_at IS NULL THEN 'paid'
                WHEN c.delivered_at IS NULL THEN 'shipped'
                ELSE 'delivered' END,
           c.order_ts, c.paid_at, c.shipped_at, c.delivered_at, c.cancelled_at, 0,
           greatest(c.order_ts, COALESCE(c.paid_at, c.order_ts), COALESCE(c.shipped_at, c.order_ts),
                    COALESCE(c.delivered_at, c.order_ts), COALESCE(c.cancelled_at, c.order_ts))
    FROM lc3 c;

    SELECT max(order_id), v_prev_max + 1 INTO v_last, v_first FROM erp.orders;

    -- строки заказов: продукт из ассортимента магазина; средняя корзина ~2.9 строки
    -- ВАЖНО (багфикк M0): random() в JOIN-условии VOLATILE — перерисовывается на
    -- каждую строку сравнения и теряет ~37% строк (P(мимо) = 1/e). Индекс
    -- ассортимента рисуется РОВНО ОДИН раз в собственном lateral, дальше —
    -- детерминированный join по rn.
    INSERT INTO erp.order_lines (order_line_id, order_id, product_id, qty, unit_price, discount_pct, line_amount, updated_at)
    SELECT nextval('meta.seq_line'),
           o.order_id, a.product_id, q.qty,
           round(pr.list_price * q.price_f)::bigint,
           q.disc,
           round(q.qty * round(pr.list_price * q.price_f)::bigint * (100 - q.disc) / 100.0)::bigint,
           o.order_ts
    FROM erp.orders o
    CROSS JOIN LATERAL (                    -- сколько строк у заказа (1 розыгрыш)
      SELECT CASE WHEN q1.r < 0.20 THEN 1 WHEN q1.r < 0.45 THEN 2
                  WHEN q1.r < 0.72 THEN 3 ELSE 4 + floor(random()*3)::int END AS n_lines
      FROM (SELECT random() AS r) q1
    ) nl
    CROSS JOIN LATERAL generate_series(1, nl.n_lines) g(i)
    CROSS JOIN LATERAL (                    -- параметры строки (qty/скидка/цена)
      SELECT CASE WHEN q2.r < 0.28 THEN 1 WHEN q2.r < 0.58 THEN 2
                  WHEN q2.r < 0.80 THEN 3 ELSE 4 + floor(random()*3)::int END AS qty,
             CASE WHEN random() < 0.70 THEN 0::numeric
                  ELSE (5 * (1 + floor(random()*4)::int))::numeric END AS disc,
             0.9 + random() * 0.2 AS price_f
      FROM (SELECT random() AS r) q2
    ) q
    CROSS JOIN LATERAL (                    -- индекс ассортимента: 1 розыгрыш
      SELECT 1 + floor(c.cnt * random())::int AS pick_rn
      FROM meta.assortment_cnt c
      WHERE c.store_id = o.store_id
    ) p
    CROSS JOIN LATERAL (                    -- детерминированный выбор продукта
      SELECT a.product_id
      FROM meta.assortment a
      WHERE a.store_id = o.store_id AND a.rn = p.pick_rn
      LIMIT 1
    ) a
    JOIN erp.products pr ON pr.product_id = a.product_id
    WHERE o.order_id BETWEEN v_first AND v_last;

    -- итог заказа = сумма строк (инвариант)
    UPDATE erp.orders o SET total_amount = s.amt
    FROM (SELECT order_id, sum(line_amount) amt FROM erp.order_lines
          WHERE order_id BETWEEN v_first AND v_last GROUP BY 1) s
    WHERE o.order_id = s.order_id AND o.total_amount <> s.amt;

    -- платежи: сплиты детерминированы по order_id % 100 < 7 (≈7%)
    INSERT INTO erp.payments (payment_id, order_id, paid_ts, method, amount, status, updated_at)
    SELECT nextval('meta.seq_payment'), o.order_id, o.paid_at,
           CASE WHEN o.channel = 'shop' THEN (CASE WHEN random() < 0.7 THEN 'card' ELSE 'cash' END)
                ELSE 'online' END,
           o.total_amount, 'captured', o.paid_at
    FROM erp.orders o
    WHERE o.order_id BETWEEN v_first AND v_last AND o.paid_at IS NOT NULL
      AND (o.order_id % 100) >= 7;

    INSERT INTO erp.payments (payment_id, order_id, paid_ts, method, amount, status, updated_at)
    SELECT nextval('meta.seq_payment'), o.order_id, o.paid_at, 'card',
           round(o.total_amount * 0.6)::bigint, 'captured', o.paid_at
    FROM erp.orders o
    WHERE o.order_id BETWEEN v_first AND v_last AND o.paid_at IS NOT NULL
      AND (o.order_id % 100) < 7;

    INSERT INTO erp.payments (payment_id, order_id, paid_ts, method, amount, status, updated_at)
    SELECT nextval('meta.seq_payment'), o.order_id, o.paid_at, 'gift',
           o.total_amount - round(o.total_amount * 0.6)::bigint, 'captured', o.paid_at
    FROM erp.orders o
    WHERE o.order_id BETWEEN v_first AND v_last AND o.paid_at IS NOT NULL
      AND (o.order_id % 100) < 7;

    -- refund'ы отменённых после оплаты
    UPDATE erp.payments p SET status = 'refunded', refunded_at = o.cancelled_at, updated_at = o.cancelled_at
    FROM erp.orders o
    WHERE o.order_id = p.order_id AND o.order_id BETWEEN v_first AND v_last
      AND o.status = 'cancelled' AND o.cancelled_at IS NOT NULL AND o.paid_at IS NOT NULL;

    -- возвраты: ~4% строк доставленных заказов; qty ≤ qty строки; refund пропорционален
    INSERT INTO erp.returns (return_id, order_line_id, return_ts, qty, reason, refund_amount)
    SELECT nextval('meta.seq_return'), l.order_line_id,
           LEAST(v_t0_eod, o.delivered_at + (24 * (1 + random()*25)) * interval '1 hour'),
           rq.rqty,
           (ARRAY['defect','wrong_item','changed_mind','damaged_delivery','late_delivery'])[1 + floor(random()*5)::int],
           round(l.line_amount * rq.rqty / l.qty)::bigint
    FROM erp.order_lines l
    JOIN erp.orders o ON o.order_id = l.order_id
    CROSS JOIN LATERAL (SELECT LEAST(l.qty, 1 + (random() < 0.35)::int) AS rqty) rq
    WHERE o.order_id BETWEEN v_first AND v_last
      AND o.delivered_at IS NOT NULL AND o.delivered_at < v_t0_eod - interval '3 day'
      AND random() < 0.04;

    -- часть заказов с возвратами получает статус returned
    UPDATE erp.orders o SET status = 'returned',
           updated_at = greatest(o.updated_at, r.last_ret)
    FROM (SELECT l.order_id, max(r.return_ts) AS last_ret
          FROM erp.returns r
          JOIN erp.order_lines l ON l.order_line_id = r.order_line_id
          WHERE l.order_id BETWEEN v_first AND v_last
          GROUP BY 1) r
    WHERE o.order_id = r.order_id AND random() < 0.5;

    -- снапшоты инвентаря: ~30 дней × 14 магазинов × ассортимент (~0.85M строк/окно)
    INSERT INTO erp.inventory (snap_date, store_id, product_id, qty_on_hand, qty_reserved)
    SELECT d::date, a.store_id, a.product_id,
           CASE WHEN random() < 0.03 THEN 0 ELSE 20 + floor(random()*180)::int END,
           floor(random()*9)::int
    FROM generate_series(v_start, v_end, interval '1 day') d
    JOIN meta.assortment a ON true
    JOIN erp.stores s ON s.store_id = a.store_id
         AND s.opened_at <= d::date AND (s.closed_at IS NULL OR s.closed_at >= d::date)
    JOIN erp.products p ON p.product_id = a.product_id
         AND p.is_active AND p.launched_at <= d::date;

    v_start := v_end + 1;
  END LOOP;
  RAISE NOTICE '[seed] windows done %', clock_timestamp();

  -- ------------------------------------------- CRM: участия (95% до T0) + орфаны
  INSERT INTO crm.promo_participation (id, promo_id, order_no, attached_at, sync_ts)
  SELECT nextval('meta.seq_participation'), pr.promo_id, o.order_no,
         o.order_ts + interval '1 hour',
         o.order_ts + interval '1 hour' + (random() * 2) * interval '1 day'
  FROM crm.promotions pr
  JOIN erp.orders o ON o.order_ts::date BETWEEN pr.starts_at AND pr.ends_at
                    AND o.status <> 'cancelled'
                    AND (o.order_id % 100) < 15                    -- ~15% заказов
  WHERE o.order_ts < v_t0_eod - interval '4 day';

  -- ~1% орфанных ссылок: номера вне реального диапазона (ORD-9xxxxxx)
  INSERT INTO crm.promo_participation (id, promo_id, order_no, attached_at, sync_ts)
  SELECT nextval('meta.seq_participation'),
         (SELECT promo_id FROM crm.promotions ORDER BY random() LIMIT 1),
         'ORD-9' || lpad((100000 + floor(random()*899999))::int::text, 6, '0'),
         v_t0_eod - (random() * 30) * interval '1 day',
         v_t0_eod - (random() * 28) * interval '1 day'
  FROM generate_series(1, 650);

  RAISE NOTICE '[seed] crm + orphans done %', clock_timestamp();

  -- журнал: T0 помечаем «прожитым» (симуляция живёт начиная с T0+1)
  INSERT INTO meta.simulated_days (sim_date, stats)
  VALUES (p_t0, jsonb_build_object('seed', true));
END $$;

-- ----------------------------------------------------------------------------
-- simulate_day(): один день жизни обеих систем (план §2.5, сценарная сетка)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION meta.simulate_day(p_date date)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  v_t0 date := (SELECT v::date FROM meta.config WHERE k = 't0');
  v_day_start timestamptz := p_date::timestamp;
  v_ts timestamptz := p_date::timestamp + interval '9 hour';  -- «рабочее» время изменений
  v_n int; v_i int; v_ord bigint; v_line bigint;
  v_first bigint; v_last bigint; v_prev_max bigint;
  v_stats jsonb := '{}'::jsonb;
  v_next_day date;
BEGIN
  -- Один писатель генератора; журнал и изменения дня фиксируются одной транзакцией.
  PERFORM pg_advisory_xact_lock(87206310);
  IF v_t0 IS NULL THEN
    RAISE EXCEPTION 'сначала выполните meta.seed_history()';
  END IF;
  IF EXISTS (SELECT 1 FROM meta.simulated_days WHERE sim_date = p_date) THEN
    RAISE EXCEPTION 'день % уже прожит; перезалив дня — операция DWH, не генератора (§2.5)', p_date;
  END IF;

  SELECT max(sim_date) + 1 INTO v_next_day FROM meta.simulated_days;
  IF p_date IS DISTINCT FROM v_next_day THEN
    RAISE EXCEPTION 'ожидался следующий день %, получен %', v_next_day, p_date;
  END IF;

  PERFORM setseed(meta.day_seed(p_date));

  -- =============================== 1. Переходы статусов (бампают updated_at)
  UPDATE erp.orders SET status = 'delivered', updated_at = v_ts, delivered_at = v_day_start + (10 + random()*8) * interval '1 hour'
  WHERE status = 'shipped' AND shipped_at < v_day_start - interval '20 hour' AND random() < 0.8;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_stats := v_stats || jsonb_build_object('delivered', v_n);

  UPDATE erp.orders SET status = 'shipped', updated_at = v_ts, shipped_at = v_day_start + (9 + random()*6) * interval '1 hour'
  WHERE status = 'paid' AND paid_at < v_day_start - interval '10 hour' AND random() < 0.85;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_stats := v_stats || jsonb_build_object('shipped', v_n);

  UPDATE erp.orders SET status = 'paid', updated_at = v_ts, paid_at = v_day_start + (9 + random()*9) * interval '1 hour'
  WHERE status = 'created' AND order_ts < v_day_start - interval '6 hour' AND random() < 0.9;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_stats := v_stats || jsonb_build_object('paid', v_n);

  UPDATE erp.orders SET status = 'cancelled', updated_at = v_ts, cancelled_at = v_day_start + (9 + random()*9) * interval '1 hour'
  WHERE status = 'created' AND order_ts < v_day_start - interval '6 hour' AND random() < 0.05;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_stats := v_stats || jsonb_build_object('cancelled', v_n);

  -- L52: доступно только ещё не возвращённое количество строки.
  INSERT INTO erp.returns (return_id, order_line_id, return_ts, qty, reason, refund_amount)
  SELECT nextval('meta.seq_return'), l.order_line_id,
         v_ts + random() * interval '8 hour',
         rq.rqty,
         (ARRAY['defect','wrong_item','changed_mind','damaged_delivery','late_delivery'])[1 + floor(random()*5)::int],
         round(l.line_amount * rq.rqty / l.qty)::bigint
  FROM erp.order_lines l
  JOIN erp.orders o ON o.order_id = l.order_id
  LEFT JOIN (SELECT order_line_id, sum(qty) AS returned_qty
             FROM erp.returns GROUP BY order_line_id) previous
    ON previous.order_line_id = l.order_line_id
  CROSS JOIN LATERAL (
    SELECT LEAST(l.qty - COALESCE(previous.returned_qty, 0), 1 + (random() < 0.35)::int) AS rqty
  ) rq
  WHERE o.status = 'delivered' AND o.delivered_at >= v_day_start - interval '12 day'
    AND o.delivered_at < v_day_start AND rq.rqty > 0 AND random() < 0.04;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_stats := v_stats || jsonb_build_object('returns_new', v_n);

  UPDATE erp.orders o SET status = 'returned', updated_at = v_ts
  WHERE o.status = 'delivered'
    AND EXISTS (SELECT 1 FROM erp.returns r JOIN erp.order_lines l USING (order_line_id)
                WHERE l.order_id = o.order_id AND r.return_ts::date = p_date)
    AND random() < 0.6;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_stats := v_stats || jsonb_build_object('returned', v_n);

  -- refund платежей отменённых/вернувшихся сегодня
  UPDATE erp.payments p SET status = 'refunded', refunded_at = v_ts, updated_at = v_ts
  FROM erp.orders o
  WHERE o.order_id = p.order_id AND o.status IN ('returned','cancelled')
    AND ((o.status = 'cancelled' AND o.cancelled_at::date = p_date)
         OR (o.status = 'returned' AND o.updated_at::date = p_date))
    AND p.status = 'captured';

  -- =============================== 2. Новые заказы (350±сезон + 2 late-arriving)
  SELECT COALESCE(max(order_id), 0) INTO v_prev_max FROM erp.orders;

  WITH n AS (
    SELECT round(350 * CASE EXTRACT(dow FROM p_date) WHEN 0 THEN 1.25 WHEN 6 THEN 1.3
                                                     WHEN 5 THEN 1.15 ELSE 1.0 END)::int AS cnt
  ),
  raw AS (
    SELECT p_date::timestamp AS d, random() AS ch_r, random() AS hour_r, random() AS pay_r
    FROM (SELECT 1 FROM generate_series(1, (SELECT cnt - 4 FROM n))) a
    UNION ALL
    SELECT p_date::timestamp, random(), random(), random() FROM generate_series(1, 2)
    UNION ALL
    SELECT (p_date - 1)::timestamp, random(), random(), random() FROM generate_series(1, 2)
  ),
  calc AS (
    SELECT r.*,
           CASE WHEN r.ch_r < 0.55 THEN 'shop' WHEN r.ch_r < 0.80 THEN 'web' ELSE 'app' END AS channel,
           CASE WHEN r.hour_r < 0.15 THEN 8 + floor(random()*4)::int
                WHEN r.hour_r < 0.45 THEN 12 + floor(random()*6)::int
                WHEN r.hour_r < 0.90 THEN 18 + floor(random()*4)::int
                ELSE 22 + floor(random()*2)::int END AS hour
    FROM raw r
  ),
  stamped AS MATERIALIZED (
    -- Время заказа разыгрывается один раз; оплата относится к этому же событию.
    SELECT c.*, c.d + make_interval(hours => c.hour, mins => floor(random()*60)::int) AS created_ts
    FROM calc c
  )
  INSERT INTO erp.orders (order_id, order_no, customer_id, store_id, channel, status,
                          order_ts, paid_at, total_amount, updated_at)
  SELECT nextval('meta.seq_order'),
         'ORD-' || lpad(nextval('meta.seq_order_no')::text, 7, '0'),
         1 + floor(random() * 50000)::int,
         CASE WHEN c.channel = 'shop' THEN 1 + floor(random() * 14)::int ELSE 15 END,
         c.channel,
         CASE WHEN c.hour < 18 AND c.pay_r < 0.4 THEN 'paid' ELSE 'created' END,
         c.created_ts,
         CASE WHEN c.hour < 18 AND c.pay_r < 0.4
              THEN c.created_ts + interval '5 minute' END,
         0,
         c.created_ts
  FROM stamped c;

  SELECT max(order_id), v_prev_max + 1 INTO v_last, v_first FROM erp.orders;
  v_stats := v_stats || jsonb_build_object('new_orders', v_last - v_first + 1, 'late_arriving', 2);

  INSERT INTO erp.order_lines (order_line_id, order_id, product_id, qty, unit_price, discount_pct, line_amount, updated_at)
  SELECT nextval('meta.seq_line'),
         o.order_id, a.product_id, q.qty,
         round(pr.list_price * q.price_f)::bigint,
         q.disc,
         round(q.qty * round(pr.list_price * q.price_f)::bigint * (100 - q.disc) / 100.0)::bigint,
         o.order_ts
  FROM erp.orders o
  CROSS JOIN LATERAL (                    -- сколько строк у заказа (багфикк M0)
    SELECT CASE WHEN q1.r < 0.20 THEN 1 WHEN q1.r < 0.45 THEN 2
                WHEN q1.r < 0.72 THEN 3 ELSE 4 + floor(random()*3)::int END AS n_lines
    FROM (SELECT random() AS r) q1
  ) nl
  CROSS JOIN LATERAL generate_series(1, nl.n_lines) g(i)
  CROSS JOIN LATERAL (
    SELECT CASE WHEN q2.r < 0.28 THEN 1 WHEN q2.r < 0.58 THEN 2
                WHEN q2.r < 0.80 THEN 3 ELSE 4 + floor(random()*3)::int END AS qty,
           CASE WHEN random() < 0.70 THEN 0::numeric
                ELSE (5 * (1 + floor(random()*4)::int))::numeric END AS disc,
           0.9 + random() * 0.2 AS price_f
    FROM (SELECT random() AS r) q2
  ) q
  CROSS JOIN LATERAL (                    -- индекс ассортимента: 1 розыгрыш
    SELECT 1 + floor(c.cnt * random())::int AS pick_rn
    FROM meta.assortment_cnt c
    WHERE c.store_id = o.store_id
  ) p
  CROSS JOIN LATERAL (                    -- детерминированный выбор по rn
    SELECT a.product_id
    FROM meta.assortment a
    WHERE a.store_id = o.store_id AND a.rn = p.pick_rn
    LIMIT 1
  ) a
  JOIN erp.products pr ON pr.product_id = a.product_id
  WHERE o.order_id BETWEEN v_first AND v_last;

  UPDATE erp.orders o SET total_amount = s.amt
  FROM (SELECT order_id, sum(line_amount) amt FROM erp.order_lines
        WHERE order_id BETWEEN v_first AND v_last GROUP BY 1) s
  WHERE o.order_id = s.order_id;

  INSERT INTO erp.payments (payment_id, order_id, paid_ts, method, amount, status, updated_at)
  SELECT nextval('meta.seq_payment'), o.order_id, o.paid_at,
         CASE WHEN o.channel = 'shop' THEN (CASE WHEN random() < 0.7 THEN 'card' ELSE 'cash' END)
              ELSE 'online' END,
         o.total_amount, 'captured', o.paid_at
  FROM erp.orders o
  WHERE o.order_id BETWEEN v_first AND v_last AND o.paid_at IS NOT NULL AND (o.order_id % 100) >= 7;
  INSERT INTO erp.payments (payment_id, order_id, paid_ts, method, amount, status, updated_at)
  SELECT nextval('meta.seq_payment'), o.order_id, o.paid_at, 'card',
         round(o.total_amount * 0.6)::bigint, 'captured', o.paid_at
  FROM erp.orders o
  WHERE o.order_id BETWEEN v_first AND v_last AND o.paid_at IS NOT NULL AND (o.order_id % 100) < 7;
  INSERT INTO erp.payments (payment_id, order_id, paid_ts, method, amount, status, updated_at)
  SELECT nextval('meta.seq_payment'), o.order_id, o.paid_at, 'gift',
         o.total_amount - round(o.total_amount * 0.6)::bigint, 'captured', o.paid_at
  FROM erp.orders o
  WHERE o.order_id BETWEEN v_first AND v_last AND o.paid_at IS NOT NULL AND (o.order_id % 100) < 7;

  -- =============================== 3. Ретро-правки сумм (~3/день, паттерн №3)
  v_i := 0;
  FOR v_i IN 1..3 LOOP
    SELECT order_id INTO v_ord FROM erp.orders
    WHERE status IN ('paid','shipped') AND order_ts > p_date - 30
    ORDER BY random() LIMIT 1;
    CONTINUE WHEN v_ord IS NULL;
    SELECT order_line_id INTO v_line FROM erp.order_lines WHERE order_id = v_ord
    ORDER BY random() LIMIT 1;
    CONTINUE WHEN v_line IS NULL;
    UPDATE erp.order_lines l
    SET discount_pct = s.nd,
        line_amount = round(l.qty * l.unit_price * (100 - s.nd) / 100.0)::bigint,
        updated_at = v_ts
    FROM (SELECT LEAST(30::numeric, discount_pct + 5) nd FROM erp.order_lines
          WHERE order_line_id = v_line) s
    WHERE l.order_line_id = v_line;
    UPDATE erp.orders o SET total_amount = (SELECT sum(line_amount) FROM erp.order_lines
                                            WHERE order_id = v_ord),
                            updated_at = v_ts
    WHERE o.order_id = v_ord;
  END LOOP;
  v_stats := v_stats || jsonb_build_object('amount_fixes', 3);

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

  -- =============================== 5. События магазинов (№6)
  IF p_date = v_t0 + 15 THEN
    INSERT INTO erp.stores (store_id, name, format, city, region, opened_at, updated_at)
    VALUES (16, 'Москва-Восток', 'mall', 'Москва', 'Центр', p_date, v_ts);
    INSERT INTO meta.assortment (store_id, product_id)
    SELECT 16, product_id FROM erp.products WHERE is_active AND random() < 0.6;
    PERFORM meta.renumber_assortment(16);
  END IF;
  IF p_date = v_t0 + 45 THEN
    UPDATE erp.stores SET closed_at = p_date, updated_at = v_ts WHERE store_id = 13;
  END IF;

  -- =============================== 6. Снапшот инвентаря дня
  INSERT INTO erp.inventory (snap_date, store_id, product_id, qty_on_hand, qty_reserved)
  SELECT p_date, a.store_id, a.product_id,
         CASE WHEN random() < 0.03 THEN 0 ELSE 20 + floor(random()*180)::int END,
         floor(random()*9)::int
  FROM meta.assortment a
  JOIN erp.stores s ON s.store_id = a.store_id
       AND s.opened_at <= p_date AND (s.closed_at IS NULL OR s.closed_at >= p_date)
  JOIN erp.products p ON p.product_id = a.product_id AND p.is_active AND p.launched_at <= p_date;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_stats := v_stats || jsonb_build_object('inventory_rows', v_n);

  -- =============================== 7. CRM (№3 из другого источника + №10)
  -- участия: заказы последних 5 дней под акциями приезжают сегодня (sync_ts = день)
  INSERT INTO crm.promo_participation (id, promo_id, order_no, attached_at, sync_ts)
  SELECT nextval('meta.seq_participation'), pr.promo_id,
         CASE WHEN random() < 0.01
              THEN 'ORD-9' || lpad((100000 + floor(random()*899999))::int::text, 6, '0')
              ELSE o.order_no END,
         o.order_ts + interval '1 hour',
         v_ts + random() * interval '6 hour'
  FROM erp.orders o
  JOIN crm.promotions pr ON o.order_ts::date BETWEEN pr.starts_at AND pr.ends_at
  WHERE o.order_ts >= v_day_start - interval '5 day' AND o.order_ts < v_day_start
    AND o.status <> 'cancelled' AND (o.order_id % 100) < 15
    AND NOT EXISTS (SELECT 1 FROM crm.promo_participation pp WHERE pp.order_no = o.order_no);
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_stats := v_stats || jsonb_build_object('crm_participation', v_n);

  -- жизненный цикл акций: пересчёт статуса по датам (бампает updated_at при смене)
  UPDATE crm.promotions p SET
    status = CASE WHEN p_date > p.ends_at THEN 'closed'
                  WHEN p_date >= p.starts_at THEN 'active' ELSE 'planned' END,
    updated_at = v_ts
  WHERE p.status <> CASE WHEN p_date > p.ends_at THEN 'closed'
                         WHEN p_date >= p.starts_at THEN 'active' ELSE 'planned' END;

  -- редкие ретро-коррекции: продление (T0+20) и досрочная остановка (T0+35)
  IF p_date = v_t0 + 20 THEN
    UPDATE crm.promotions SET ends_at = ends_at + 14, updated_at = v_ts
    WHERE promo_id = (SELECT promo_id FROM crm.promotions WHERE status = 'active'
                      ORDER BY random() LIMIT 1);
  END IF;
  IF p_date = v_t0 + 35 THEN
    UPDATE crm.promotions SET ends_at = p_date, status = 'closed', updated_at = v_ts
    WHERE promo_id = (SELECT promo_id FROM crm.promotions WHERE status = 'active'
                      AND ends_at > p_date ORDER BY random() LIMIT 1);
  END IF;

  -- События внутри виртуального дня не должны оказаться позже watermark.
  UPDATE erp.orders SET updated_at = greatest(updated_at, order_ts, paid_at, shipped_at, delivered_at, cancelled_at)
  WHERE updated_at < greatest(order_ts, paid_at, shipped_at, delivered_at, cancelled_at);

  INSERT INTO meta.simulated_days (sim_date, stats) VALUES (p_date, v_stats);
  RETURN v_stats;
END $$;

-- ----------------------------------------------------------------------------
-- reset_sources(): очистка данных для пересборки (dev)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION meta.reset_sources()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  TRUNCATE erp.inventory, erp.returns, erp.payments, erp.order_lines, erp.orders,
           erp.customers, erp.products, erp.categories, erp.stores,
           crm.promo_participation, crm.promotions,
           meta.simulated_days, meta.assortment, meta.assortment_cnt, meta.config;
  PERFORM setval('meta.seq_order',1,false), setval('meta.seq_order_no',1,false),
           setval('meta.seq_line',1,false), setval('meta.seq_payment',1,false),
           setval('meta.seq_return',1,false), setval('meta.seq_participation',1,false);
END $$;
