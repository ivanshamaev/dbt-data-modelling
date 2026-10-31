{{ config(
    materialized='table',
    schema='iceberg.med_silver',
) }}

{# L4.1 · строки заказов: версии (ретро-правки discount/line_amount — паттерн №3). #}
{# Идентичность строки (order_line_id) неизменна, мутируют только суммы — #}
{# одна версионная таблица без отдельной «идентичности» (гранулярность атомарна). #}
with deduped as (
    select
        order_line_id,
        order_id,
        product_id,
        qty,
        unit_price,
        discount_pct,
        line_amount,
        updated_at,
        row_number() over (
            partition by order_line_id, updated_at
            order by _loaded_at desc
        ) as rn
    from {{ ref('brz_erp__order_lines') }}
),

real_changes as (
    select
        order_line_id,
        order_id,
        product_id,
        qty,
        unit_price,
        discount_pct,
        line_amount,
        updated_at,
        concat_ws(
            '~',
            coalesce(cast(qty as varchar), '-'),
            coalesce(cast(unit_price as varchar), '-'),
            coalesce(cast(discount_pct as varchar), '-'),
            coalesce(cast(line_amount as varchar), '-')
        )     as signature,
        lag(concat_ws(
            '~',
            coalesce(cast(qty as varchar), '-'),
            coalesce(cast(unit_price as varchar), '-'),
            coalesce(cast(discount_pct as varchar), '-'),
            coalesce(cast(line_amount as varchar), '-')
        ))
            over (
                partition by order_line_id
                order by updated_at
            ) as prev_signature
    from deduped
    where rn = 1
),

changes_only as (
    select
        order_line_id,
        order_id,
        product_id,
        qty,
        unit_price,
        discount_pct,
        line_amount,
        updated_at
    from real_changes
    where prev_signature is null or signature <> prev_signature
),

with_validity as (
    select
        order_line_id,
        order_id,
        product_id,
        qty,
        unit_price,
        discount_pct,
        line_amount,
        updated_at,
        lead(updated_at) over (
            partition by order_line_id
            order by updated_at
        )     as valid_to,
        row_number() over (
            partition by order_line_id
            order by updated_at desc
        ) = 1 as is_current
    from changes_only
)

select
    order_line_id,
    order_id,
    product_id,
    qty,
    unit_price,
    discount_pct,
    line_amount,
    updated_at as valid_from,
    valid_to,
    is_current
from with_validity
