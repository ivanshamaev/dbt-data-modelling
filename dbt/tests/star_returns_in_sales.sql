-- Л4.4 · пороговый relationships для возвратов: строки возвратов cancelled-после-
-- оплаты заказов (refund-флоу генератора) не попадают в fct_sales по семантике
-- выручки (статус cancelled исключён) — легитимные «орфаны» ~4%. Порог 6%.
select
    round(count(*) / nullif((select count(*) from {{ ref('fct_returns') }}), 0), 4) as orphan_share,
    count(*) as orphan_cnt
from {{ ref('fct_returns') }} r
left join {{ ref('fct_sales') }} f on f.order_line_key = r.order_line_key
where f.order_line_key is null
having count(*) / nullif((select count(*) from {{ ref('fct_returns') }}), 0) > 0.06
