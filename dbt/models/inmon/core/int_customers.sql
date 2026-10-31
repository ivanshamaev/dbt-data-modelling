{{ config(
    materialized='table',
    schema='iceberg.inmon_core',
) }}

{# L4.1 · Inmon CIF, сущность «клиент» — ИДЕНТИЧНОСТЬ (без атрибутов!). #}
{# Нормализация по-инмоновски: существование клиента отдельно от его #}
{# времени-вариантных атрибутов (сегмент/город) — они в #}
{# int_customer_attributes. Прелюдия к hub/satellite разделению DV (гл. 9–10): #}
{# int_customers ≈ будущий h_customer, int_customer_attributes ≈ s_customer_erp. #}
{#  #}
{# Источник: staging (очищенное актуальное состояние). registered_at неизменен; #}
{# deleted_at — soft delete (актуальное значение в идентичности, история #}
{# Soft Delete-событий — в bronze). #}
select
    customer_id,
    customer_key,
    registered_at,
    deleted_at,
    deleted_at is not null as is_deleted
from {{ ref('stg_in_erp__customers') }}
