-- ============================================================================
-- KPI №7 ИЗ 3NF-ЯДРА: LTV по сегментам, сегмент НА МОМЕНТ ЗАКАЗА — valid-time
-- запрос к время-вариантному 3NF (второй из «пяти ответов»; полный набор:
-- звезда kpi_07.sql · 3NF этот файл · vault kpi07_from_vault.sql ·
-- anchor kpi07_from_anchor.sql · OBT — kpi_07 по obt_sales).
-- ============================================================================

SET CATALOG iceberg;
USE inmon_core;

select
    a.segment,
    count(distinct o.order_id) as orders_cnt,
    sum(l.line_amount)         as ltv_amt
from int_orders o
join int_order_states os
    on os.order_id = o.order_id and os.is_current
join int_order_lines l
    on l.order_id = o.order_id and l.is_current
join int_customer_attributes a
    on a.customer_id = o.customer_id
   and a.valid_from <= cast(o.order_ts as date)
   and (a.valid_to is null or a.valid_to > cast(o.order_ts as date))
where os.status in ('paid', 'shipped', 'delivered', 'returned')
group by 1
order by ltv_amt desc;
