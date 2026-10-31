{{ config(
    materialized='table',
    schema='iceberg.inmon_core',
) }}

{# L4.1 · категории: статическая иерархия-самоссылка (3 уровня, §2.2). #}
{# В 3NF хранится как есть; flatten level1..3 — работа dim_product (гл. 8), #}
{# bridge table — экспертная альтернатива. category_key — durable SK. #}
select
    category_id,
    parent_category_id,
    name,
    category_key
from {{ ref('stg_in_erp__categories') }}
