#!/usr/bin/env bash
# Изолированные источники fixture_erp/crm и НОВОЕ пространство DWH на каждый прогон.
set -euo pipefail
PREFIX="${PREFIX:?укажите новый префикс, например fixture01_}"
[[ "$PREFIX" =~ ^fixture[0-9]+_$ ]] || { echo 'Допустим только fixture<номер>_' >&2; exit 1; }
OUT="${OUT:-docs/live-run/scenarios-$PREFIX}"
mkdir -p "$OUT"
PG=(docker compose exec -T postgres psql -X -U postgres -d retailco -v ON_ERROR_STOP=1 -P pager=off)
MYSQL=(docker compose exec -T starrocks mysql -h127.0.0.1 -P9030 -uroot --batch --raw)
CONTEXT="schema_prefix: $PREFIX, source_erp_schema: fixture_erp, source_crm_schema: fixture_crm"
DBT=(docker compose exec -T dbt dbt build --vars "{$CONTEXT}" --target-path "target/scenarios/$PREFIX"
     --exclude bronze_orders_daily_volume_bounds bronze_inventory_daily_volume_bounds)

# CREATE без IF NOT EXISTS предохраняет от смешения старой истории с новым сценарием.
sed "s/PREFIX/$PREFIX/g" tests/scenarios/00-catalogs.sql | "${MYSQL[@]}" > "$OUT/catalogs.log" 2>&1
"${PG[@]}" < tests/scenarios/00-source.sql > "$OUT/source.log" 2>&1
sed "s/PREFIX/$PREFIX/g" tests/scenarios/marts.sql > "$OUT/marts.sql"
sed "s/PREFIX/$PREFIX/g" tests/scenarios/stability.sql > "$OUT/stability.sql"
sed "s/PREFIX/$PREFIX/g" tests/scenarios/history.sql > "$OUT/history.sql"

verify() {
    local phase="$1" label="$2"
    "${MYSQL[@]}" < "$OUT/marts.sql" > "$OUT/$label-marts.tsv"
    docker compose exec -T dbt python /scripts/check_scenarios.py "$phase" < "$OUT/$label-marts.tsv"
}
for phase in 00 01 02 03; do
    case "$phase" in
        01) "${PG[@]}" < tests/scenarios/01-changes.sql > "$OUT/01-source.log" ;;
        02) "${PG[@]}" < tests/scenarios/02-corrections.sql > "$OUT/02-source.log" ;;
        03) "${PG[@]}" < tests/scenarios/03-empty-day.sql > "$OUT/03-source.log" ;;
    esac
    echo "==> Фаза $phase"
    "${DBT[@]}" > "$OUT/$phase-build.log" 2>&1
    verify "$phase" "$phase"
    if [ "$phase" = 02 ]; then
        "${MYSQL[@]}" < "$OUT/history.sql" > "$OUT/history.tsv"
        docker compose exec -T dbt python /scripts/check_history.py < "$OUT/history.tsv"
        "${MYSQL[@]}" < "$OUT/stability.sql" > "$OUT/before-repeat.tsv"
        "${DBT[@]}" > "$OUT/repeat-build.log" 2>&1
        verify 02 repeat
        "${MYSQL[@]}" < "$OUT/stability.sql" > "$OUT/after-repeat.tsv"
        cmp "$OUT/before-repeat.tsv" "$OUT/after-repeat.tsv"
        echo 'Наблюдения изменяемых источников и времена Anchor не изменились'
    fi
done
echo '==> Перезалив старого дня через штатный скрипт'
DAY=2026-10-10 ONLY=raw_erp__orders DBT_CONTEXT="$CONTEXT" DBT_EXCLUDE="bronze_orders_daily_volume_bounds bronze_inventory_daily_volume_bounds" bash scripts/reload_day.sh > "$OUT/reload.log" 2>&1
verify 03 reload
echo '==> Категория товара на день позднего снимка остатков'
"${PG[@]}" < tests/scenarios/04-inventory.sql > "$OUT/inventory-source.log"
docker compose exec -T dbt dbt build \
    --vars "{$CONTEXT, reload_from_date: '1970-01-01'}" \
    --target-path "target/scenarios/$PREFIX-inventory" \
    --exclude bronze_orders_daily_volume_bounds bronze_inventory_daily_volume_bounds \
    > "$OUT/inventory-build.log" 2>&1
sed "s/PREFIX/$PREFIX/g" tests/scenarios/inventory.sql | "${MYSQL[@]}" > "$OUT/inventory.tsv"
diff -u tests/scenarios/inventory-expected.tsv "$OUT/inventory.tsv"
verify 03 after-inventory
echo '==> Сдвиг окна PIT и две версии промо в один день'
"${PG[@]}" < tests/scenarios/05-window-promo.sql > "$OUT/window-promo-source.log"
"${DBT[@]}" > "$OUT/window-promo-build.log" 2>&1
sed "s/PREFIX/$PREFIX/g" tests/scenarios/window-promo.sql | "${MYSQL[@]}" > "$OUT/window-promo.tsv"
diff -u tests/scenarios/window-promo-expected.tsv "$OUT/window-promo.tsv"
verify 03 after-window-promo
echo '==> Исправление механики промо внутри бизнес-дня'
"${PG[@]}" < tests/scenarios/06-promo-mechanics.sql > "$OUT/promo-mechanics-source.log"
"${DBT[@]}" > "$OUT/promo-mechanics-build.log" 2>&1
sed "s/PREFIX/$PREFIX/g" tests/scenarios/promo-mechanics.sql | "${MYSQL[@]}" > "$OUT/promo-mechanics.tsv"
diff -u tests/scenarios/promo-mechanics-expected.tsv "$OUT/promo-mechanics.tsv"
verify 03 after-promo-mechanics
echo "Сценарии завершены: $OUT"
