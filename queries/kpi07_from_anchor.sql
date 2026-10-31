-- ============================================================================
-- KPI №7 ИЗ ANCHOR (L5.4): LTV по сегментам, сегмент НА КОНЕЦ ДНЯ ЗАКАЗА —
-- VALID-TIME механика (третий способ после SCD2-join звезды и PIT из vault'а).
-- As-of join прямо к historized-атрибуту: valid_from <= дата заказа < valid_to.
-- Три SQL бок-о-бок (звезда/vault/anchor) — главный артефакт гл. 14.
-- ============================================================================

SET CATALOG iceberg;
USE anchor_core;

select
    seg.segment,
    count(distinct wv_o.order_id) as orders_cnt,
    sum(wv_l.line_amount)         as ltv_amt
from wv_order_line wv_l
inner join wv_order wv_o
    on wv_o.order_id = wv_l.order_id
inner join t_customer_order tco
    on tco.order_id = wv_o.order_id
inner join (
    -- historized-атрибут с восстановленным valid-интервалом (knot → значение)
    select
        c.customer_id,
        k.value        as segment,
        c.valid_from,
        lead(c.valid_from) over (partition by c.customer_id
                                 order by c.valid_from) as valid_to
    from ac_customer_segment c
    inner join kn_segment k on k.knot_id = c.value  -- L37: value(BIGINT knot-ссылка), не несуществующий knot_id
    where c.superseded_time is null
) seg
    on seg.customer_id = tco.customer_id
   and seg.valid_from <= cast(wv_o.order_ts as date)
   and (seg.valid_to is null or seg.valid_to > cast(wv_o.order_ts as date))
where wv_o.status in ('paid', 'shipped', 'delivered', 'returned')
group by 1
order by ltv_amt desc;
