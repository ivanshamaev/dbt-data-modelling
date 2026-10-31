-- LTV в пределах 180-дневного окна PIT, по сегменту на конец дня заказа.
-- Два способа должны дать одинаковые строки на ОДНОМ временном горизонте.
-- Полное LTV за всю историю: iceberg.vault_marts.im_customer_ltv.
SET CATALOG iceberg;
USE vault_core;

-- Указатель включает бизнес-день, отпечаток и время наблюдения:
-- один отпечаток может повториться при A→B→A в тот же день.
with lines as (
    select
        order_hk, order_ts, line_amount,
        row_number() over (
            partition by order_line_hk order by line_updated_at desc, load_date desc
        ) as rn
    from l_order_line
)
select
    'pit' as method,
    s.segment,
    sum(ol.line_amount) as ltv_amt,
    count(distinct ol.order_hk) as orders_cnt
from lines ol
inner join l_order_customer lc on lc.order_hk = ol.order_hk
inner join b_order_effective_state state on state.order_hk = ol.order_hk
inner join pit_customer pit
    on pit.customer_hk = lc.customer_hk and pit.as_of_date = cast(ol.order_ts as date)
inner join s_customer_erp s
    on s.customer_hk = pit.customer_hk
    and s.hash_diff = pit.s_customer_erp_diff
    and s.effective_from = pit.s_customer_erp_eff_from
    and s.load_ts = pit.s_customer_erp_load_ts
where ol.rn = 1 and state.status in ('paid', 'shipped', 'delivered', 'returned')
group by s.segment
order by s.segment;

-- Тот же valid-time join без готовых указателей; границы берём из того же PIT.
with lines as (
    select
        order_hk, order_ts, line_amount,
        row_number() over (
            partition by order_line_hk order by line_updated_at desc, load_date desc
        ) as rn
    from l_order_line
),
ranked as (
    select
        customer_hk, segment, effective_from,
        row_number() over (
            partition by customer_hk, effective_from order by load_ts desc
        ) as rn
    from s_customer_erp
),
segments as (
    select
        customer_hk, segment, effective_from,
        lead(effective_from) over (partition by customer_hk order by effective_from) as valid_to
    from ranked where rn = 1
),
horizon as (
    select min(as_of_date) as first_day, max(as_of_date) as last_day from pit_customer
)
select
    'intervals' as method,
    s.segment,
    sum(ol.line_amount) as ltv_amt,
    count(distinct ol.order_hk) as orders_cnt
from lines ol
cross join horizon h
inner join l_order_customer lc on lc.order_hk = ol.order_hk
inner join b_order_effective_state state on state.order_hk = ol.order_hk
inner join segments s
    on s.customer_hk = lc.customer_hk
    and cast(ol.order_ts as date) >= s.effective_from
    and (s.valid_to is null or cast(ol.order_ts as date) < s.valid_to)
where ol.rn = 1 and state.status in ('paid', 'shipped', 'delivered', 'returned')
    and cast(ol.order_ts as date) between h.first_day and h.last_day
group by s.segment
order by s.segment;
