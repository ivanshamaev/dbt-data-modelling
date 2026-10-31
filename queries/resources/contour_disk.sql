-- ============================================================================
-- Ресурсы методологий (лекция docs/lectures/m9-02-resources.md, Stage 3):
-- disk по контурам меряется ОБЪЁМОМ S3-ОБЪЕКТОВ бакета (scripts/resources_report.sh,
-- aws-cli по префиксам БД) — honest-метрика Iceberg: information_schema внешних
-- каталогов не экспортирует data_size (проверено 2026-10-31), а SHOW DATA
-- не адресует внешние БД 3-частным именем. Internal-звезда Kimball — SHOW DATA
-- (комментарий ниже). cpu/ram/время — протоколом make resources.
-- ============================================================================

-- 3a) Звезда Kimball (internal): по таблицам (вывод скрипта)
--   for t in dim_* fct_* agg_* obt_* km_*; do
--     mysql -e "SHOW DATA FROM analytics.$t"
--   done

-- 3b) Состав контуров (число таблиц — information_schema внешнего каталога)
-- SET CATALOG iceberg;
-- SELECT table_schema, count(*) tables_cnt FROM information_schema.tables
-- WHERE table_schema IN ('bronze','inmon_stage','inmon_core','inmon_marts',
--   'vault_stage','vault_core','vault_marts','anchor_stage','anchor_core',
--   'anchor_marts','med_bronze','med_silver','med_gold','gold_iceberg')
-- GROUP BY 1 ORDER BY 1;

-- 4) Число моделей/тестов — на хосте репо (dbt ls по path:models/<contour>)
