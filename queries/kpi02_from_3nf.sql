-- ============================================================================
-- KPI №2 из 3NF-ядра (L4.1): топ-10 товаров по выручке за квартал
-- с иерархией категорий. ГЛАВНЫЙ «болевой» артефект главы 6: ВОСЕМЬ join'ов —
-- цена нормализованного ядра для аналитика (в звезде с flatten — один join).
-- Семантика выручки — как в kpi01_from_3nf.sql (is_current, paid+).
-- ============================================================================

SET CATALOG iceberg;
USE inmon_core;

with revenue as (
    select
        l.product_id,
        sum(l.line_amount) as revenue_amt
    from int_orders o
    join int_order_states os on os.order_id = o.order_id and os.is_current
    join int_order_lines l   on l.order_id = o.order_id and l.is_current
    where os.status in ('paid', 'shipped', 'delivered', 'returned')
      and cast(o.order_ts as date) >= date '2026-01-01'   -- параметр квартала
      and cast(o.order_ts as date) <  date '2026-04-01'
    group by 1
)
select
    p.sku,
    p.brand,
    c1.name as category_l3,
    c2.name as category_l2,
    c3.name as category_l1,
    r.revenue_amt
from revenue r
join int_products p
    on p.product_id = r.product_id
join int_product_categories pc                       -- текущая категория (№5)
    on pc.product_id = p.product_id and pc.is_current
join int_categories c1 on c1.category_id = pc.category_id
left join int_categories c2 on c2.category_id = c1.parent_category_id
left join int_categories c3 on c3.category_id = c2.parent_category_id
order by r.revenue_amt desc
limit 10;
