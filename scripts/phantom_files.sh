#!/usr/bin/env bash
# ============================================================================
# make phantoms / phantoms-clean · сценарий восстановления №4 (L6.2, гл. 13):
# фантомные data-файлы после drop в external catalogs (issue #124, ✅ H6).
#
# Два источника фантомов: temp-таблица КАЖДОГО incremental-прогона и копии
# при --full-refresh (нет ALTER TABLE SWAP для external). Митигации гайда:
#   1) override starrocks__drop_relation с FORCE (macros/drop_relation_force.sql,
#      H17 — проверяется живым прогоном);
#   2) правило «rebuild через insert_overwrite, не drop/create»;
#   3) этот аудит: счётчик объектов хранилища по префиксам таблиц.
#
# Честная оговорка: ПОЛНАЯ детекция орфан-файлов (объект вне всех манифестов
# живых таблиц) требует catalog-API — за рамками гайда (observability исключён).
# Здесь — ручной аудит по префиксам и чистка префикса целиком (для таблиц,
# которые точно удалены из каталога).
# ============================================================================
set -euo pipefail
MODE="${1:-audit}"                       # audit | clean
PREFIX="${2:-}"                          # clean: префикс (имя таблицы/директории)
COMPOSE="docker compose"

# L36: compose run внутри DinD-pod'а глотает вывод — aws-cli запускаем напрямую
# в сети rustfs-контейнера (креды из .env стенда).
AWS_DOCKER() {  # $@ — аргументы aws-cli; endpoint подставляется сам
  docker run --rm --network container:retailco-rustfs \
    -e AWS_ACCESS_KEY_ID="${RUSTFS_ROOT_USER:-minioadmin}" \
    -e AWS_SECRET_ACCESS_KEY="${RUSTFS_ROOT_PASSWORD:-minioadmin}" \
    -e AWS_REGION=local \
    amazon/aws-cli "$@" --endpoint-url http://127.0.0.1:9000
}
[ -f .env ] && source <(grep -E '^RUSTFS_' .env)

echo "==> Объекты в бакете ${RUSTFS_BUCKET:-retailco} (аудит фантомов): по префиксам"
AWS_DOCKER s3api list-objects-v2 --bucket "${RUSTFS_BUCKET:-retailco}" \
    --output text --query "Contents[].Key" \
  | tr "\t" "\n" | grep -v '^$' | cut -d/ -f1 | sort | uniq -c | sort -rn || \
  echo "   (бакет пуст или недоступен)"

echo "==> Суммарный размер:"
AWS_DOCKER s3 ls "s3://${RUSTFS_BUCKET:-retailco}" --recursive --summarize | tail -2 || true

if [ "$MODE" = "clean" ]; then
  [ -z "$PREFIX" ] && { echo "clean требует PREFIX (префикс таблицы в бакете)"; exit 1; }
  echo "==> УДАЛЕНИЕ префикса '$PREFIX' (таблица должна быть удалена из каталога!)"
  read -r -p "Точно? Введите DELETE для подтверждения: " ok
  [ "$ok" = "DELETE" ] || exit 1
  AWS_DOCKER s3 rm "s3://${RUSTFS_BUCKET:-retailco}/$PREFIX" --recursive
  echo "Чисто."
fi
