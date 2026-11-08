# Имена Anchor и фактов Kimball и переход на версию 3

В версии 3.0.0 имена отражают роль модели и её временную перспективу. По сравнению с версией 2.0.0 переименованы ещё 12 моделей: три широкие проекции Anchor, три агрегата Anchor и шесть фактов Kimball. Версия 2.0.0 ранее переименовала 24 конструкции ядра Anchor. `anc_` обозначает якорь, `attr_` — атрибут, `tie_` — тай, `knot_` — кнот. Состав Anchor остаётся прежним: 11 staging, 27 core и три marts; весь проект содержит 168 моделей и 724 включённых теста.

| Компонент | Префикс | Число | Пример |
|---|---|---:|---|
| Якорь | `anc_` | 5 | `anc_customer` |
| Атрибут | `attr_` | 11 | `attr_customer_segment` |
| Тай, связь | `tie_` | 4 | `tie_customer_order` |
| Кнот | `knot_` | 4 | `knot_segment` |
| Последние известные значения Anchor | `latest_anc_` | 3 | `latest_anc_customer` |
| Агрегат Anchor | `agg_anc_` | 3 | `agg_anc_sales_daily` |
| Факт Kimball | `fact_` | 6 | `fact_sales` |

Префикс staging `stg_anc_` сохраняется. Проекции `latest_anc_` выбирают максимальный valid_from среди незамещённых утверждений; это не параметризованный ответ на произвольную дату. Три `agg_anc_` группируют показатели по дню × каналу, сегменту и участию в промо. Они не переименовываются в измерения: имя описывает действительную роль объекта. Измерения Kimball сохраняют `dim_`; существующие факты меняют только `fct_` на `fact_`. Служебный тег проекций `wv` заменён на `latest`; селекторы `tag:wv` нужно обновить. Поля `customer_id`, `valid_from`, `insert_time`, `superseded_time`, `value` и `knot_id` сохраняют имена и смысл. Изменение относится к именам моделей и таблиц, а не к временной семантике или гранулярности.

## Соответствие имён

| Прежнее имя | Новое имя |
|---|---|
| `a_customer` | `anc_customer` |
| `a_order` | `anc_order` |
| `a_order_line` | `anc_order_line` |
| `a_product` | `anc_product` |
| `a_promo` | `anc_promo` |
| `ac_customer_city` | `attr_customer_city` |
| `ac_customer_segment` | `attr_customer_segment` |
| `ac_order_amount` | `attr_order_amount` |
| `ac_order_channel` | `attr_order_channel` |
| `ac_order_delivered_at` | `attr_order_delivered_at` |
| `ac_order_line_amount` | `attr_order_line_amount` |
| `ac_order_order_ts` | `attr_order_order_ts` |
| `ac_order_paid_at` | `attr_order_paid_at` |
| `ac_order_shipped_at` | `attr_order_shipped_at` |
| `ac_order_status` | `attr_order_status` |
| `ac_promo_mechanics` | `attr_promo_mechanics` |
| `kn_channel` | `knot_channel` |
| `kn_mechanics` | `knot_mechanics` |
| `kn_order_status` | `knot_order_status` |
| `kn_segment` | `knot_segment` |
| `t_customer_order` | `tie_customer_order` |
| `t_order_line_product` | `tie_order_line_product` |
| `t_order_order_line` | `tie_order_order_line` |
| `t_order_promo` | `tie_order_promo` |
| `wv_order_line` | `latest_anc_order_line` |
| `wv_order` | `latest_anc_order` |
| `wv_customer` | `latest_anc_customer` |
| `am_promo_effect` | `agg_anc_promo_effect` |
| `am_customer_ltv` | `agg_anc_customer_ltv` |
| `am_sales_daily` | `agg_anc_sales_daily` |
| `fct_order_lifecycle` | `fact_order_lifecycle` |
| `fct_returns` | `fact_returns` |
| `fct_payments` | `fact_payments` |
| `fct_assortment_coverage` | `fact_assortment_coverage` |
| `fct_sales` | `fact_sales` |
| `fct_inventory_daily` | `fact_inventory_daily` |

