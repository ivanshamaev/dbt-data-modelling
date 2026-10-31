-- Состояние после фазы 02: ручные ожидания для истории, не только итоговых витрин.
SELECT 'bronze_customer_observations' AS check_name, count(*) AS actual, 3 AS expected
FROM iceberg.PREFIXbronze.raw_erp__customers WHERE customer_id=1
UNION ALL
SELECT 'inmon_customer_days', count(*), 2
FROM iceberg.PREFIXinmon_core.int_customer_attributes WHERE customer_id=1
UNION ALL
SELECT 'inmon_current_premium', count(*), 1
FROM iceberg.PREFIXinmon_core.int_customer_attributes
WHERE customer_id=1 AND segment='premium' AND valid_from='2026-10-31' AND valid_to IS NULL
UNION ALL
SELECT 'vault_aba_rows', count(*), 3
FROM iceberg.PREFIXvault_core.s_order_amounts s
INNER JOIN iceberg.PREFIXvault_core.h_order h ON h.order_hk=s.order_hk WHERE h.order_id=101
UNION ALL
SELECT 'vault_aba_same_business_day', count(DISTINCT effective_from), 1
FROM iceberg.PREFIXvault_core.s_order_amounts s
INNER JOIN iceberg.PREFIXvault_core.h_order h ON h.order_hk=s.order_hk WHERE h.order_id=101
UNION ALL
SELECT 'vault_aba_load_times', count(DISTINCT load_ts), 3
FROM iceberg.PREFIXvault_core.s_order_amounts s
INNER JOIN iceberg.PREFIXvault_core.h_order h ON h.order_hk=s.order_hk WHERE h.order_id=101
UNION ALL
SELECT 'vault_aba_amounts', sum(total_amount), 88000
FROM iceberg.PREFIXvault_core.s_order_amounts s
INNER JOIN iceberg.PREFIXvault_core.h_order h ON h.order_hk=s.order_hk WHERE h.order_id=101
UNION ALL
SELECT 'pit_days', count(DISTINCT as_of_date), 180 FROM iceberg.PREFIXvault_core.pit_customer
UNION ALL
SELECT 'pit_rows', count(*), 360 FROM iceberg.PREFIXvault_core.pit_customer
UNION ALL
SELECT 'pit_horizon', datediff(max(as_of_date),min(as_of_date)), 179 FROM iceberg.PREFIXvault_core.pit_customer
UNION ALL
SELECT 'pit_last_day', count(*), 2 FROM iceberg.PREFIXvault_core.pit_customer WHERE as_of_date='2026-10-31'
UNION ALL
SELECT 'pit_resolved_pointers', count(*), 360
FROM iceberg.PREFIXvault_core.pit_customer p
INNER JOIN iceberg.PREFIXvault_core.s_customer_erp s
 ON s.customer_hk=p.customer_hk AND s.hash_diff=p.s_customer_erp_diff
 AND s.effective_from=p.s_customer_erp_eff_from AND s.load_ts=p.s_customer_erp_load_ts
UNION ALL
SELECT 'anchor_original_still_known', count(*), 1
FROM iceberg.PREFIXanchor_core.ac_customer_segment a
INNER JOIN iceberg.PREFIXanchor_core.kn_segment k ON k.knot_id=a.value
WHERE customer_id=1 AND k.value='standard' AND valid_from='1970-01-01' AND superseded_time IS NULL
UNION ALL
SELECT 'anchor_vip_previous_belief', count(*), 1
FROM iceberg.PREFIXanchor_core.ac_customer_segment a
INNER JOIN iceberg.PREFIXanchor_core.kn_segment k ON k.knot_id=a.value
WHERE customer_id=1 AND k.value='vip' AND valid_from='2026-10-31' AND superseded_time>insert_time
UNION ALL
SELECT 'anchor_premium_current_belief', count(*), 1
FROM iceberg.PREFIXanchor_core.ac_customer_segment a
INNER JOIN iceberg.PREFIXanchor_core.kn_segment k ON k.knot_id=a.value
WHERE customer_id=1 AND k.value='premium' AND valid_from='2026-10-31' AND superseded_time IS NULL
UNION ALL
SELECT 'partial_returns_qty', sum(qty), 2 FROM iceberg.PREFIXbronze.raw_erp__returns WHERE order_line_id=201
ORDER BY 1;
