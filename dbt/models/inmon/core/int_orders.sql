{{ config(
    materialized='table',
    schema='iceberg.inmon_core',
) }}

{# L4.1 · сущность «заказ» — идентичность: неизменяемые при рождении поля. #}
{# Статусы/суммы/этапы — время-вариантные, их история в int_order_states. #}
{# Естественные FK (customer_id, store_id) — по-инмоновски без денормализации; #}
{# цена этой чистоты читатель почувствует на KPI-запросах (queries/kpi0*_from_3nf.sql). #}
select
    order_id,
    order_key,
    order_no,
    customer_id,
    store_id,
    channel,
    order_ts
from {{ ref('stg_in_erp__orders') }}
