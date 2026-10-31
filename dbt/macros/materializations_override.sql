{# ============================================================================
 # Материализации для dotted-схем во внешнем каталоге (уроки L27/L28/L29).
 #
 # ПОЧЕМУ НЕ ШТАТНЫЕ (dbt-starrocks 1.12.2):
 #  • view: штатная материализация строит «кандидата» под tmp-именем и
 #    сравнивает определения; изменившееся — rename/replace. Для внешних
 #    каталогов это ломается дважды: (а) ICEBERG_VIEW не поддерживает ALTER
 #    (rename → «doesn't support [ALTER]»); (б) внешние view НЕВИДИМЫ как VIEW
 #    в information_schema (BASE TABLE!) → wrong-type ветка → тот же ALTER.
 #  • incremental: каждый прогон создаёт TEMP-таблицу `__dbt_tmp` во внешнем
 #    каталоге. При dirPath-мисматче (L24) temp получает ЧУЖОЙ каталог, и
 #    cleanup-дроп temp'а физически удаляет файлы живой таблицы (S3 404,
 #    задвоенные сканы — L28). Temp-таблицы во внешнем каталоге на этом
 #    стеке принципиально небезопасны.
 #
 # РЕШЕНИЕ:
 #  • view — всегда CREATE OR REPLACE (нужен конфиг on_view_exists='replace',
 #    установлен в dbt_project.yml). View — чистые метаданные, пересоздание
 #    дёшево и идемпотентно; «skip-if-unchanged» — потерян сознательно.
 #  • incremental для dotted-схем — ПРЯМОЙ insert (overwrite) из model SQL,
 #    без temp-таблицы. Бронза: dynamic_overwrite — атомарная замена партиций
 #    окна (H4). Спутники (append): insert into с дедупликацией в SQL.
 #    Internal (analytics) — штатный поток адаптера без изменений.
 # ========================================================================== #}

{%- materialization table, adapter='starrocks' -%}
    {%- set target_relation = this.incorporate(type='table') -%}
    {%- set catalog = config.get('catalog', target.catalog) -%}
    {%- set database_cfg = config.get('database') or target_relation.schema -%}
    {%- set on_table_exists = config.get('on_table_exists', 'replace') -%}

    {#- L30: dotted-схема во внешнем каталоге — БЕЗ drop/create: Lakekeeper
        purge каталога soft-dropped таблицы убивает файлы новой таблицы,
        записанные туда при dirPath-мисматче. Вместо этого — ПОЛНЫЙ
        insert overwrite для НЕПАРТИЦИОНИРОВАННОЙ таблицы. L63: Iceberg
        сохраняет отсутствующие во входе партиции; флаг dynamic_overwrite
        не превращает его в полный static overwrite внутренних таблиц. -#}
    {%- set tgt_catalog = config.get('catalog', target.catalog) -%}
    {%- set prof_external = (tgt_catalog is not none and tgt_catalog != 'default_catalog') -%}
    {%- set dotted = (database is none and schema is string and '.' in schema) -%}
    {%- set ext_here = dotted or prof_external -%}
    {%- set code = model['compiled_code'].strip().rstrip(';').strip() -%}

    {%- if ext_here -%}
      {%- if config.get('partition_by') -%}
        {{ exceptions.raise_compiler_error('L63: materialized=table во внешнем каталоге требует непартиционированной таблицы; INSERT OVERWRITE не удаляет отсутствующие партиции Iceberg. После смены размещения нужна отдельная миграция.') }}
      {%- endif -%}
      {%- if prof_external and not dotted -%}
        {%- set target_relation = adapter.Relation.create(
            database=tgt_catalog,
            schema=target.schema,
            identifier=target_relation.identifier,
            type='table'
        ) -%}
      {%- endif -%}
      {%- set existing_relation = load_relation(target_relation) -%}
      {{ run_hooks(pre_hooks) }}
      {%- if existing_relation is none -%}
        {{ log("Creating new table: " ~ target_relation, info=True) }}
        {%- call statement('main') -%}
          {{ starrocks__create_table_as(false, target_relation, code, true) }}
        {%- endcall -%}
      {%- else -%}
        {# L63: пустой INSERT OVERWRITE Iceberg оставляет старые данные.
           Источники модели должны быть стабильны между проверкой и записью. #}
        {%- set probe = run_query('select 1 as has_row from (' ~ code ~ ') model_rows limit 1') -%}
        {%- if probe.rows | length == 0 -%}
          {{ log("Пустой результат: TRUNCATE без drop " ~ target_relation, info=True) }}
          {%- call statement('main') -%}
            truncate table {{ target_relation }}
          {%- endcall -%}
        {%- else -%}
          {{ log("Full rewrite (insert overwrite, без drop): " ~ target_relation, info=True) }}
          {%- set dest_columns = adapter.get_columns_in_relation(existing_relation) -%}
          {%- set dest_cols_csv = get_quoted_csv(dest_columns | map(attribute="name")) -%}
          {%- call statement('main') -%}
          insert /*+SET_VAR(dynamic_overwrite = FALSE)*/ overwrite {{ target_relation }} ({{ dest_cols_csv }})
          (
              {{ code }}
          )
          {%- endcall -%}
        {%- endif -%}
      {%- endif -%}
      {{ run_hooks(post_hooks) }}
      {{ return({'relations': [target_relation]}) }}
    {%- endif -%}

    {#- internal analytics: штатный поток адаптера —#}
    {%- set is_external = false -%}
    {%- if catalog != 'default_catalog' -%}
      {%- set is_external = true -%}
      {%- if not database_cfg -%}
        {%- set msg -%}
          External tables require both 'catalog' and 'database'
        {%- endset %}
        {{ exceptions.raise_compiler_error(msg) }}
      {%- endif -%}
    {%- endif -%}

    {%- if is_external -%}
      {%- set target_relation = adapter.Relation.create(
          database=catalog,
          schema=database_cfg,
          identifier=target_relation.identifier,
          type='table'
      ) -%}
      {%- set existing_relation = load_relation(target_relation) -%}
    {%- else -%}
      {%- set existing_relation = load_cached_relation(this) -%}
    {%- endif -%}

    {%- set sql = model['compiled_code'] -%}

    {{ run_hooks(pre_hooks) }}

    {%- if existing_relation is not none -%}
      {%- if should_full_refresh() or on_table_exists == 'replace' -%}
        {{ log("Dropping and recreating table", info=True) }}
        {{ adapter.drop_relation(existing_relation) }}
        {%- set existing_relation = none -%}
      {%- elif on_table_exists == 'append' -%}
        {% call statement('main') -%}
          INSERT INTO {{ target_relation }}
          {{ sql }}
        {%- endcall %}
        {{ return({'relations': [target_relation]}) }}
      {%- elif on_table_exists == 'ignore' -%}
        {{ return({'relations': [target_relation]}) }}
      {%- else -%}
        {%- set msg -%}
          Unknown on_table_exists strategy: '{{ on_table_exists }}'.
          Valid options are: 'replace', 'append', 'ignore'
        {%- endset %}
        {{ exceptions.raise_compiler_error(msg) }}
      {%- endif -%}
    {%- endif -%}

    {%- if existing_relation is none -%}
      {{ log("Creating new table: " ~ target_relation, info=True) }}
      {% call statement('main') -%}
        {{ starrocks__create_table_as(false, target_relation, sql, is_external) }}
      {%- endcall %}
    {%- endif -%}

    {{ run_hooks(post_hooks) }}

    {{ return({'relations': [target_relation]}) }}
{%- endmaterialization -%}


{%- materialization view, adapter='starrocks' -%}
  {%- set target_relation = this.incorporate(type='view') -%}
  {%- set sql = model['compiled_code'] -%}
  {{ run_hooks(pre_hooks) }}
  {%- call statement('main') -%}
    {{ starrocks__create_view_as(target_relation, sql) }}
  {%- endcall -%}
  {{ run_hooks(post_hooks) }}
  {{ return({'relations': [target_relation]}) }}
{%- endmaterialization -%}


{%- materialization incremental, adapter='starrocks' -%}
    {%- set keys = config.get('keys', validator=validation.any[list]) -%}
    {%- set full_refresh_mode = (should_full_refresh()) -%}
    {%- set identifier = this.name -%}
    {%- set target_relation = api.Relation.create(
        identifier=identifier,
        schema=schema,
        database=database,
        type='table',
    ) -%}
    {%- set tmp_relation = make_temp_relation(this).incorporate(type='table') -%}

    {%- set catalog = config.get('catalog', target.catalog) -%}
    {%- set database_cfg = config.get('database') or target.schema -%}

    {%- if catalog != 'default_catalog' and database_cfg -%}
      {%- set is_external = true -%}
    {%- endif -%}

    {%- if is_external -%}
      {%- set target_relation = adapter.Relation.create(
        database=catalog,
        schema=database_cfg,
        identifier=target_relation.identifier,
        type='table'
      ) -%}
      {%- set tmp_relation = adapter.Relation.create(
        database=catalog,
        schema=database_cfg,
        identifier=tmp_relation.identifier,
        type='table'
      ) -%}
    {%- endif -%}

    {#- L28: dotted-схема ('iceberg.bronze') с database=None — тоже внешний
        каталог; temp-таблицы для него не создаём вообще. Профильный catalog
        (iceberg_gold) — внешний тем же образом (L38). -#}
    {%- set tgt_catalog_inc = config.get('catalog', target.catalog) -%}
    {%- set prof_external_inc = (tgt_catalog_inc is not none and tgt_catalog_inc != 'default_catalog') -%}
    {%- set dotted = (database is none and schema is string and '.' in schema) or prof_external_inc -%}
    {%- if prof_external_inc and database is none -%}
      {%- set target_relation = api.Relation.create(
          identifier=identifier,
          schema=target.schema,
          database=tgt_catalog_inc,
          type='table',
      ) -%}
    {%- endif -%}
    {%- set code = compiled_code.strip().rstrip(';').strip() -%}

    {%- set existing_relation = load_relation(target_relation) -%}
    {%- set incremental_strategy = starrocks__validate_get_incremental_strategy(config) -%}

    {%- if not dotted -%}
      {{ drop_relation_if_exists(tmp_relation) }}
    {%- endif -%}

    {%- set on_schema_change = incremental_validate_on_schema_change(config.get('on_schema_change'), default='ignore') -%}

    {{ run_hooks(pre_hooks) }}

    {%- if existing_relation is none -%}
      {%- call statement('main') -%}
          {{ starrocks__create_table_as(False, target_relation, compiled_code, is_external) }}
      {%- endcall -%}

    {%- elif existing_relation.is_view -%}
        {#-- Can't overwrite a view with a table, drop it before creating table --#}
        {{ log("Dropping relation " ~ target_relation ~ " because it is a view and this model is a table.") }}
        {%- do adapter.drop_relation(existing_relation) -%}
        {%- call statement('main') -%}
            {{ starrocks__create_table_as(False, target_relation, compiled_code, is_external) }}
        {%- endcall -%}

    {%- elif full_refresh_mode and is_external -%}
        {#-- External catalogs have no ALTER TABLE ... SWAP WITH, so the backup-and-exchange
             route below is unavailable: drop and recreate in place instead. --#}
        {%- do adapter.drop_relation(existing_relation) -%}
        {%- call statement('main') -%}
            {{ starrocks__create_table_as(False, target_relation, compiled_code, is_external) }}
        {%- endcall -%}

    {%- elif full_refresh_mode -%}
        {#-- First create a backup of the existing table and then exchange the new table with the backup --#}
        {%- set backup_identifier = existing_relation.identifier ~ "__dbt_backup" -%}
        {%- set backup_relation = existing_relation.incorporate(path={"identifier": backup_identifier}) -%}
        {%- do adapter.drop_relation(backup_relation) -%}

        {%- call statement('main') -%}
            {{ starrocks__create_table_as(False, backup_relation, compiled_code, is_external) }}
        {%- endcall -%}

        {%- do starrocks__exchange_relation(target_relation, backup_relation) -%}

    {%- elif dotted -%}
        {#- L28: ПРЯМОЙ путь без temp-таблицы: insert (overwrite) целевым
            SQL модели. Стратегии: append/default → INSERT INTO;
            insert_overwrite → overwrite (dynamic=FALSE);
            dynamic_overwrite → overwrite (dynamic=TRUE). -#}
        {%- set dest_columns = adapter.get_columns_in_relation(existing_relation) -%}
        {%- set dest_cols_csv = get_quoted_csv(dest_columns | map(attribute="name")) -%}
        {%- set dyn = 'TRUE' if incremental_strategy in ('dynamic_overwrite', 'microbatch') else 'FALSE' -%}
        {%- if incremental_strategy in ('append', 'default') -%}
          {%- call statement('main') -%}
          insert into {{ target_relation }} ({{ dest_cols_csv }})
          (
              {{ code }}
          )
          {%- endcall -%}
        {%- else -%}
          {%- call statement('main') -%}
          insert /*+SET_VAR(dynamic_overwrite = {{ dyn }})*/ overwrite {{ target_relation }} ({{ dest_cols_csv }})
          (
              {{ code }}
          )
          {%- endcall -%}
        {%- endif -%}

    {% else %}
        {#-- Create the temp relation, either as a view or as a temp table (internal; штатный путь адаптера) --#}
        {%- call statement('create_tmp_relation') -%}
            {{ starrocks__create_table_as(True, tmp_relation, compiled_code, is_external) }}
        {%- endcall -%}

        {%- do adapter.expand_target_column_types(
            from_relation=tmp_relation,
            to_relation=target_relation
        ) -%}
        {#-- Process schema changes. Returns dict of changes if successful. Use source columns for upserting/merging --#}
        {%- set dest_columns = process_schema_changes(on_schema_change, tmp_relation, existing_relation) -%}
        {%- if not dest_columns %}
            {%- set dest_columns = adapter.get_columns_in_relation(existing_relation) -%}
        {%- endif -%}

        {#-- Get the incremental_strategy, the macro to use for the strategy, and build the sql --#}
        {%- set incremental_predicates = config.get('predicates', none) or config.get('incremental_predicates', none) -%}
        {%- set strategy_sql_macro_func = adapter.get_incremental_strategy_macro(context, incremental_strategy) -%}
        {%- set strategy_arg_dict = ({'target_relation': target_relation, 'temp_relation': tmp_relation, 'unique_key': keys, 'dest_columns': dest_columns, 'incremental_predicates': incremental_predicates }) -%}

        {%- call statement('main') -%}
            {{ strategy_sql_macro_func(strategy_arg_dict) }}
        {%- endcall -%}
    {%- endif -%}

    {%- if not dotted -%}
        {%- do drop_relation_if_exists(tmp_relation) -%}
    {%- endif -%}

    {{ run_hooks(post_hooks) }}

    {%- set target_relation = target_relation.incorporate(type='table') -%}

    {%- set should_revoke = should_revoke(existing_relation.is_table, full_refresh_mode) -%}
    {%- do apply_grants(target_relation, grant_config, should_revoke=should_revoke) -%}
    {%- do persist_docs(target_relation, model) -%}

    {{ return({'relations': [target_relation]}) }}
{%- endmaterialization -%}
