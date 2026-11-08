{{ config(
    materialized='table',
    schema='iceberg.med_silver',
) }}

{# L4.3 · платежи: актуальные версии (refund-переходы статуса, паттерн №9). #}
{# Зерно payment_id: отдельные части оплаты остаются отдельными событиями. #}
with ranked as (
    select
        payment_id,
        order_id,
        paid_ts,
        method,
        amount,
        status,
        refunded_amount,
        refunded_at,
        updated_at,
        _batch_id,
        _loaded_at,
        _source,
        _ingest_date,
        row_number() over (
            partition by payment_id
            order by updated_at desc, _loaded_at desc
        ) as rn
    from {{ ref('brz_erp__payments') }}
)

select
    payment_id,
    order_id,
    paid_ts,
    method,
    amount,
    status,
    refunded_amount,
    refunded_at,
    updated_at
from ranked
where rn = 1
