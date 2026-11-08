-- Полный отсортированный набор наблюдений клиента и его сегмента; stdout хешируется SHA-256.
SELECT 'raw' AS layer,customer_id,segment,cast(updated_at AS varchar) AS valid_time,
       cast(_loaded_at AS varchar) AS first_seen,'' AS superseded
FROM iceberg.bronze.raw_erp__customers
UNION ALL
SELECT 'brz',customer_id,segment,cast(updated_at AS varchar),cast(_loaded_at AS varchar),''
FROM iceberg.med_bronze.brz_erp__customers
UNION ALL
SELECT 'anchor',a.customer_id,k.value,cast(a.valid_from AS varchar),cast(a.insert_time AS varchar),
       coalesce(cast(a.superseded_time AS varchar),'')
FROM iceberg.anchor_core.attr_customer_segment a
INNER JOIN iceberg.anchor_core.knot_segment k ON k.knot_id=a.value
ORDER BY 1,2,3,4,5,6;
