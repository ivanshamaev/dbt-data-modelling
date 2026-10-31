{# ============================================================================
 # Общие SQL-шаблоны текущих срезов атрибутов и широких views.
 # Это часть учебной реализации, а не полный генератор Anchor-модели.
 #
 # Конвенция колонок этой реализации:
 #   anchor:      <pk>, insert_time
 #   attribute:   <pk>, [knot_id | value], valid_from, insert_time, superseded_time
 #   knot:        knot_id, value
 #   tie:         <pk1>, <pk2>, insert_time
 #
 # anchor_current_attr: сабзапрос «текущее верование» атрибута (superseded_time
 # is null, последняя valid_from) — разрешение значения, опционально через knot.
 # anchor_view: собирает широкий view «классической формы» из anchor + attrs +
 # ties (полный генератор — упражнение; здесь общая часть, fallback — ручные SQL).
 # ========================================================================== #}

{% macro anchor_current_attr(attr_model, pk, knot_model=none) -%}
(select
    c.{{ pk }},
    {{ 'k.value' if knot_model else 'c.value' }}       as v,
    row_number() over (partition by c.{{ pk }}
                       order by c.valid_from desc)     as rn
 from {{ ref(attr_model) }} c
    {%- if knot_model %}
 join {{ ref(knot_model) }} k on k.knot_id = c.value
    {%- endif %}
 where c.superseded_time is null)
{%- endmacro %}


{% macro anchor_view(anchor_model, pk, attributes=[], ties=[]) -%}
select
    a.{{ pk }}{% if attributes or ties %},{% endif %}
    {%- for at in attributes %}
    x{{ loop.index }}.v as {{ at.as }}{{ "," if not loop.last or ties }}
    {%- endfor %}
    {%- for t in ties %}
    t{{ loop.index }}.{{ t.col }} as {{ t.as }}{{ "," if not loop.last }}
    {%- endfor %}
from {{ ref(anchor_model) }} a
    {%- for at in attributes %}
left join {{ anchor_current_attr(at.model, pk, at.knot) }} x{{ loop.index }}
    on x{{ loop.index }}.{{ pk }} = a.{{ pk }} and x{{ loop.index }}.rn = 1
    {%- endfor %}
    {%- for t in ties %}
left join (
    select {{ t.pk }} as {{ pk }}, {{ t.col }} from {{ ref(t.model) }}
) t{{ loop.index }} on t{{ loop.index }}.{{ pk }} = a.{{ pk }}
    {%- endfor %}
{%- endmacro %}
