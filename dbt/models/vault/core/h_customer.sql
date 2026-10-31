{#append-only: новые BK только (анти-join, H3) #}
{{ config(
    materialized='incremental',
    schema='iceberg.vault_core',
    incremental_strategy='default',
    tags=['vault'],
) }}

-- L5.2 · h_customer: идентичность клиента (business key + load_date + record_source).
-- Hub неизменен: смена атрибутов — дело спутника. Ключ = тот же durable SK,
-- что и в звезде (md5(bk)) — reconciliation без lookup-слоёв (P2-11).
-- load_date = дата загрузки в vault (transaction time; temporal baseline §2.1:
-- вся pre-DWH история получает load_date первого билда — честно и задокументировано).
with src as (
    select
        customer_id,
        {{ hash_key('customer_id') }} as customer_hk
    from {{ ref('stg_dv_erp__customers') }}
)

select
    src.customer_hk,
    src.customer_id,
    cast(now() as date) as load_date,
    'erp'               as record_source
from src
{% if is_incremental() %}
    where not exists (
        select 1 from {{ this }} t
        where t.customer_hk = src.customer_hk
    )
{% endif %}
