{{ config(
    materialized='incremental',
    schema='iceberg.vault_core',
    incremental_strategy='default',
    tags=['vault'],
) }}

-- L5.2 · l_return_order_line: связь «возврат ссылается на строку заказа»
-- (частичные возвраты — свои строки; qty/refund — в спутнике возвратов
-- или на связи; здесь на связи, как и в l_order_line — единая школа (а)).
with src as (
    select
        r.{{ hash_key(['r.return_id', 'r.order_line_id']) }} as return_order_line_hk,
        r.{{ hash_key('r.return_id') }}                      as return_hk,
        r.{{ hash_key('r.order_line_id') }}                  as order_line_hk,
        r.return_id,
        r.return_ts,
        r.qty                                                as return_qty,
        r.refund_amount                                      as refund_amt
    from {{ ref('stg_dv_erp__returns') }} r
)

select
    src.return_order_line_hk,
    src.return_hk,
    src.order_line_hk,
    src.return_id,
    src.return_ts,
    src.return_qty,
    src.refund_amt,
    cast(now() as date) as load_date,
    'erp'               as record_source
from src
{% if is_incremental() %}
    where not exists (
        select 1 from {{ this }} t
        where t.return_order_line_hk = src.return_order_line_hk
    )
{% endif %}
