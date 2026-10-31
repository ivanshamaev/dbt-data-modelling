#!/usr/bin/env bash
# ============================================================================
# make gold-on-iceberg · демонстрация переносимости dbt-кода (L6.2, гл. 13):
# весь gold-слой теми же моделями собирается в Iceberg (target iceberg_gold),
# без правки SQL — переключение каталога lives в профиле.
#
# ЧЕСТНАЯ ОГОВОРКА (главный учебный тезис): переносимость кончается там, где
# просвечивает механика платформы. Из демо исключены модели, чья семантика
# опирается на internal-фичи StarRocks:
#   • dim_customer, fct_order_lifecycle — PRIMARY KEY upsert (H12) — в external
#     INSERT только appends (H3), SCD2/accumulating механика не переносится;
#   • vw_dim_* , fct_assortment_coverage — view в external не проверена (H9).
# Для них канонический дом — internal; «хочешь Iceberg — меняй механику
# (версии через insert_overwrite), а не только каталог».
# ============================================================================
set -euo pipefail
COMPOSE="docker compose"
DBT="$COMPOSE exec -T dbt dbt"

echo "==> Сборка переносимого подмножества gold в Iceberg (target iceberg_gold):"
# L38: исключены и SK-relationships-тесты к dim_customer/dim_product: в переносимом
# подмножестве факт строится на durable-SK (без версий) — версионные SK-связи
# неприменимы; это и есть тезис «переносимость кончается на механике платформы».
$DBT build --target iceberg_gold \
  --select tag:gold \
  --exclude dim_customer fct_order_lifecycle vw_dim_order_date vw_dim_paid_date vw_dim_delivered_date fct_assortment_coverage \
            relationships_fct_sales_product_sk_v__product_sk_v__ref_dim_product_ \
            relationships_fct_sales_customer_sk_v__customer_sk_v__ref_dim_customer_

echo "==> Где что лежит теперь:"
$COMPOSE exec -T starrocks mysql -h 127.0.0.1 -P 9030 -u root \
  -e "SET CATALOG iceberg; SHOW DATABASES; SELECT count(*) FROM gold_iceberg.fct_sales;" || true
echo "Сравнить планы/время тех же KPI из двух каталогов — bench (queries/benchmarks/)."
