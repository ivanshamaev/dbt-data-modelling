#!/usr/bin/env bash
# Новый Compose-проект и временная БД: рабочий источник не используется.
set -euo pipefail
cd "$(dirname "$0")/.."
check_project="retailco-generator-check"
compose=(docker compose -p "$check_project" -f docker-compose.generator-test.yml)
"${compose[@]}" up -d --wait postgres
check_db="generator_check_$(date +%s)_$$"
"${compose[@]}" exec -T postgres createdb -U postgres "$check_db"
psql=("${compose[@]}" exec -T postgres psql -X -U postgres -d "$check_db" -v ON_ERROR_STOP=1)
cleanup() {
    local result=$?
    if (( result == 0 )); then
        "${compose[@]}" exec -T postgres dropdb -U postgres "$check_db"
    else
        printf 'Ошибка: тестовая база %s сохранена в проекте %s.\n' "$check_db" "$check_project" >&2
    fi
}
trap cleanup EXIT
load_sources() {
    "${psql[@]}" < sql/00_init_sources.sql
    "${psql[@]}" < sql/01_generator.sql
}
load_sources
"${psql[@]}" < tests/generator_edge_cases.sql
load_sources
# Тот же seed, что у полного набора: уменьшены только число клиентов/SKU/заказов.
"${psql[@]}" -c "SET timezone='Asia/Vladivostok'; SELECT meta.seed_history(date '2026-09-01',1155,160,40,8)"
"${psql[@]}" < tests/generator_business_contracts.sql
"${psql[@]}" -c "SELECT d::date,meta.simulate_day(d::date) FROM generate_series(date '2026-09-02',date '2026-11-01',interval '1 day') g(d)"
"${psql[@]}" < tests/generator_business_contracts.sql
"${psql[@]}" < tests/source_contracts_gate.sql
"${psql[@]}" < tests/generator_guards.sql
"${psql[@]}" < tests/generator_live_cases.sql
# Повторяем короткий seed с другой TZ: бизнес-данные должны совпасть побайтно.
"${psql[@]}" -c "SELECT meta.seed_history(date '2026-09-01',14,40,12,8)"
"${psql[@]}" < tests/generator_reproducibility.sql
printf 'PASS: проверки генератора в изолированной базе.\n'
