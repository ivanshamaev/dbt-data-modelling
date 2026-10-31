FROM python:3.11-slim

# Версии фиксированы (план §3.1): dbt-core 1.12.x + адаптер той же мажорной линии.
# Обновление — через CHANGELOG-регламент (§8.5), не молча.
RUN pip install --no-cache-dir \
    "dbt-core==1.12.5" \
    "dbt-starrocks==1.12.2" \
    # Форматирование SQL: standalone SQLFluff (dbt lint/format требуют dbt v2 и
    # не знают StarRocks) — docs/format-recommendation.md §3
    "sqlfluff==3.3.1"

WORKDIR /app
ENTRYPOINT ["sleep", "infinity"]
