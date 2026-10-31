-- Две временные оси: сумма для фиксированного бизнес-дня T,
-- как она была известна в каждый фактический момент доставки D.
-- Выбирается первый заказ с несколькими наблюдёнными суммами.
-- Пустой результат означает, что такого заказа в загруженной истории нет.
-- Сценарный набор после фазы 02 показывает для заказа 101: 30000 → 28000 → 30000.
-- Обычный текущий срез не может восстановить эту последовательность.

SET CATALOG iceberg;
USE anchor_core;

with candidate as (
    select
        order_id,
        max(valid_from) as business_day
    from ac_order_amount
    group by order_id
    having count(distinct value) > 1
    order by order_id
    limit 1
),

moments as (
    select distinct
        c.order_id,
        c.business_day,
        a.insert_time as known_at
    from candidate c
    inner join ac_order_amount a on a.order_id = c.order_id
),

perspectives as (
    select
        m.order_id,
        m.business_day,
        m.known_at,
        a.value as believed_amount,
        a.valid_from as amount_valid_from,
        a.insert_time as belief_insert_time,
        a.superseded_time,
        row_number() over (
            partition by m.order_id, m.known_at
            order by a.valid_from desc, a.insert_time desc
        ) as rn
    from moments m
    inner join ac_order_amount a
        on a.order_id = m.order_id
        and a.valid_from <= m.business_day
        and a.insert_time <= m.known_at
        and (a.superseded_time is null or m.known_at < a.superseded_time)
)

select
    order_id,
    business_day,
    known_at,
    believed_amount,
    amount_valid_from,
    belief_insert_time,
    superseded_time
from perspectives
where rn = 1
order by order_id, known_at;
