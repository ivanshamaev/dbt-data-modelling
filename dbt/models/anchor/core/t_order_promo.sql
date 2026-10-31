{{ config(
    materialized='table',
    schema='iceberg.anchor_core',
    tags=['anchor'],
) }}

-- L5.4 · t_order_promo: КРОСС-ИСТОЧНИКОВЫЙ tie (№10) — заказ (ERP) участвовал
-- в промо (CRM). insert_time = min(sync_ts), время синхронизации CRM,
-- а не первой доставки в bronze. Заказы без совпадения order_no отфильтрованы.
select
    o.order_id,
    pp.promo_id,
    min(pp.sync_ts) as insert_time
from {{ ref('raw_crm__promo_participation') }} pp
inner join (
    select distinct
        order_id,
        order_no
    from {{ ref('raw_erp__orders') }}
) o on pp.order_no = o.order_no
group by 1, 2;
