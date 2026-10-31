SELECT 'pit_rows' AS check_name,cast(count(*) AS varchar) AS actual FROM iceberg.PREFIXvault_core.pit_customer
UNION ALL SELECT 'pit_days',cast(count(DISTINCT as_of_date) AS varchar) FROM iceberg.PREFIXvault_core.pit_customer
UNION ALL SELECT 'pit_first',cast(min(as_of_date) AS varchar) FROM iceberg.PREFIXvault_core.pit_customer
UNION ALL SELECT 'pit_last',cast(max(as_of_date) AS varchar) FROM iceberg.PREFIXvault_core.pit_customer
UNION ALL SELECT 'promo_daily_versions',cast(count(*) AS varchar) FROM PREFIXanalytics.dim_promo WHERE promo_id='PR-1' AND valid_from='2026-10-31'
UNION ALL SELECT 'promo_current_end',cast(ends_at AS varchar) FROM PREFIXanalytics.dim_promo WHERE promo_id='PR-1' AND is_current
UNION ALL SELECT 'promo_empty_intervals',cast(count(*) AS varchar) FROM PREFIXanalytics.dim_promo WHERE valid_to IS NOT NULL AND valid_to<=valid_from
ORDER BY 1;
