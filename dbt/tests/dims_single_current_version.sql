-- Проверяются все представленные сущности, включая группы без current-строк.
-- L4.3 · SCD-дисциплина gold-измерений: у каждой сущности РОВНО ОДНА
-- is_current-версия. Нарушение = регрессия механики версий (жёсткий fail).
select 'dim_customer' as model, customer_id as entity_id, sum(case when is_current then 1 else 0 end) as current_cnt
from {{ ref('dim_customer') }}
group by 1, 2
having sum(case when is_current then 1 else 0 end) <> 1

union all
select 'dim_product', product_id, sum(case when is_current then 1 else 0 end)
from {{ ref('dim_product') }}
group by 1, 2
having sum(case when is_current then 1 else 0 end) <> 1

union all
select 'dim_promo', promo_id, sum(case when is_current then 1 else 0 end)
from {{ ref('dim_promo') }}
group by 1, 2
having sum(case when is_current then 1 else 0 end) <> 1
