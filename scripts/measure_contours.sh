#!/usr/bin/env bash
# Единственная активная сборка; источник и остальные работы должны быть остановлены.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${OUT:-docs/live-run/contour-measurements-$(date -u +%Y%m%dT%H%M%SZ)}"
name="measure-${EPOCHREALTIME/./}"
WORK="dbt/target/$name"
mkdir -p "$OUT" "$WORK"
trap 'cp -a "$WORK/." "$OUT/"' EXIT
mapfile -t CONTAINERS < <(docker compose ps --status running -q)
[ "${#CONTAINERS[@]}" -ge 5 ] || { echo 'Не все сервисы работают' >&2; exit 1; }
docker inspect --format '{{.Name}}' "${CONTAINERS[@]}" | sed 's#^/##' > "$WORK/container-names.txt"
docker info --format '{"cpu":{{.NCPU}},"ram_bytes":{{.MemTotal}},"engine":"{{.ServerVersion}}"}' > "$WORK/host.json"
marker() {
    docker compose exec -T postgres psql -X -U postgres -d retailco -v ON_ERROR_STOP=1 -At \
        -c "SELECT count(*),max(sim_date),(SELECT count(*) FROM erp.orders) FROM meta.simulated_days"
}
sample() {
    local directory="$1" number="$2"
    mkdir -p "$directory"
    printf '%s\t%s.jsonl\n' "${EPOCHREALTIME/./}" "$number" >> "$directory/samples.tsv"
    docker stats --no-stream --format '{{json .}}' "${CONTAINERS[@]}" > "$directory/$number.jsonl"
}
marker > "$WORK/source-before.tsv"
make contours-check > "$WORK/contours.log" 2>&1
make reconcile > "$WORK/reconcile-before.log" 2>&1
for contour in inmon kimball vault anchor medallion; do
    echo "Измеряется $contour"
    dir="$WORK/$contour"
    mkdir -p "$dir/idle"
    for i in 1 2 3; do sample "$dir/idle" "$i"; sleep 2; done
    (
        printf '%s\n' "${EPOCHREALTIME/./}" > "$dir/start-us.txt"
        set +e
        make "$contour" > "$dir/build.log" 2>&1
        result=$?
        printf '%s\n' "${EPOCHREALTIME/./}" > "$dir/end-us.txt"
        exit "$result"
    ) &
    build_pid=$!
    i=0
    while kill -0 "$build_pid" 2>/dev/null; do
        i=$((i+1))
        sample "$dir" "$i"
        sleep 4
    done
    wait "$build_pid"
    cp dbt/target/run_results.json "$dir/"
    marker > "$dir/source-after.tsv"
    cmp "$WORK/source-before.tsv" "$dir/source-after.tsv"
done
make reconcile > "$WORK/reconcile-after.log" 2>&1
docker compose exec -T dbt python /scripts/summarize_measurements.py "/app/target/$name" > "$WORK/report.md"
cat "$WORK/report.md"
echo "Артефакты: $OUT"
