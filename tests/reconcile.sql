-- ============================================================================
-- tests/reconcile.sql · Reconciliation ядер (план §1.4, DoD §10)
-- Запуск: make reconcile   (после make build)
--
-- Правило: цифры витрин, собранных разными методологиями, ОБЯЗАНЫ сходиться
-- до копейки на контрольной дате. Расхождение — баг, который находится
-- и разбирается (типовые источники: гранулярность, окно дат, состав статусов,
-- потерянные версии). Раскомментированные блоки добавляются по мере готовности
-- ядер: vault — M3 (L5.3), anchor — M3 (L5.4).
--
-- Сверяются текущие результаты по всей доступной истории на одном состоянии источников.
-- ============================================================================

SET CATALOG default_catalog;
USE analytics;


-- ---------------------------------------------------------------------------
-- R1 · KPI №1 (выручка, вся история): 3NF-ядро ↔ звезда
-- ---------------------------------------------------------------------------
select 'R1_kpi1_total_revenue' as check_name,
       '3nf'                   as core,
       sum(l.line_amount)      as value_amt
from iceberg.inmon_core.int_order_lines l
inner join iceberg.inmon_core.int_orders   o on o.order_id = l.order_id
inner join iceberg.inmon_core.int_order_states os
    on os.order_id = l.order_id and os.is_current
where l.is_current
  and os.status in ('paid', 'shipped', 'delivered', 'returned')

union all

select 'R1_kpi1_total_revenue', 'star', sum(line_amount)
from fact_sales

union all

select 'R1_kpi1_total_revenue', 'vault', sum(revenue_amt)
from iceberg.vault_marts.im_sales_daily

union all

select 'R1_kpi1_total_revenue', 'anchor', sum(revenue_amt)
from iceberg.anchor_marts.agg_anc_sales_daily

-- ---------------------------------------------------------------------------
-- R2 · KPI №7 (LTV по сегментам на момент заказа): 3NF ↔ звезда
-- ---------------------------------------------------------------------------
;

with star_ltv as (
    select c.segment, sum(f.line_amount) as ltv_amt
    from fact_sales f
    inner join dim_customer c on c.customer_sk_v = f.customer_sk_v
    group by 1
),
nf_ltv as (
    select a.segment, sum(l.line_amount) as ltv_amt
    from iceberg.inmon_core.int_order_lines l
    inner join iceberg.inmon_core.int_orders o on o.order_id = l.order_id
    inner join iceberg.inmon_core.int_order_states os
        on os.order_id = l.order_id and os.is_current
    inner join iceberg.inmon_core.int_customer_attributes a
        on a.customer_id = o.customer_id
       and a.valid_from <= cast(o.order_ts as date)
       and (a.valid_to is null or a.valid_to > cast(o.order_ts as date))
    where l.is_current
      and os.status in ('paid', 'shipped', 'delivered', 'returned')
    group by 1
),
-- PIT rolling-180 (§8.11) не покрывает историю: для R2 показываем ВТОРУЮ
-- каноническую механику — прямой as-of join к спутнику (эквивалентен PIT-джойну,
-- kpi07_from_vault.sql; PIT в прод-режиме строится полной сеткой или доливается).
vault_ltv as (
    select s.segment, sum(ol.line_amount) as ltv_amt
    from (select order_hk, order_ts, line_amount from (
              select ol2.order_hk, ol2.order_ts, ol2.line_amount, row_number() over (partition by order_line_hk
                                               order by line_updated_at desc, load_date desc) as rn
              from iceberg.vault_core.l_order_line ol2
          ) x where rn = 1) ol
    inner join iceberg.vault_core.b_order_effective_state oes
        on oes.order_hk = ol.order_hk
    inner join iceberg.vault_core.l_order_customer lc
        on lc.order_hk = ol.order_hk
    inner join (
        -- as-of: версия сегмента, действовавшая НА ДАТУ ЗАКАЗА (не current belief!);
        -- same-day коррекции схлопываем последней по load_ts (L57/L58)
        select customer_hk, segment, effective_from,
               lead(effective_from) over (partition by customer_hk
                                          order by effective_from) as next_from
        from (
            select c.customer_hk, c.segment, c.effective_from, row_number() over (partition by customer_hk, effective_from
                                           order by load_ts desc) as rn
            from iceberg.vault_core.s_customer_erp c
        ) d
        where rn = 1
    ) s
        on s.customer_hk = lc.customer_hk
       and s.effective_from <= cast(ol.order_ts as date)
       and (s.next_from is null or s.next_from > cast(ol.order_ts as date))
    where oes.status in ('paid', 'shipped', 'delivered', 'returned')
    group by 1
),
anchor_ltv as (
    select seg.segment, sum(ol.line_amount) as ltv_amt
    from iceberg.anchor_core.latest_anc_order_line ol
    inner join iceberg.anchor_core.latest_anc_order o
        on o.order_id = ol.order_id
    inner join iceberg.anchor_core.tie_customer_order tco
        on tco.order_id = o.order_id
    inner join (
        select c.customer_id, k.value as segment, c.valid_from,
               lead(c.valid_from) over (partition by c.customer_id
                                        order by c.valid_from) as valid_to
        from iceberg.anchor_core.attr_customer_segment c
        inner join iceberg.anchor_core.knot_segment k on k.knot_id = c.value
        where c.superseded_time is null
    ) seg
        on seg.customer_id = tco.customer_id
       and seg.valid_from <= cast(o.order_ts as date)
       and (seg.valid_to is null or seg.valid_to > cast(o.order_ts as date))
    where o.status in ('paid', 'shipped', 'delivered', 'returned')
    group by 1
)
select
    'R2_kpi7_ltv_by_segment' as check_name,
    segment,
    max(star_ltv)   as star_ltv,
    max(nf_ltv)     as nf_ltv,
    max(vault_ltv)  as vault_ltv,
    max(anchor_ltv) as anchor_ltv,
    coalesce(max(star_ltv), 0) - coalesce(max(anchor_ltv), 0) as diff_star_anchor,
    case
        when coalesce(max(star_ltv), 0) = coalesce(max(nf_ltv), 0)
         and coalesce(max(star_ltv), 0) = coalesce(max(vault_ltv), 0)
         and coalesce(max(star_ltv), 0) = coalesce(max(anchor_ltv), 0)
        then 'OK' else 'FAIL'
    end as status
