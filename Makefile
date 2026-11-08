SHELL := /bin/bash
COMPOSE := docker compose
PSQL := $(COMPOSE) exec -T postgres psql -U postgres -d retailco -v ON_ERROR_STOP=1
MYSQL := $(COMPOSE) exec -T starrocks mysql -h 127.0.0.1 -P 9030 -u root
DBT := $(COMPOSE) exec -T dbt dbt

.DEFAULT_GOAL := help

.PHONY: help up down ps logs
help: ## эта справка
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[0;34m%-16s\033[0m %s\n", $$1, $$2}'

up: ## поднять стенд (pg, rustfs, lakekeeper, starrocks, dbt)
	$(COMPOSE) up -d --build
	@echo "Ждём healthchecks..."; $(COMPOSE) ps

down: ## остановить стенд (данные в volumes сохраняются)
	$(COMPOSE) down

ps: ## статус контейнеров
	$(COMPOSE) ps

logs: ## хвост логов всех сервисов
	$(COMPOSE) logs -f --tail=50

# --- источники и генератор ---------------------------------------------------

.PHONY: sources reset seed simulate-day live
sources: ## применить DDL источников + функции генератора (пересоздаёт схемы!)
	$(PSQL) < sql/00_init_sources.sql
	$(PSQL) < sql/01_generator.sql

reset: ## очистка только источников и журнала; DDL остаётся, DWH не очищается
	$(PSQL) -c "SELECT meta.reset_sources()"

seed: ## seed_history(): исходные ERP/CRM-данные с тремя годами бизнес-дат
	$(PSQL) -c "SELECT meta.seed_history()"

# дата по умолчанию — следующий непрожитый день из журнала генератора (§11.5.7)
simulate-day: ## прожить один день обеих систем (DATE=YYYY-MM-DD опционально)
	@if [ -n "$$DATE" ]; then \
	  $(PSQL) -c "SELECT meta.simulate_day('$$DATE')"; \
	else \
	  $(PSQL) -c "SELECT meta.simulate_day(COALESCE((SELECT max(sim_date)+1 FROM meta.simulated_days), ((SELECT v FROM meta.config WHERE k='t0')::date + 1)))"; \
	fi

live: ## прожить N дней симуляции (days=60 по умолчанию)
	@for i in $$(seq 1 $${days:-60}); do DATE= $(MAKE) -s simulate-day || exit 1; done
	@echo "Симуляция завершена: $$( $(PSQL) -tAc 'SELECT count(*) FROM meta.simulated_days' ) дней прожито"

# --- dbt ----------------------------------------------------------------------

.PHONY: deps build bronze med_bronze med_silver med_gold smoke
deps: ## dbt deps (dbt_utils)
	$(DBT) deps

build: lint contours-check ## канонический прогон: модели + тесты (гейт формата — docs/format-recommendation.md)
	$(DBT) build

bronze: ## общий bronze-слой: инжест источников (методологически нейтрален)
	$(DBT) build --select tag:bronze

# --- слойные селекторы medallion-контура (bronze/silver/gold изолированы;
# --- публичные silver/gold прежней планировки УДАЛЕНЫ — CHANGELOG 2.0.0) ------

med_bronze: ## medallion bronze: собственная bronze-копия контура
	$(DBT) build --select tag:med_bronze

med_silver: ## Medallion Silver: истории, текущие срезы, события и снимки
	$(DBT) build --select tag:med_silver+ --exclude tag:med_gold+

med_gold: ## medallion gold: канонические витрины каталога
	$(DBT) build --select tag:med_gold

# --- изолированные контуры методологий (гл. 13; состав селекторов сверен dbt ls,
# --- live-прогон — см. plan/modules/live-run-history.md) -----------------------
# Каждый контур = свой staging + своё ядро + свои витрины (+общий bronze
# upstream). Кимбалл больше НЕ читает int_*: развязано по требованию изоляции
# (init_task п.2); temporal baseline несут kim_*_history.

.PHONY: inmon kimball vault anchor medallion contours-check
inmon: ## контур Inmon: bronze→stg_in→3NF(int_*)→dm_* (+тесты) — гл. 6
	$(DBT) build --select '+path:models/inmon'

kimball: ## контур Kimball: bronze→stg_kim→звезда(dim/fact/agg/obt)→km_* (+тесты) — гл. 8
	$(DBT) build --select '+path:models/kimball'

vault: ## контур Data Vault: bronze→stg_dv→raw vault→BV/PIT→im_* (+тесты) — гл. 10
	$(DBT) build --select '+path:models/vault'

anchor: ## контур Anchor: общий bronze, собственный staging и историческое ядро → views/marts
	$(DBT) build --select '+path:models/anchor'

medallion: ## контур Medallion: собственные bronze→silver→gold (+тесты) — гл. 12
	$(DBT) build --select path:models/medallion

contours-check: ## проверка полного manifest, включённых тестов и изоляции контуров
	$(DBT) parse --no-partial-parse
	$(COMPOSE) exec -T dbt python /scripts/check_contours.py target/manifest.json

smoke: ## контрольные запросы к источникам и каталогам
	@echo "--- PG: объёмы источников ---"
	$(PSQL) -c "SELECT 'orders' t, count(*) FROM erp.orders UNION ALL SELECT 'customers', count(*) FROM erp.customers UNION ALL SELECT 'inventory', count(*) FROM erp.inventory UNION ALL SELECT 'promo_participation', count(*) FROM crm.promo_participation"
	@echo "--- StarRocks: каталоги ---"
	$(MYSQL) -e "SHOW CATALOGS"

# --- форматирование SQL (docs/format-recommendation.md) -----------------------

.PHONY: lint fmt
lint: ## sqlfluff: проверка единого формата моделей/макросов (гейт build)
	$(COMPOSE) exec -T dbt sqlfluff lint models macros

fmt: ## sqlfluff: автоформатирование моделей/макросов (fix, один проход)
	$(COMPOSE) exec -T dbt sqlfluff fix models macros

# --- KPI и reconciliation ------------------------------------------------------

.PHONY: kpi reconcile rebuild
kpi: ## 13 KPI-запросов к звезде Kimball
	@set -e; for i in $$(seq -w 1 13); do \
	  echo "=== KPI $$i ==="; \
	  $(MYSQL) < queries/kpi_$$i.sql; \
	done

reconcile: ## сверка ядер (M2: 3NF ↔ звезда; M3 добавит vault/anchor)
	set -o pipefail; $(MYSQL) --batch --raw < tests/reconcile.sql | $(COMPOSE) exec -T dbt python /scripts/check_reconciliation.py

rebuild: ## пересборка модели с потомками: make rebuild m=fact_sales (гл. 13)
	@if [ -z "$$m" ]; then echo "usage: make rebuild m=<model>"; exit 1; fi
	$(DBT) build --select "$$m+"

reload-day: ## сценарий 2: перезалив дня (DWH-операция): make reload-day DAY=YYYY-MM-DD [ONLY=raw_erp__orders]
	bash scripts/reload_day.sh

phantoms: ## аудит фантомных файлов в S3-хранилище
	bash scripts/phantom_files.sh audit

phantoms-clean: ## чистка фантомов по префиксу: make phantoms-clean PREFIX=<table>
	bash scripts/phantom_files.sh clean "$(PREFIX)"

gold-on-iceberg: ## старый эксперимент iceberg_gold, вне текущей приёмки
	bash scripts/gold_on_iceberg.sh

compact: ## компакция Iceberg-таблиц bronze (кандидат OPTIMIZE TABLE — H15, M0-6)
	@for t in raw_erp__customers raw_erp__products raw_erp__stores raw_erp__orders \
	         raw_erp__order_lines raw_erp__payments raw_erp__returns raw_erp__inventory \
	         raw_crm__promotions raw_crm__promo_participation; do \
	  echo "OPTIMIZE iceberg.bronze.$$t;"; \
	done | $(MYSQL) && echo "Компакция запущена (список таблиц — bronze)."

bench: ## бенчмарк методики гл. 14: прогрев + 5 замеров, медианы
	bash queries/benchmarks/run.sh

resources: ## ресурсы методологий (лекция 9.2): source/disk/модели/время
	bash scripts/resources_report.sh

catalogs: ## bootstrap Lakekeeper + warehouse + каталоги StarRocks + smoke (scripts/catalogs.sh)
	bash scripts/catalogs.sh
