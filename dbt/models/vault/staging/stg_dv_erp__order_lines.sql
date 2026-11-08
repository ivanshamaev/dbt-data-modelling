{{ config(
    materialized='table',
    schema='iceberg.vault_stage',
) }}

{# L4.3 · строки заказов: актуальные версии (ретро-правки discount/line_amount, #}
{# v2.2-спека). Гранулярность будущего fact_sales; order_line_key — идентичность #}
{# строки для возвратов и transactional link. #}
with ranked as (
    select
        order_line_id,
        order_id,
        product_id,
        qty,
        unit_price,
        discount_pct,
        line_amount,
        updated_at,
        _batch_id,
        _loaded_at,
        _source,
        _ingest_date,
        row_number() over (
            partition by order_line_id
            order by updated_at desc, _loaded_at desc
        ) as rn
    from {{ ref('raw_erp__order_lines') }}
)

select
    order_line_id,
    order_id,
    product_id,
    qty,
    unit_price,
    discount_pct,
    line_amount,
    updated_at,
    {{ hash_key('order_line_id') }} as order_line_key
from ranked
where rn = 1