## Проверка исходников

Все вызовы ref(), YAML-контракты, SQLFluff-исключения, запросы KPI, benchmarks, reconciliation и сценарные SQL используют новые имена. Чистый parse и lint выполняются внутри dbt-контейнера:

```bash
make deps
make contours-check
make lint
docker compose exec -T dbt python /scripts/check_anchor_naming.py target/manifest.json
```

Чтобы сравнить граф с прежней редакцией, до обновления сохраните чистый manifest старого проекта в `dbt/target/anchor-before.json`. После обновления выполните:

```bash
docker compose exec -T dbt dbt parse --no-partial-parse
docker compose exec -T dbt python /scripts/check_anchor_naming.py target/manifest.json --baseline target/anchor-before.json
```

Проверка сравнивает SQL и зависимости всех моделей, материализацию, физические имена с учётом переименования и договоры всех тестов. Из сравнения исключён пересчитываемый dbt хеш служебного alias generic-теста. Совпадение графа не является выполнением SQL на СУБД. [Проверка версии 3](validation/model-role-naming-2026-11-08/manifest-check.json), [parse и lint](validation/model-role-naming-2026-11-08/parse-lint.log). Историческая [проверка версии 2](validation/anchor-naming-2026-11-08/manifest-check.json) сохранена отдельно.

## Переход существующего стенда

Новые имена создают новые физические отношения в `iceberg.anchor_core`, `iceberg.anchor_marts` и `analytics`. Для существующего стенда нужен последовательный переход при стабильном источнике и одном процессе записи.

1. До обновления сохраните manifest, контрольные выгрузки трёх витрин и резервную копию нужного состояния. Зафиксируйте прежнее имя Compose-проекта и тома. При переносе рабочей папки задайте `COMPOSE_PROJECT_NAME` с прежним значением: имя каталога по умолчанию меняет имя Compose-проекта и его томов. Сохранённые наблюдения Bronze и их первые времена доставки необходимы для восстановления истории.
2. Обновите исходники открытого проекта. Выполните чистый parse, lint и проверку имён. Обновите собственные SQL-запросы по таблице соответствий.
3. Выполните `make anchor`, затем `make kimball`. 24 конструкции Anchor имеют материализацию table и реконструируются из сохранённого Bronze; проекции и агрегаты собираются после своих зависимостей. Новые факты Kimball создаются под новыми именами; для начального наполнения исторических снимков необходим сохранённый вход всего нужного горизонта. Существующие измерения и их историю не удаляйте.
4. Выполните `make reconcile`, сравните сохранённые выгрузки и проверьте временной ответ `queries/bitemporal_order_amount.sql`. Последовательность для нового `attr_order_amount` должна сохранять первое время доставки и A → B → A при соответствующем входе.
5. Завершите переключение потребителей. Старые таблицы и views учитывайте в отдельной операции очистки после проверки зависимостей и резервных копий; старые views могут продолжать обращаться к прежним таблицам. Пока они существуют, они увеличивают физический объём старого и нового ядра вместе.

Обычный `--full-refresh` внешних инкрементальных моделей не используется как способ переименования. Генератор source и журнал симулированных дней при этой операции не сбрасываются. Если прежние наблюдения Bronze утрачены, новое имя модели не восстановит исчезнувшую историю.

Автономная проверка от 2026-11-08 подтверждает 168 моделей, 724 теста и сохранность графа после замены имён. K8s-стенд был недоступен, локальный CPU не поддерживает AVX2; живое исполнение нового ядра не выполнялось. Результаты приёмки от 2026-10-31 относятся к прежним именам. Новая миграция требует собственной проверки данных на доступном стенде.