from (
    select segment, ltv_amt as star_ltv, cast(null as bigint) as nf_ltv, cast(null as bigint) as vault_ltv, cast(null as bigint) as anchor_ltv from star_ltv
    union all
    select segment, cast(null as bigint), ltv_amt, cast(null as bigint), cast(null as bigint) from nf_ltv
    union all
    select segment, cast(null as bigint), cast(null as bigint), ltv_amt, cast(null as bigint) from vault_ltv
    union all
    select segment, cast(null as bigint), cast(null as bigint), cast(null as bigint), ltv_amt from anchor_ltv
) t
group by segment
order by status desc, segment;

-- Ожидание: все строки status = OK — ЧЕТЫРЕ независимых реализации одного смысла
-- (звезда / 3NF / vault / anchor) сходятся до копейки. Это и есть reconciliation.

-- ---------------------------------------------------------------------------
-- R3 · KPI №13 (промо-эффективность): звезда (obt) ↔ vault (im_promo) ↔
-- anchor (tie_order_promo × attr_promo_mechanics) — кросс-источниковая сходимость
-- в трёх ядрах (приёмный тест мультиисточниковости).
-- ---------------------------------------------------------------------------
with star_kpi13 as (
    select
        case when promo_key is not null then 'promo' else 'organic' end as order_type,
        sum(line_amount) as revenue_amt
    from obt_sales
    group by 1
),
vault_kpi13 as (
    select order_type, sum(revenue_amt) as revenue_amt
    from iceberg.vault_marts.im_promo
    group by 1
),
anchor_kpi13 as (
    select
        case when tp.order_id is not null then 'promo' else 'organic' end as order_type,
        sum(ol.line_amount) as revenue_amt
    from iceberg.anchor_core.latest_anc_order_line ol
    inner join iceberg.anchor_core.latest_anc_order o
        on o.order_id = ol.order_id
    left join (
        select distinct order_id from iceberg.anchor_core.tie_order_promo
    ) tp on tp.order_id = o.order_id
    where o.status in ('paid', 'shipped', 'delivered', 'returned')
    group by 1
)
select
    'R3_kpi13_promo_revenue' as check_name,
    order_type,
    max(star_amt)   as star_amt,
    max(vault_amt)  as vault_amt,
    max(anchor_amt) as anchor_amt,
    case
        when coalesce(max(star_amt), 0) = coalesce(max(vault_amt), 0)
         and coalesce(max(star_amt), 0) = coalesce(max(anchor_amt), 0)
        then 'OK' else 'FAIL'
    end as status
from (
    select order_type, revenue_amt as star_amt, cast(null as bigint) as vault_amt, cast(null as bigint) as anchor_amt from star_kpi13
    union all
    select order_type, cast(null as bigint), revenue_amt, cast(null as bigint) from vault_kpi13
    union all
    select order_type, cast(null as bigint), cast(null as bigint), revenue_amt from anchor_kpi13
) t
group by order_type
order by status desc, order_type;

-- L71: distinct-контуров недостаточно: равные дубликаты и NULL в мере
-- скрываются min/max. Требуются ровно пять строк и пять непустых мер.
-- ---------------------------------------------------------------------------
-- R4 · Канонические витрины каталога (docs/design/mart_catalog.md): ПЯТЬ
-- контуров × три витрины обязаны совпадать до копейки. Это приёмный тест
-- требования изоляции: одинаковые витрины, собранные независимыми процессами.
-- ---------------------------------------------------------------------------
;

