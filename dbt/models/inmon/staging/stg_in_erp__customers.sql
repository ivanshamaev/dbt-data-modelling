{{ config(
    materialized='table',
    schema='iceberg.inmon_stage',
) }}

{# L4.3 · staging-канон, шаблон для мутабельных сущностей: #}
{# 1) дедуп bronze-истории -> актуальная версия строки (row_number по PK, #}
{# свежесть по updated_at/_loaded_at); #}
{# 2) чистка/типизация + флаги; #}
{# 3) durable hash-SK (identity + строка версии SCD2: bk | valid_from). #}
{# Материализация table (полная пересборка): текущие состояния компактны; #}
{# альтернативы (view/ephemeral) — после живой проверки M0-1 (H9); #}
{# Внешняя table пересчитывается без drop/create; пустой результат очищается явно. #}
{# Никаких бизнес-фильтров: удалённые клиенты остаются (is_deleted). #}
with ranked as (
    select
        customer_id,
        segment,
        city,
        region,
        registered_at,
        updated_at,
        deleted_at,
        _batch_id,
        _loaded_at,
        _source,
        _ingest_date,
        row_number() over (
            partition by customer_id
            order by updated_at desc, _loaded_at desc
        ) as rn
    from {{ ref('raw_erp__customers') }}
)

select
    customer_id,
    segment,
    city,
    region,
    registered_at,
    updated_at,
    deleted_at,
    deleted_at is not null                                      as is_deleted,
    {{ hash_key('customer_id') }}                               as customer_key,
    {{ hash_key(['customer_id', 'cast(updated_at as date)']) }} as customer_sk_v
from ranked
where rn = 1
