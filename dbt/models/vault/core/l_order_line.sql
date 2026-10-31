{{ config(
    materialized='incremental',
    schema='iceberg.vault_core',
    incremental_strategy='default',
    tags=['vault'],
) }}

-- Учебная адаптация позиции заказа: изменяемые меры хранятся прямо на связи.
-- Альтернатива — отделить идентичность/отношение позиции от satellite payload.
-- Это проектная развилка, а не универсальное правило non-historized links.
-- order_line_hk = hash(order_line_id); контекст заголовка обновляется только
-- при новой версии самой позиции. Вход current-staging не читает все raw-версии.
with src as (
    select
        {{ hash_key('l.order_line_id') }}                                             as order_line_hk,
        {{ hash_key('o.order_id') }}                                                  as order_hk,
        {{ hash_key('l.product_id') }}                                                as product_hk,
        {{ hash_diff(['l.qty', 'l.unit_price', 'l.discount_pct', 'l.line_amount']) }} as line_hash,
        l.order_line_id,
        l.qty,
        l.unit_price,
        l.discount_pct,
        l.line_amount,
        o.order_ts,
        o.channel,
        l.updated_at                                                                  as line_updated_at
    from {{ ref('stg_dv_erp__order_lines') }} l
    inner join {{ ref('stg_dv_erp__orders') }} o
        on l.order_id = o.order_id
)

select
    src.order_line_hk,
    src.line_hash,
    src.order_hk,
    src.product_hk,
    src.order_line_id,
    src.qty,
    src.unit_price,
    src.discount_pct,
    src.line_amount,
    src.order_ts,
    src.channel,
    src.line_updated_at,
    cast(now() as date) as load_date,
    'erp'               as record_source
from src
{% if is_incremental() %}
{# Исправление и возвращение значения различаются полным line_updated_at;
   текущий потребитель сортирует по line_updated_at desc, load_date desc. #}
    where not exists (
        select 1 from {{ this }} t
        where
            t.order_line_hk = src.order_line_hk
            and t.line_hash = src.line_hash
            and t.line_updated_at = src.line_updated_at
    )
{% endif %}
