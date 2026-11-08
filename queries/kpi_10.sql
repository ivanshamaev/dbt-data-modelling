-- KPI 10 · Доля выручки новых продуктов против старых (иерархия + время запуска,
-- паттерн №5): «новый» = запущен в [дата заказа − 90 дней, дата заказа].
-- before_launch показывает несогласованные даты синтетического источника.
SET CATALOG default_catalog;
USE analytics;

select
    case
        when p.launched_at > f.order_date then 'before_launch'
        when p.launched_at >= date_sub(f.order_date, 90) then 'new'
        else 'old'
    end as product_age,
    sum(f.line_amount) as revenue_amt,
    sum(f.line_amount) / (select sum(line_amount) from fact_sales) as revenue_share
from fact_sales f
join dim_product p on p.product_sk_v = f.product_sk_v
group by 1;
