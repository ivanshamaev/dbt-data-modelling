{# ============================================================================
 # Dotted-schema → внешние каталога: видимость отношений для dbt (L27).
 #
 # Проблема (живой прогон 2026-10-23): при каноническом для dbt-starrocks 1.12.x
 # паттерне L18 (custom schema = 'catalog.database') отношения приходят в
 # метаданные dbt с database=None. Адаптерные макросы метаданных решают
 # «внешний или internal» по relation.database → для dotted-схем всегда
 # «internal» → опрашивают default_catalog.information_schema, где внешних
 # таблиц НЕТ. Последствия:
 #   • кэш отношений пуст → is_incremental() всегда false → ВСЕ incremental-
 #     модели (bronze/sat/pit/…) при каждом билде шли по пути CREATE и
 #     перезаливали всю 3-летнюю историю (водяные знаки ни разу не срабатывали),
 #     а на существующей таблице CREATE падал с 1050;
 #   • get_columns_in_relation возвращал [] → dest_columns incremental-стратегии
 #     был бы пуст.
 #
 # Решение: оба макроса распознают точку в schema и ходят в
 # `<catalog>.information_schema` напрямую. Идентичность возвращаемых строк
 # сохраняем dotted (database=NULL, schema='iceberg.bronze'), чтобы ключ кэша
 # совпадал с ключом поиска (None, 'iceberg.bronze'), а render() отношения
 # расщеплялся в 3-компонентное имя (`iceberg`.`bronze`.`tbl`).
 #
 # ВАЖНО (урок L27bis): тело обязано ЗАВЕРШАТЬСЯ return(load_result(...).table) —
 # python-обёртка адаптера получает строки ТОЛЬКО так (паттерн run_query).
 # Без return макрос рендерится в пустую строку, и кэш молча остаётся пустым.
 #
 # НЕ-dotted случай (internal analytics) — поведение адаптера 1.12.2 сохранено
 # дословно (включая materialized_views join).
 # ========================================================================== #}
{%- macro starrocks__list_relations_without_caching(schema_relation) -%}
    {%- set dotted = (schema_relation.database is none
                       and schema_relation.schema is string
                       and '.' in schema_relation.schema) -%}
    {%- if dotted -%}
    {%- set parts = schema_relation.schema.split('.') -%}
    {%- set cat = parts[0] -%}
    {%- set sch = parts[1] -%}
    {%- call statement('list_relations_without_caching', fetch_result=True) -%}
    select
      null as "database",
      tbl.table_name as name,
      '{{ schema_relation.schema }}' as "schema",
      case when tbl.table_type = 'BASE TABLE' or tbl.table_type = 'TABLE' then 'table'
           when tbl.table_type = 'VIEW' then 'view'
           else 'unknown' end as table_type
    from `{{ cat }}`.information_schema.tables tbl
    where tbl.table_schema = '{{ sch }}'
    {%- endcall -%}
  {%- elif schema_relation.database is not none and schema_relation.database != 'default_catalog' -%}
    {#- профильный catalog (напр. iceberg_gold-таргет): внешняя ветка адаптера;
        database возвращаем ЯВНО — иначе кэш сохранит None, а lookup идёт с 'iceberg' #}
    {%- call statement('list_relations_without_caching', fetch_result=True) -%}
    select
      '{{ schema_relation.database }}' as "database",
      tbl.table_name as name,
      tbl.table_schema as "schema",
      case when tbl.table_type = 'BASE TABLE' or tbl.table_type = 'TABLE' then 'table'
           when tbl.table_type = 'VIEW' then 'view'
           else 'unknown' end as table_type
    from `{{ schema_relation.database }}`.information_schema.tables tbl
    where tbl.table_schema = '{{ schema_relation.schema }}'
    {%- endcall -%}
  {%- else -%}
    {%- call statement('list_relations_without_caching', fetch_result=True) -%}
    select
      null as "database",
      tbl.table_name as name,
      tbl.table_schema as "schema",
      case when tbl.table_type = 'BASE TABLE' or tbl.table_type = 'TABLE' then 'table'
           when tbl.table_type = 'VIEW' and mv.table_name is null then 'view'
           when tbl.table_type = 'VIEW' and mv.table_name is not null then 'materialized_view'
           when tbl.table_type = 'SYSTEM VIEW' then 'system_view'
           else 'unknown' end as table_type
    from information_schema.tables tbl
    left join default_catalog.information_schema.materialized_views mv
    on tbl.TABLE_SCHEMA = mv.TABLE_SCHEMA
    and tbl.TABLE_NAME = mv.TABLE_NAME
    where tbl.table_schema = '{{ schema_relation.schema }}'
    {%- endcall -%}
  {%- endif -%}
    {{ return(load_result('list_relations_without_caching').table) }}
{%- endmacro -%}

{%- macro starrocks__get_columns_in_relation(relation) -%}
    {%- set db = relation.database -%}
    {%- set sch = relation.schema -%}
    {%- set dotted = (db is none and sch is string and '.' in sch) -%}
    {%- if dotted -%}
    {%- set parts = sch.split('.') -%}
    {%- set cat = parts[0] -%}
    {%- set sch = parts[1] -%}
  {%- else -%}
        {%- set cat = starrocks__external_catalog(db) -%}
    {%- endif -%}
    {%- set information_schema = ('`' ~ cat ~ '`.information_schema') if cat is not none else 'INFORMATION_SCHEMA' -%}
    {%- call statement('get_columns_in_relation', fetch_result=True) -%}
    select
        column_name,
        data_type,
        character_maximum_length,
        numeric_precision,
        numeric_scale
    from {{ information_schema }}.columns
    where table_name = '{{ relation.identifier }}'
      and table_schema = '{{ sch }}'
    order by ordinal_position
    {%- endcall -%}
    {%- set table = load_result('get_columns_in_relation').table -%}
    {%- if table.rows -%}
    {%- call statement('desc_columns_in_relation', fetch_result=True) -%}
      desc {{ relation }}
    {%- endcall -%}
    {%- set desc_table = load_result('desc_columns_in_relation').table -%}
    {{ return(starrocks__sql_convert_columns_in_relation(relation, table, desc_table)) }}
  {%- else -%}
    {{ return([]) }}
  {%- endif -%}
{%- endmacro -%}
