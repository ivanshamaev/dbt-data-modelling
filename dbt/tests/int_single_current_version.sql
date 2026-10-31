-- Проверяются все представленные сущности, включая группы без current-строк.
-- L4.1 · инвариант время-вариантных таблиц ядра: у каждой сущности РОВНО ОДНА
-- is_current-версия. Нарушение = баг механики версий (дубли bronze-потока,
-- дыра в оконной функции) — регрессия, которой быть не должно → жёсткий fail.
select 'int_customer_attributes' as model, customer_id as entity_id,
       sum(case when is_current then 1 else 0 end) as current_cnt
from {{ ref('int_customer_attributes') }}
group by 1, 2
having sum(case when is_current then 1 else 0 end) <> 1

union all
select 'int_product_categories', product_id, sum(case when is_current then 1 else 0 end)
from {{ ref('int_product_categories') }}
group by 1, 2
having sum(case when is_current then 1 else 0 end) <> 1

union all
select 'int_order_states', order_id, sum(case when is_current then 1 else 0 end)
from {{ ref('int_order_states') }}
group by 1, 2
having sum(case when is_current then 1 else 0 end) <> 1

union all
select 'int_order_lines', order_line_id, sum(case when is_current then 1 else 0 end)
from {{ ref('int_order_lines') }}
group by 1, 2
having sum(case when is_current then 1 else 0 end) <> 1

union all
select 'int_payments', payment_id, sum(case when is_current then 1 else 0 end)
from {{ ref('int_payments') }}
group by 1, 2
having sum(case when is_current then 1 else 0 end) <> 1
