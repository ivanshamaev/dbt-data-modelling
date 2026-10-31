#!/usr/bin/env bash
# Живая проверка общей материализации: непусто → пусто → непусто.
set -euo pipefail
OUT="${OUT:-docs/live-run/empty-table-contract}"
mkdir -p "$OUT"
MYSQL=(docker compose exec -T starrocks mysql -h127.0.0.1 -P9030 -uroot --batch --raw)
"${MYSQL[@]}" -e 'CREATE DATABASE IF NOT EXISTS iceberg.course_contract_checks' > "$OUT/catalog.log"
DBT=(docker compose exec -T dbt dbt --log-path /app/target/contract-probe/logs run
    --project-dir /tests/contracts/empty-table --profiles-dir /app
    --target-path /app/target/contract-probe)
for value in 1 0 2; do
    "${DBT[@]}" --vars "{probe_schema: iceberg.course_contract_checks, probe_value: $value}" > "$OUT/value-$value.log" 2>&1
    actual=$("${MYSQL[@]}" -N -e 'SELECT count(*),coalesce(min(id),0),coalesce(max(id),0) FROM iceberg.course_contract_checks.course_empty_contract')
    if [ "$value" = 0 ]; then expected=$'0\t0\t0'; else expected=$(printf '1\t%s\t%s' "$value" "$value"); fi
    printf '%s\t%s\n' "$value" "$actual" >> "$OUT/results.tsv"
    [ "$actual" = "$expected" ] || { echo "Неверный результат для $value: $actual" >&2; exit 1; }
done
if "${DBT[@]}" --vars '{probe_schema: iceberg.course_contract_checks, probe_partitioned: true}' > "$OUT/partition-guard.log" 2>&1; then
    echo 'Ожидался отказ для внешней партиционированной table' >&2
    exit 1
fi
grep -q 'L63:' "$OUT/partition-guard.log"
echo 'Проверены пустой результат, восстановление данных и запрет partition_by'
