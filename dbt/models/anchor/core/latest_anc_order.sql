{{ config(
    materialized='view',
    schema='iceberg.anchor_core',
    tags=['anchor', 'latest'],
) }}

  {# L5.4 · latest_anc_order: заказ в классической форме — атрибуты (status/channel/ #}
  {# amount/order_ts) + tie к клиенту. Собран anchor_view-макросом. #}
{{ anchor_view( 'anc_order', 'order_id', attributes=[ {'model': 'attr_order_status', 'knot': 'knot_order_status', 'as': 'status'}, {'model': 'attr_order_amount', 'knot': none, 'as': 'total_amount'}, {'model': 'attr_order_channel', 'knot': 'knot_channel', 'as': 'channel'}, {'model': 'attr_order_order_ts', 'knot': none, 'as': 'order_ts'}, {'model': 'attr_order_paid_at', 'knot': none, 'as': 'paid_at'}, {'model': 'attr_order_shipped_at', 'knot': none, 'as': 'shipped_at'}, {'model': 'attr_order_delivered_at', 'knot': none, 'as': 'delivered_at'}, ], ties=[ {'model': 'tie_customer_order', 'pk': 'order_id', 'col': 'customer_id', 'as': 'customer_id'}, ] ) }}
