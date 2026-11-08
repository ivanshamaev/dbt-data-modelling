{{ config(
    materialized='table',
    schema='iceberg.anchor_core',
    tags=['anchor'],
) }}

-- L5.4 · knot_segment: knot — справочник повторяющихся значений для атрибутов.
-- knot_id = row_number по value; номера стабильны только при неизменном домене.
-- После расширения домена все зависимые атрибуты пересобираются вместе с knot.
with stream as (
    select distinct segment as value
    from {{ ref('raw_erp__customers') }}
)

select
    row_number() over (
        order by value
    ) as knot_id,
    value
from stream;
