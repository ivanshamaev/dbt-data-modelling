{{ config(
    materialized='table',
    schema='iceberg.bronze',
) }}

-- L3.2 · raw_erp__categories: статический справочник (~325 строк, без таймстемпов).
-- Осознанно table = полная перезагрузка: дешевле, чем выдумывать watermark для
-- неизменяемых данных. Внешняя table обновляется без drop/create;
-- пустой результат очищается веткой TRUNCATE (materializations_override.sql).
select
    category_id,
    parent_category_id,
    name,
    {{ bronze_tech('erp', 'now()') }}
from {{ source('erp_pg', 'categories') }}
