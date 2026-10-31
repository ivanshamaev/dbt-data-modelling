{# ============================================================================
 # Bronze-хелперы (L3.2, план §4)
 #
 # Контракт bronze: сырьё как есть + техколонки, никаких бизнес-правил:
 #   _batch_id    — invocation_id записавшего строку запуска
 #   _loaded_at   — время записи; у mutable точный повтор сохраняет первое время
 #   _source      — 'erp' | 'crm' (record source сырьевого слоя)
 #   _ingest_date — дата события/изменения в источнике = дневная партиция
 #                  (mutable: append версий; события/снапшоты: overwrite дня)
 # ========================================================================== #}

{% macro bronze_tech(source_name, event_ts_expr) -%}
    '{{ invocation_id }}' as _batch_id,
    now() as _loaded_at,
    '{{ source_name }}' as _source,
    cast({{ event_ts_expr }} as date) as _ingest_date
{%- endmacro %}


{# ============================================================================
 # Watermark + lookback (план §3.3.4, §8.2; паттерн №7 «late-arriving»)
 #
 # Канонический инкремент bronze-гайда — окно ЦЕЛЫМИ ДНЯМИ (урок L31:
 # голый watermark по event_col режет границу серединой дня, и dynamic_overwrite
 # перезаписывает граничную партицию ЧАСТИЧНО — ранние строки дня теряются;
 # за два прохода пропало 407 строк заказов):
 #   where cast(<event_col> as date) > (select max(_ingest_date) from <this>) - interval N day
 #
 # Почему НЕ microbatch по умолчанию (хотя H5 ✅ поддержан): первый билд
 # истории потребовал бы много дневных батчей × 11 таблиц. Первый запуск
 # читает всю историю; события далее заменяют присутствующие дневные партиции
 # (incremental_strategy='dynamic_overwrite' — на Iceberg заменяет только
 # продюцированные партиции, соседние не трогает; H4).
 #
 # event_col — БЕЗ алиаса: колонка разрешается и в списке FROM модели,
 # и в подзапросе к {{ this }}.
 # ========================================================================== #}
{% macro bronze_lookback(event_col, days=var('lookback_days', 3)) -%}
    {%- if is_incremental() %}
        {% if var('reload_from_date', none) %}
    where cast({{ event_col }} as date) >= cast('{{ var("reload_from_date") }}' as date)
    {% else %}
    where cast({{ event_col }} as date) > coalesce((select max(_ingest_date) from {{ this }}), date '1970-01-01') - interval {{ days }} day
    {% endif %}
    {%- endif %}
{%- endmacro %}


{# L53: источник содержит текущие состояния. Точное сравнение payload, включая
   updated_at, отделяет повтор доставки от новой версии; NULL сравнивается безопасно. #}
{% macro bronze_new_versions(columns) -%}
    {%- set predicates = [] -%}
    {%- for column in columns -%}
        {%- do predicates.append('s.' ~ column ~ ' <=> t.' ~ column) -%}
    {%- endfor -%}
    {%- if is_incremental() %}
    left anti join {{ this }} t
        on {{ predicates | join(' and ') }}
    {%- endif %}
{%- endmacro %}
