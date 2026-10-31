# RetailCo dbt-проект

dbt-модели RetailCo (пять контуров методологий) и всё необходимое для их
прогона: локальный docker-стенд и настройки Kubernetes-кластера для деплоя.

Скопировано из `data-modeling-guide` (без docs/guide/plan — только рабочая часть).

## Структура

```
dbt/                 dbt-проект retailco: bronze + 5 контуров
  models/bronze/     общий инжест источников (нейтральный)
  models/inmon/      Inmon: staging → 3NF (int_*) → dm_*
  models/kimball/    Kimball: staging → звезда (dim/fct/agg/obt) → km_*
  models/vault/      Data Vault: staging → HUB/LINK/SAT → PIT → im_*
  models/anchor/     Anchor: staging → ядро → views/marts
  models/medallion/  Medallion: bronze → silver → gold
  macros/            кастомные макросы (multicatalog, materializations, hash)
  tests/             singular-тесты контуров (bronze/звезда/vault)
  snapshots/         снапшоты (сейчас отключены)
  profiles.yml       профиль StarRocks; packages.yml — зависимость dbt_utils
docker-compose.yml   стенд: postgres (erp/crm) + rustfs + lakekeeper + starrocks + dbt
docker/              образ dbt-runner: dbt.Dockerfile (dbt-core 1.12.5 + dbt-starrocks)
.env                 переменные стенда
Makefile             цели запуска (up, build, kpi, reconcile, …)
scripts/             скрипты проверок и операций (contours-check, reload-day, отчёты)
sql/                 DDL источников, генератор данных, каталоги StarRocks
queries/             13 KPI-запросов, бенчмарки, ресурсные отчёты
tests/               reconcile, сценарии приёмки, контракты источников
kubernetes/          kubeconfig тестового кластера + как подключаться
```

## Запуск локально

```bash
cp .env .env            # при необходимости поправить порты/креды
make up                 # поднять стенд (pg, rustfs, lakekeeper, starrocks, dbt)
make deps               # dbt deps (dbt_utils)
make sources            # DDL источников + функции генератора (пересоздаёт схемы!)
make seed               # исходные данные (3 года истории)
make live days=5        # прожить несколько дней симуляции (опционально)
make catalogs           # бакет + warehouse + каталоги StarRocks
make build              # канонический прогон: модели + тесты
make kpi                # 13 KPI-запросов
make reconcile          # сверка ядер методологий
```

Отдельный контур: `make inmon | kimball | vault | anchor | medallion`.

## Деплой на Kubernetes-кластер

Кластер Beget Cloud (`a54281`), pod `stand` в ns `retailco` с docker-стендом
внутри; репозиторий копируется в `/workspace` пода.

```bash
export KUBECONFIG=$PWD/kubernetes/kubeconfig_87aa2491-f136-45db-9bef-ab3bc55d90b6.yaml
kubectl get nodes
kubectl -n retailco get pod stand            # STATUS Running
kubectl -n retailco exec stand -- docker ps  # контейнеры стенда

# доставка репозитория в под и прогон:
kubectl -n retailco cp . stand:/workspace
kubectl -n retailco exec stand -- make -C /workspace up build
```

Подробнее: `kubernetes/_how_to_connect.md`,
в исходном репо — `docs/live-run/runbook-m4-server-session.md`.
