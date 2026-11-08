{{ config(
    materialized='view',
    schema='iceberg.anchor_core',
    tags=['anchor', 'latest'],
) }}

  {# L5.4 · latest_anc_order_line: строка заказа в классической форме — сумма + ties #}
  {# к заказу и товару. Собран anchor_view-макросом. #}
{{ anchor_view( 'anc_order_line', 'order_line_id', attributes=[ {'model': 'attr_order_line_amount', 'knot': none, 'as': 'line_amount'}, ], ties=[ {'model': 'tie_order_order_line', 'pk': 'order_line_id', 'col': 'order_id', 'as': 'order_id'}, {'model': 'tie_order_line_product', 'pk': 'order_line_id', 'col': 'product_id', 'as': 'product_id'}, ] ) }}
