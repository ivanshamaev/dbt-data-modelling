#!/usr/bin/env bash
# Повторное чтение источников с заданного бизнес-дня и пересчёт всех зависимых слоёв.
# Mutable bronze дописывает ранее не виденные версии; дневные события заменяют партиции.
set -euo pipefail
DAY="${DAY:?укажите DAY=YYYY-MM-DD}"
ONLY="${ONLY:-tag:bronze}"
[[ "$DAY" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo 'Неверный формат DAY' >&2; exit 1; }
[[ "$(date -d "$DAY" +%F)" == "$DAY" ]] || { echo 'Неверная дата DAY' >&2; exit 1; }
case "$ONLY" in
  tag:bronze) MED_TGT=tag:med_bronze ;;
  raw_erp__*|raw_crm__*)
    [[ "$ONLY" =~ ^raw_(erp|crm)__[a-z_]+$ && -f "dbt/models/bronze/$ONLY.sql" ]] || { echo 'Неизвестная модель ONLY' >&2; exit 1; }
    MED_TGT="${ONLY/raw_/brz_}" ;;

  *) echo 'ONLY должен быть tag:bronze или именем raw_erp__/raw_crm__ модели' >&2; exit 1 ;;
esac
EXCLUDE=()
if [ -n "${DBT_EXCLUDE:-}" ]; then
    read -r -a EXCLUDED_NAMES <<< "$DBT_EXCLUDE"
    EXCLUDE=(--exclude "${EXCLUDED_NAMES[@]}")
fi
# Абсолютная дата не зависит от часов хоста и от того, до какого дня дошла симуляция.
VARS="{reload_from_date: '$DAY'${DBT_CONTEXT:+, $DBT_CONTEXT}}"
echo "==> Повторное чтение с $DAY: $ONLY и $MED_TGT"
docker compose exec -T dbt dbt build --select "$ONLY" "$MED_TGT" --vars "$VARS" "${EXCLUDE[@]}"
echo '==> Все пять контуров, включая Medallion silver'
docker compose exec -T dbt dbt build \
  --select path:models/inmon path:models/kimball path:models/vault path:models/anchor path:models/medallion/silver path:models/medallion/gold \
  --vars "$VARS" "${EXCLUDE[@]}"
echo 'Готово. Проверка: make kpi && make reconcile'
