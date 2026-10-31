#!/usr/bin/env bash
# Три одинаковых вопроса × пять контуров: 1 прогрев + 5 замеров wall-clock клиента.
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT="${OUT:-queries/benchmarks/run-$(date -u +%Y%m%dT%H%M%SZ)}"
mkdir -p "$OUT/plans"
MYSQL=(docker compose exec -T starrocks mysql -h127.0.0.1 -P9030 -uroot --batch --raw)
marker() {
    docker compose exec -T postgres psql -X -U postgres -d retailco -v ON_ERROR_STOP=1 -At \
        -c "SELECT count(*),max(sim_date),(SELECT count(*) FROM erp.orders) FROM meta.simulated_days"
}
median() { sort -n | awk 'NR==3 {print $1}'; }
marker > "$OUT/source-before.tsv"
make reconcile > "$OUT/reconcile-before.log" 2>&1
printf 'mart\tcontour\trun\telapsed_us\n' > "$OUT/timings.tsv"
: > "$OUT/queries.sha256"
printf '| Витрина | Контур | Медиана, мс | Замеров |\n|---|---|---:|---:|\n' > "$OUT/results.md"
for mart in sales_daily customer_ltv promo_effect; do
    for contour in inmon kimball vault anchor medallion; do
        file="queries/benchmarks/canonical/${mart}__${contour}.sql"
        [ -s "$file" ] || { echo "Нет запроса $file" >&2; exit 1; }
        sha256sum "$file" >> "$OUT/queries.sha256"
        # EXPLAIN не является фактическим профилем scan rows/bytes.
        { printf 'EXPLAIN\n'; cat "$file"; } | "${MYSQL[@]}" > "$OUT/plans/${mart}__${contour}.txt"
        "${MYSQL[@]}" < "$file" > /dev/null
        times=()
        for i in 1 2 3 4 5; do
            start=${EPOCHREALTIME/./}
            "${MYSQL[@]}" < "$file" > /dev/null
            end=${EPOCHREALTIME/./}
            elapsed=$((end-start))
            [ "$elapsed" -ge 0 ] || { echo 'Часы сдвинулись назад' >&2; exit 1; }
            times+=("$elapsed")
            printf '%s\t%s\t%s\t%s\n' "$mart" "$contour" "$i" "$elapsed" >> "$OUT/timings.tsv"
        done
        med=$(printf '%s\n' "${times[@]}" | median)
        millis=$(awk -v us="$med" 'BEGIN {printf "%.3f",us/1000}')
        printf '| %s | %s | %s | 5 |\n' "$mart" "$contour" "$millis" >> "$OUT/results.md"
        echo "$mart / $contour: ${millis} мс"
    done
done
marker > "$OUT/source-after.tsv"
cmp "$OUT/source-before.tsv" "$OUT/source-after.tsv"
make reconcile > "$OUT/reconcile-after.log" 2>&1
cat "$OUT/results.md"
echo "Артефакты: $OUT. Время включает Compose, клиент, передачу и форматирование результата."
