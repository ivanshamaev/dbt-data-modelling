-- ============================================================================
-- KPI №4 ИЗ VAULT: воронка и время переходов — b_order_effective_state свёл
-- последний статус и вехи (BV ради этого и существует: марты не бегают по
-- окнам двух спутников). Один из «пяти ответов» на KPI №4 (гл. 14).
-- Важно: order_ts берётся distinct-подзапросом — иначе fanout по строкам
-- заказа взвесит каждый заказ числом строк (типичная ошибка двойного учёта).
-- ============================================================================

SET CATALOG iceberg;
USE vault_core;

select
    count(distinct b.order_hk)                               as orders_cnt,
    count(b.paid_at)                                         as paid_cnt,
    count(b.shipped_at)                                      as shipped_cnt,
    count(b.delivered_at)                                    as delivered_cnt,
    avg(timestampdiff(SECOND, ot.order_ts, b.paid_at))        / 60.0 as avg_min_create_to_paid,
    avg(timestampdiff(SECOND, b.paid_at, b.shipped_at))      / 60.0 as avg_min_paid_to_shipped,
    avg(timestampdiff(SECOND, b.shipped_at, b.delivered_at)) / 60.0 as avg_min_shipped_to_delivered
from b_order_effective_state b
join (
    select distinct order_hk, order_ts
    from (select * from (
            select ol.*, row_number() over (partition by order_line_hk
                                            order by line_updated_at desc, load_date desc) as rn
            from l_order_line ol
          ) x where rn = 1) dl
) ot on ot.order_hk = b.order_hk;
