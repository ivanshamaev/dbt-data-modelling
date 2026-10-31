-- Однократный снимок источника перед одним контрольным виртуальным днём.
CREATE TABLE meta.course_customer_baseline_20261031 AS
SELECT customer_id, segment::text AS segment, city, region, updated_at,
       (SELECT max(sim_date) FROM meta.simulated_days) AS baseline_day
FROM erp.customers;
SELECT count(*) AS customers, min(baseline_day) AS baseline_day
FROM meta.course_customer_baseline_20261031;
