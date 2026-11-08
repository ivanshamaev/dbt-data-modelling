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
    count(distinct o.order_id) as orders_cnt,
    sum(ol.line_amount)         as ltv_amt
from latest_anc_order_line ol
inner join latest_anc_order o
    on o.order_id = ol.order_id
inner join tie_customer_order tco
    on tco.order_id = o.order_id
inner join (
    -- historized-атрибут с восстановленным valid-интервалом (knot → значение)
    select
        c.customer_id,
        k.value        as segment,
        c.valid_from,
        lead(c.valid_from) over (partition by c.customer_id
                                 order by c.valid_from) as valid_to
    from attr_customer_segment c
    inner join knot_segment k on k.knot_id = c.value  -- L37: value(BIGINT knot-ссылка), не несуществующий knot_id
    where c.superseded_time is null
) seg
    on seg.customer_id = tco.customer_id
   and seg.valid_from <= cast(o.order_ts as date)
   and (seg.valid_to is null or seg.valid_to > cast(o.order_ts as date))
where o.status in ('paid', 'shipped', 'delivered', 'returned')
group by 1
order by ltv_amt desc;
