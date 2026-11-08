{{ config(
    materialized='view',
    schema='iceberg.anchor_core',
    tags=['anchor', 'latest'],
) }}

  {# L5.4 · latest_anc_customer: «классическая форма» через anchor_view-макрос (H14): #}
  {# anchor + текущие атрибуты (segment через knot, city). #}
  {# Обычный SQL view; исключение лишних join проверяется по EXPLAIN. #}
{{ anchor_view( 'anc_customer', 'customer_id', attributes=[ {'model': 'attr_customer_segment', 'knot': 'knot_segment', 'as': 'segment'}, {'model': 'attr_customer_city', 'knot': none, 'as': 'city'}, ] ) }}
