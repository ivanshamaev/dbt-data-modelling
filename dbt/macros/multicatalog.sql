{# ============================================================================
 # КАНОНИЧЕСКИЙ ПАТТЕРН dbt-starrocks 1.12.x для multi-catalog (находка L18):
 #
 # Проблема: config(catalog='iceberg', database='bronze') работает для DDL
 # САМОЙ модели, но ref()/тесты резолвят отношение через manifest, где
 # starrocks__generate_database_name всегда возвращает None → ref уходит в
 # profile-схему (`analytics`.`tbl`) → "Unknown table".
 #
 # Решение адаптера (заложено в relation.py: quoted() расщепляет точки):
 # ВНЕШНИЙ путь кодируется в CUSTOM SCHEMA модели как 'catalog.database':
 #   bronze    → schema='iceberg.bronze'
 #   silver-слои аналогично; gold без custom schema → profile (internal).
 # dbt core по умолчанию склеивает custom schema с target.schema
 # (analytics_iceberg.bronze) — поэтому passthrough-оверрайд ниже.
 # Базы во внешнем каталоге преждесозданы (sql/02_catalogs.sql, L17) —
 # CREATE SCHEMA для точечных имён не требуется (см. starrocks__create_schema
 # override в этом же файле).
 # ========================================================================== #}

{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- set prefix = var('schema_prefix', '') -%}
    {%- if prefix and not modules.re.match('^[a-z][a-z0-9_]*_$', prefix) -%}
        {{ exceptions.raise_compiler_error('schema_prefix: ожидается префикс вида fixture_') }}
    {%- endif -%}
    {%- if custom_schema_name is none -%}
        {{ prefix }}{{ target.schema }}
    {%- else -%}
        {%- set parts = (custom_schema_name | trim).split('.') -%}
        {{ parts[:-1] | join('.') ~ '.' if parts | length > 1 else '' }}{{ prefix }}{{ parts[-1] }}
    {%- endif -%}
{%- endmacro %}


{# Для dotted-схем (внешние каталоги) dbt вызывает create_schema перед
   материализацией; CREATE DATABASE `iceberg`.`bronze` из session-каталога —
   невалидно. Для internal: StarRocks не знает IF NOT EXISTS (L20), а run_query
   guard ненадёжен при параллельных threads → ВСЕ базы преждесоздаются
   (02_catalogs.sql + catalogs.sh), create_schema = no-op. #}
{% macro starrocks__create_schema(relation) -%}
    {%- call statement('create_schema') -%}
        select 1
    {%- endcall -%}
{%- endmacro %}
