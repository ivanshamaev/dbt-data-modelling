{{ config(
    materialized='view',
    schema='iceberg.anchor_core',
    tags=['anchor', 'wv'],
) }}

  {# L5.4 · wv_order: заказ в классической форме — атрибуты (status/channel/ #}
  {# amount/order_ts) + tie к клиенту. Собран anchor_view-макросом. #}
{{ anchor_view( 'a_order', 'order_id', attributes=[ {'model': 'ac_order_status', 'knot': 'kn_order_status', 'as': 'status'}, {'model': 'ac_order_amount', 'knot': none, 'as': 'total_amount'}, {'model': 'ac_order_channel', 'knot': 'kn_channel', 'as': 'channel'}, {'model': 'ac_order_order_ts', 'knot': none, 'as': 'order_ts'}, {'model': 'ac_order_paid_at', 'knot': none, 'as': 'paid_at'}, {'model': 'ac_order_shipped_at', 'knot': none, 'as': 'shipped_at'}, {'model': 'ac_order_delivered_at', 'knot': none, 'as': 'delivered_at'}, ], ties=[ {'model': 't_customer_order', 'pk': 'order_id', 'col': 'customer_id', 'as': 'customer_id'}, ] ) }}
