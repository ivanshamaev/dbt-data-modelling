#!/usr/bin/env bash
# ============================================================================
# make catalogs: bootstrap Lakekeeper → warehouse → бакет → каталоги StarRocks → smoke
# Проверено по docs.lakekeeper.io/docs/nightly/{bootstrap,engines} (2026-10-18).
# M0-8: живая сверка переменных/эндпоинтов с examples/minimal Lakekeeper.
# ============================================================================
set -euo pipefail

C_BLUE='\033[0;34m'; C_GREEN='\033[0;32m'; C_OFF='\033[0m'
step() { echo -e "${C_BLUE}==> $1${C_OFF}"; }

wait_http() { # url name tries
  local i=0
  until wget -q -O /dev/null "$1" 2>/dev/null; do
    i=$((i+1)); [ "$i" -ge "${3:-60}" ] && { echo "$2 недоступен: $1" >&2; exit 1; }
    sleep 2
  done
}

step "0. Ждём здоровье сервисов"
wait_http http://localhost:8181/health "Lakekeeper"
echo -e "${C_GREEN}    Lakekeeper healthy${C_OFF}"

step "1. Bootstrap Lakekeeper (однократно; повтор — тихо игнорируем)"
# Без auth (OSS, провайдер не задан) токен не нужен; default project создаётся сам.
# Повторный bootstrap = 400 CatalogAlreadyBootstrapped — норма, глушим.
wget -q -O - --header='Content-Type: application/json' \
  --post-data='{"accept-terms-of-use": true}' \
  http://localhost:8181/management/v1/bootstrap 2>/dev/null | grep -vi 'bootstrapped' || true

step "2. Создаём бакет retailco в RustFS (warehouse-валидация требует существующий)"
docker compose --profile init run --rm rustfs-init

step "3. Создаём warehouse retailco (S3 → RustFS), идемпотентно"
# Формат — по management-open-api.yaml v0.14.1: маршрут в ед.ч., warehouse-name,
# storage-credential = type + credential-type + access-key-id (пример из спеки).
# L41: повторный прогон на существующем warehouse — Lakekeeper отвечает
# 400 CreateWarehouseStorageProfileOverlap (не 409); ветка «уже существует»
# обязана ловить оба варианта, иначе set -e убивает скрипт на wget exit 8.
set +e
wget -q -O /tmp/wh.json --content-on-error --server-response \
  --header='Content-Type: application/json' \
  --post-data='{
    "warehouse-name": "retailco",
    "storage-profile": {
      "type": "s3",
      "flavor": "s3-compat",
      "bucket": "retailco",
      "endpoint": "http://rustfs:9000",
      "region": "local",
      "path-style-access": true,
      "sts-enabled": false
    },
    "storage-credential": {
      "type": "s3",
      "credential-type": "access-key",
      "access-key-id": "minioadmin",
      "secret-access-key": "minioadmin"
    }
  }' http://localhost:8181/management/v1/warehouse 2>/tmp/wh.code
set -e
CODE=$(grep -oE 'HTTP/[0-9.]+ [0-9]+' /tmp/wh.code | tail -1 | grep -oE '[0-9]+$')
if echo "$CODE" | grep -qE '^(200|201)$'; then
  echo "    warehouse создан"
elif [ "$CODE" = "409" ] || grep -q 'CreateWarehouseStorageProfileOverlap' /tmp/wh.json 2>/dev/null; then
  echo "    warehouse уже существует"
else
  echo "    ОШИБКА ($CODE):"; cat /tmp/wh.json; echo; exit 1
fi

step "4. Применяем каталоги StarRocks (sql/02_catalogs.sql)"
docker compose exec -T starrocks \
  mysql -h 127.0.0.1 -P 9030 -u root < sql/02_catalogs.sql

step "5. Smoke: 5 запросов"
docker compose exec -T starrocks mysql -h 127.0.0.1 -P 9030 -u root -e "
  SHOW CATALOGS;
"
echo -e "${C_GREEN}catalogs: done. Дальше: make sources && make seed && make live days=60${C_OFF}"
