-- KPI 9 · Дни out-of-stock по магазинам и SKU (periodic snapshot; ассортиментная
-- покрытие наблюдаемых сочетаний; отсутствие строки не приравнивается к нулю).
SET CATALOG default_catalog;
USE analytics;

select
    store_id,
    product_id,
    count(*) as oos_days
from fact_inventory_daily
where is_out_of_stock
group by 1, 2
order by oos_days desc, 1, 2
limit 100;
