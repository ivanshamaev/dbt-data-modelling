-- L4.3 · ограниченный тест «заведомо плохих данных» (§4 плана):
-- ~1% CRM-участий орфанны по order_no ПО ПОСТРОЕНИЮ — жёсткий
-- relationships-тест делал бы канонический `dbt build` перманентно красным.
-- Правило: доля орфанов ≤ 1,5% (жёсткий fail — только регрессия,
-- которой в данных быть не должно).
with total as (
    select count(*) as n
    from {{ ref('stg_in_crm__promo_participation') }}
),
orphans as (
    select count(*) as o
    from {{ ref('stg_in_crm__promo_participation') }} p
    left join {{ ref('stg_in_erp__orders') }} e
        on e.order_no = p.order_no
    where e.order_id is null
)
select
    o.o / nullif(t.n, 0) as orphan_share,
    o.o                  as orphan_cnt,
    t.n                  as total_cnt
from orphans o cross join total t
having o.o / nullif(t.n, 0) > 0.015
