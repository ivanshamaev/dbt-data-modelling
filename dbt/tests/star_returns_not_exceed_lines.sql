-- L52: сумма частичных возвратов ограничена покупкой.
select
    order_line_key,
    sum(return_qty) as returned_qty,
    max(line_qty) as bought_qty
from {{ ref('fct_returns') }}
group by order_line_key
having sum(return_qty) > max(line_qty)
