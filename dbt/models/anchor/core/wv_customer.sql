{{ config(
    materialized='view',
    schema='iceberg.anchor_core',
    tags=['anchor', 'wv'],
) }}

  {# L5.4 · wv_customer: «классическая форма» через anchor_view-макрос (H14): #}
  {# anchor + текущие атрибуты (segment через knot, city). #}
  {# Обычный SQL view; исключение лишних join проверяется по EXPLAIN. #}
{{ anchor_view( 'a_customer', 'customer_id', attributes=[ {'model': 'ac_customer_segment', 'knot': 'kn_segment', 'as': 'segment'}, {'model': 'ac_customer_city', 'knot': none, 'as': 'city'}, ] ) }}
