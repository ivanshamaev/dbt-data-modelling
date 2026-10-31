#!/usr/bin/env bash
# Диск текущих таблиц и сохранённых файлов; неизвестное не подменяется нулём.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${OUT:-docs/live-run/resources-$(date -u +%Y%m%dT%H%M%SZ)}"
name="resources-${EPOCHREALTIME/./}"
WORK="dbt/target/$name"
APP="/app/target/$name"
mkdir -p "$OUT" "$WORK/ddl" "$WORK/internal"
trap 'cp -a "$WORK/." "$OUT/"' EXIT
MYSQL=(docker compose exec -T starrocks mysql -h127.0.0.1 -P9030 -uroot --batch --raw)
PY=(docker compose exec -T dbt python /scripts/resource_inventory.py)
make contours-check > "$WORK/contours.log" 2>&1
cp dbt/target/manifest.json dbt/target/run_results.json "$WORK/"
"${PY[@]}" list "$APP/manifest.json" > "$WORK/relations.tsv"
"${PY[@]}" sql "$APP/manifest.json" > "$WORK/current-files.sql"
"${MYSQL[@]}" -N < "$WORK/current-files.sql" > "$WORK/current-files.tsv"
while IFS=$'\t' read -r model kind relation; do
    if [ "$kind" = external ]; then
        "${MYSQL[@]}" -e "SHOW CREATE TABLE $relation" < /dev/null > "$WORK/ddl/$model.tsv"
    else
        "${MYSQL[@]}" -e "SHOW DATA FROM $relation" < /dev/null > "$WORK/internal/$model.tsv"
    fi
done < "$WORK/relations.tsv"
bucket="${RUSTFS_BUCKET:-$(awk -F= '$1=="RUSTFS_BUCKET" {print $2}' .env)}"
[[ "$bucket" =~ ^[a-z0-9.-]+$ ]] || { echo 'Не определён корректный bucket' >&2; exit 1; }
printf '%s\n' "$bucket" > "$WORK/bucket.txt"
# Креды передаются штатным Compose-сервисом; конфигурация с паролями не печатается.
docker compose run --rm --no-deps --pull never --entrypoint aws rustfs-init \
    --endpoint-url http://rustfs:9000 s3api list-objects-v2 --bucket "$bucket" \
    --query 'Contents[].[Key,Size]' --output text \
    > "$WORK/s3-objects.tsv" 2> "$WORK/s3-inventory.stderr"
docker compose exec -T postgres psql -X -U postgres -d retailco -v ON_ERROR_STOP=1 \
    -A -F $'\t' -P footer=off < queries/resources_source.sql > "$WORK/source.tsv"
docker info --format '{"cpu":{{.NCPU}},"ram_bytes":{{.MemTotal}},"engine":"{{.ServerVersion}}","kernel":"{{.KernelVersion}}"}' > "$WORK/host.json"
docker compose exec -T dbt python -c 'import importlib.metadata as m; print("\n".join(f"{p}={m.version(p)}" for p in ("dbt-core","dbt-starrocks","sqlfluff")))' > "$WORK/versions.txt"
"${PY[@]}" summary "$APP/manifest.json" "$APP" > "$WORK/report.md"
cp -a "$WORK/." "$OUT/"
cat "$OUT/report.md"
echo "Артефакты: $OUT. CPU/RAM собирает scripts/measure_contours.sh во время сборок."
