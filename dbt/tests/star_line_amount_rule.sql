-- L4.4 · бизнес-правило золота №1 (жёсткий fail — регрессия, которой быть
-- не может по инвариантам генератора): line_amount = qty × unit_price × (1 − discount).
select
    order_line_key,
    qty, unit_price, discount_pct, line_amount,
    round(qty * unit_price * (100 - discount_pct) / 100.0) as expected_amt
from {{ ref('fact_sales') }}
where line_amount <> round(qty * unit_price * (100 - discount_pct) / 100.0)
