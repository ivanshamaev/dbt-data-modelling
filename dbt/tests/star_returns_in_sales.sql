-- Возврат разрешён после доставки; такая позиция обязана присутствовать в продажах.
select r.return_id
from {{ ref('fact_returns') }} r
left join {{ ref('fact_sales') }} f on f.order_line_key = r.order_line_key
where f.order_line_key is null
