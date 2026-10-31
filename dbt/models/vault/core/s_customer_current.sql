{{ config(
    materialized='table',
    schema='iceberg.vault_core',
    tags=['vault', 'bv'],
) }}

{# L5.3 · Business Vault: s_customer_current — вычисляемый «спутник» текущего #}
{# состояния (последняя версия s_customer_erp на клиента). BV = вычисления, #}
{# стабильные между витринами; всё остальное — в март. #}
with ranked as (
    select
        customer_hk,
        hash_diff,
        segment,
        city,
        region,
        registered_at,
        deleted_at,
        load_date,
        record_source,
        effective_from,
        row_number() over (
            partition by customer_hk
            order by effective_from desc, load_ts desc
        ) as rn
    from {{ ref('s_customer_erp') }}
)

select
    customer_hk,
    segment,
    city,
    region,
    registered_at,
    deleted_at,
    hash_diff,
    effective_from,
    load_date,
    'erp_bv' as record_source
{# вычисляемое: помечаем, что это BV #}
from ranked
where rn = 1
