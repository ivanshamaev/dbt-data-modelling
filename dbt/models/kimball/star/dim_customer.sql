{{ config(
    materialized='table',
    table_type='PRIMARY',
    keys=['customer_sk_v'],
    order_by=['customer_id', 'valid_from'],
    tags=['gold', 'dim'],
) }}

-- L54/L57: ручной SCD2 из собственной наблюдённой истории, без snapshots.
-- Полная реконструкция небольшой размерности учитывает несколько изменений
-- между билдами и поздние версии. Цена: переписываем всю размерность.
select
    {{ hash_key(['a.customer_id', 'cast(a.valid_from as date)']) }} as customer_sk_v,
    i.customer_key,
    a.customer_id,
    a.segment,
    a.city,
    a.region,
    i.registered_at,
    i.is_deleted,
    cast(a.valid_from as date)                                      as valid_from,
    cast(a.valid_to as date)                                      as valid_to,
    a.is_current
from {{ ref('kim_customer_history') }} a
inner join {{ ref('stg_kim_erp__customers') }} i
    on a.customer_id = i.customer_id
