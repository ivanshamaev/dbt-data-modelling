{{ config(
    materialized='table',
    schema='iceberg.anchor_stage',
) }}

{# L4.3 · статический справочник: bronze уже уникален (table-перезагрузка), #}
{# дедуп не нужен — только канонизация + category_key для иерархии (гл. 7–8). #}
select
    category_id,
    parent_category_id,
    name,
    {{ hash_key('category_id') }} as category_key
from {{ ref('raw_erp__categories') }}
