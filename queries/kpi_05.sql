-- KPI 5: доля денежных возвратов по причине от gross-продаж той же категории.
-- Обе стороны ограничены продажами текущего канонического среза, за всю историю.
-- Знаменатель считается ДО соединения с возвратами и не размножается их числом.
SET CATALOG default_catalog;
USE analytics;

with sales as (
    select
        p.category_l1,
        p.category_l3,
        sum(f.line_amount) as category_sales_amt
    from fct_sales f
    inner join dim_product p on p.product_sk_v = f.product_sk_v
    group by 1, 2
), returned as (
    select
        p.category_l1,
        p.category_l3,
        r.reason,
        count(*) as returns_cnt,
        sum(r.return_qty) as units_returned,
        sum(r.refund_amt) as refund_amt
    from fct_returns r
    inner join dim_product p on p.product_sk_v = r.product_sk_v
    inner join fct_sales f on f.order_line_key = r.order_line_key
    group by 1, 2, 3
)
select
    r.category_l1,
    r.category_l3,
    r.reason,
    r.returns_cnt,
    r.units_returned,
    r.refund_amt,
    s.category_sales_amt,
    r.refund_amt / nullif(s.category_sales_amt, 0) as return_rate
from returned r
inner join sales s
    on r.category_l1 <=> s.category_l1 and r.category_l3 <=> s.category_l3
order by r.refund_amt desc;
