-- ============================================================================
-- Каталоги StarRocks: JDBC (источники PG) + Iceberg REST (Lakekeeper/MinIO)
-- План §3.2/§3.3; конфигурации проверены по docs.lakekeeper.io (V3 журнала).
-- Выполняется ВНУТРИ StarRocks (make catalogs), не в PostgreSQL!
-- ============================================================================

-- 1) Источники: федеративный доступ к erp.* / crm.* (только чтение)
-- driver_url: maven-ссылка (контейнер должен иметь интернет);
-- оффлайн-fallback M0: положить jar в контейнер и указать file://-путь.
CREATE EXTERNAL CATALOG IF NOT EXISTS erp_pg
PROPERTIES (
    "type"         = "jdbc",
    "user"         = "retailco_ro",
    "password"     = "retailco_ro",
    "jdbc_uri"     = "jdbc:postgresql://postgres:5432/retailco",
    "driver_url"   = "https://repo1.maven.org/maven2/org/postgresql/postgresql/42.7.4/postgresql-42.7.4.jar",
    "driver_class" = "org.postgresql.Driver"
);

-- 2) Lakehouse: Iceberg через REST-каталог Lakekeeper, данные в MinIO
-- Статические S3-ключи: надёжный путь для кастомных эндпоинтов (Lakekeeper docs:
-- vended credentials для custom endpoints не работали в 3.3, с 3.4.1+ «probably
-- not required» — на 4.1 можно пробовать, для стенда остаёмся на статике).
CREATE EXTERNAL CATALOG IF NOT EXISTS iceberg
PROPERTIES (
    "type"                       = "iceberg",
    "iceberg.catalog.type"       = "rest",
    "iceberg.catalog.uri"        = "http://lakekeeper:8181/catalog",
    "iceberg.catalog.warehouse"  = "retailco",
    "aws.s3.enable_path_style_access" = "true",
    "aws.s3.endpoint"            = "http://rustfs:9000",
    "aws.s3.access_key"          = "minioadmin",
    "aws.s3.secret_key"          = "minioadmin",
    "aws.s3.region"              = "local"
);

-- Смоук-проверка выполняется скриптом scripts/catalogs.sh (шаг 5).

-- 3) Внешние databases контуров: dbt-starrocks не создаёт databases в external-каталогах
--    (находка живого прогона L17) — преждесоздаём идемпотентно.
--    Карта контуров (guide/cource-improve/todo_cource_dev.md §4.2):
--      bronze.*      — общий инжест (нейтрален к методологиям)
--      <contour>_stage/_core/_marts — изолированные контуры методологий
--      med_bronze/med_silver/med_gold — контур medallion (все три слоя свои)
SET CATALOG iceberg;
CREATE DATABASE IF NOT EXISTS bronze;
CREATE DATABASE IF NOT EXISTS inmon_stage;
CREATE DATABASE IF NOT EXISTS inmon_core;
CREATE DATABASE IF NOT EXISTS inmon_marts;
CREATE DATABASE IF NOT EXISTS kimball_stage;
CREATE DATABASE IF NOT EXISTS vault_stage;
CREATE DATABASE IF NOT EXISTS vault_core;
CREATE DATABASE IF NOT EXISTS vault_marts;
CREATE DATABASE IF NOT EXISTS anchor_stage;
CREATE DATABASE IF NOT EXISTS anchor_core;
CREATE DATABASE IF NOT EXISTS anchor_marts;
CREATE DATABASE IF NOT EXISTS med_bronze;
CREATE DATABASE IF NOT EXISTS med_silver;
CREATE DATABASE IF NOT EXISTS med_gold;
CREATE DATABASE IF NOT EXISTS gold_iceberg;   -- демо переносимости (L6.2)
-- Легаси-базы прежней планировки (silver, silver_vault, silver_anchor) НЕ
-- создаются; на стендах старой сборки их можно удалить вручную (L30: после
-- drop не обращаться к ним SHOW CREATE/SELECT; перезапуск сборки самолечится):
--   DROP DATABASE IF EXISTS iceberg.silver;
--   DROP DATABASE IF EXISTS iceberg.silver_vault;
--   DROP DATABASE IF EXISTS iceberg.silver_anchor;
SET CATALOG default_catalog;

-- internal analytics тоже преждесоздаём (create_schema = no-op в multicatalog.sql)
SET CATALOG default_catalog;
CREATE DATABASE IF NOT EXISTS analytics;
