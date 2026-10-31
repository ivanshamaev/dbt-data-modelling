{{ config(
    materialized='table',
    schema='iceberg.anchor_core',
    tags=['anchor'],
) }}

-- Наблюдения атрибута сохраняются с первым временем доставки из bronze.
-- valid_from — бизнес-день; superseded_time закрывает только прежнее
-- утверждение о ТОМ ЖЕ бизнес-дне, а не всю историю сущности.
with stream as (
    select
        customer_id,
        city                     as value,
        cast(updated_at as date) as valid_from,
        _loaded_at
    from {{ ref('raw_erp__customers') }}
),

dedup as (
    select
        customer_id,
        value,
        valid_from,
        _loaded_at,
        row_number() over (
            partition by customer_id, valid_from, _loaded_at
            order by _loaded_at
        ) as rn
    from stream
),

normalized as (
    select
        customer_id,
        value,
        valid_from,
        _loaded_at
    from dedup
    where rn = 1
)

select
    customer_id,
    value,
    valid_from,
    _loaded_at as insert_time,
    lead(_loaded_at) over (
        partition by customer_id, valid_from
        order by _loaded_at
    ) as superseded_time
from normalized
