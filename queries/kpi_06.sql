-- KPI 6 · Структура оплат и refund'ов по методам платежа (паттерн №9).
SET CATALOG default_catalog;
USE analytics;

select
    method,
    payment_status,
    count(*)      as payments_cnt,
    sum(payment_amt) as amount_amt
from fact_payments
group by 1, 2
order by 1, 2;
