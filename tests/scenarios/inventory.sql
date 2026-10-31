SELECT snap_date, category_id
FROM PREFIXanalytics.fct_inventory_daily
WHERE product_id=2
ORDER BY snap_date;
