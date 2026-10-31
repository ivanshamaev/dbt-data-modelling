{{ config(
    materialized='table',
    schema=var('probe_schema'),
    partition_by=['id'] if var('probe_partitioned', false) else none,
) }}

-- Отдельный проект: в основной DAG и число 168 моделей не входит.
select cast({{ var('probe_value', 1) }} as bigint) as id
where {{ var('probe_value', 1) }} > 0
