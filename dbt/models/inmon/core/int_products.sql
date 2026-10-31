{{ config(
    materialized='table',
    schema='iceberg.inmon_core',
) }}

{# L4.1 · сущность «товар» — идентичность (без время-вариантных атрибутов). #}
{# category_id — время-вариантный атрибут (паттерн №5): его история живет #}
{# в int_product_categories. brand/list_price неизменны в наших источниках — #}
{# осознанное упрощение спеки, задокументировано (§2.2). #}
select
    product_id,
    product_key,
    sku,
    brand,
    list_price,
    is_active,
    launched_at
from {{ ref('stg_in_erp__products') }}