with sales_daily as (
    select 'inmon' as contour, sales_date, channel, orders_cnt, revenue_amt from iceberg.inmon_marts.dm_sales_daily
    union all
    select 'kimball', sales_date, channel, orders_cnt, revenue_amt from km_sales_daily
    union all
    select 'vault', sales_date, channel, orders_cnt, revenue_amt from iceberg.vault_marts.im_sales_daily
    union all
    select 'anchor', sales_date, channel, orders_cnt, revenue_amt from iceberg.anchor_marts.agg_anc_sales_daily
    union all
    select 'medallion', sales_date, channel, orders_cnt, revenue_amt from iceberg.med_gold.gld_sales_daily
),

ltv as (
    select 'inmon' as contour, segment, customers_cnt, orders_cnt, ltv_amt from iceberg.inmon_marts.dm_customer_ltv
    union all
    select 'kimball', segment, customers_cnt, orders_cnt, ltv_amt from km_customer_ltv
    union all
    select 'vault', segment, customers_cnt, orders_cnt, ltv_amt from iceberg.vault_marts.im_customer_ltv
    union all
    select 'anchor', segment, customers_cnt, orders_cnt, ltv_amt from iceberg.anchor_marts.agg_anc_customer_ltv
    union all
    select 'medallion', segment, customers_cnt, orders_cnt, ltv_amt from iceberg.med_gold.gld_customer_ltv
),

promo as (
    select 'inmon' as contour, order_type, orders_cnt, revenue_amt from iceberg.inmon_marts.dm_promo_effect
    union all
    select 'kimball', order_type, orders_cnt, revenue_amt from km_promo_effect
    union all
    select 'vault', order_type, orders_cnt, revenue_amt from iceberg.vault_marts.im_promo_effect
    union all
    select 'anchor', order_type, orders_cnt, revenue_amt from iceberg.anchor_marts.agg_anc_promo_effect
    union all
    select 'medallion', order_type, orders_cnt, revenue_amt from iceberg.med_gold.gld_promo_effect
)

select
    'R4_sales_daily' as check_name,
    sales_date       as dim1,
    channel          as dim2,
    count(distinct contour)                                    as contours_cnt,
    min(orders_cnt)                                             as orders_cnt_min,
    max(orders_cnt)                                             as orders_cnt_max,
    min(revenue_amt)                                            as revenue_amt_min,
    max(revenue_amt)                                            as revenue_amt_max,
    case
        when min(orders_cnt) = max(orders_cnt)
         and min(revenue_amt) = max(revenue_amt)
         and count(distinct contour) = 5
         and count(*) = 5
         and count(orders_cnt) = 5
         and count(revenue_amt) = 5
        then 'OK' else 'FAIL'
    end as status
from sales_daily
group by 1, 2, 3

union all

select
    'R4_customer_ltv' as check_name,
    segment           as dim1,
    cast(null as varchar) as dim2,
    count(distinct contour) as contours_cnt,
    min(orders_cnt)         as orders_cnt_min,
    max(orders_cnt)         as orders_cnt_max,
    min(ltv_amt)            as revenue_amt_min,
    max(ltv_amt)            as revenue_amt_max,
    case
        when min(orders_cnt) = max(orders_cnt)
         and min(customers_cnt) = max(customers_cnt)
         and min(ltv_amt) = max(ltv_amt)
         and count(distinct contour) = 5
         and count(*) = 5
         and count(orders_cnt) = 5
         and count(customers_cnt) = 5
         and count(ltv_amt) = 5
        then 'OK' else 'FAIL'
    end as status
from ltv
group by 1, 2

union all

select
    'R4_promo_effect' as check_name,
    order_type        as dim1,
    cast(null as varchar) as dim2,
    count(distinct contour) as contours_cnt,
    min(orders_cnt)         as orders_cnt_min,
    max(orders_cnt)         as orders_cnt_max,
    min(revenue_amt)        as revenue_amt_min,
    max(revenue_amt)        as revenue_amt_max,
    case
        when min(orders_cnt) = max(orders_cnt)
         and min(revenue_amt) = max(revenue_amt)
         and count(distinct contour) = 5
         and count(*) = 5
         and count(orders_cnt) = 5
         and count(revenue_amt) = 5
        then 'OK' else 'FAIL'
    end as status
from promo
group by 1, 2
order by status desc, check_name, dim1, dim2;

-- Ожидание: все строки status = OK — ПЯТЬ изолированных контуров дают
-- идентичные канонические витрины. Это главный приёмочный тест архитектуры
-- изолированных контуров (guide/cource-improve, критерий DoD «Эквивалентность»).
