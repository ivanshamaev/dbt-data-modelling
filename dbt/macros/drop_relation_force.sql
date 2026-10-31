{# ============================================================================
 # starrocks__drop_relation — project override (уроки L27/L28, 2026-10-23).
 #
 # ИСТОРИЯ ВОПРОСА:
 #  • Изначальный override (H17, обход issue #124 «drop в external оставляет
 #    файлы») добавлял FORCE и… не работал: возвращал SQL строкой без
 #    {% call statement() %} → через adapter.drop_relation() → execute_macro
 #    никто не исполнял → drop был тихим no-op (L27-а). Плюс бэктики в
 #    render() ломали startswith-детект FORCE (L27-б).
 #  • Починенная версия с безусловным FORCE оказалась ОПАСНОЙ: при
 #    dirPath-мисматче (L24) temp-таблица получает чужой каталог, и её
 #    FORCE-дроп физически удаляет файлы живой таблицы (S3 404, задвоенные
 #    сканы — L28). Внешних temp-таблиц больше нет вовсе (см.
 #    materializations_override.sql), а модельные таблицы во внешних
 #    каталогах дропаем БЕЗ FORCE: файлы остаются фантомами и чистятся
 #    отдельной процедурой (make phantoms, L6.2 сценарий 4) — фантом это
 #    мусор, но не потеря чужих данных.
 #  • DROP VIEW … FORCE — синтаксическая ошибка StarRocks: FORCE применим
 #    только к таблицам (учтено на всякий случай).
 #
 # Текущая семантика: обычный DROP через statement() — как у адаптера,
 # но с корректной цепочкой исполнения (statement-обёртка обязательна:
 # python-путь execute_macro исполняет SQL только так).
 # ========================================================================== #}

{% macro starrocks__drop_relation(relation) -%}
    {%- call statement('drop_relation', auto_begin=False) -%}
        drop {{ relation.type }} if exists {{ relation.render() }}
    {%- endcall -%}
{%- endmacro %}
