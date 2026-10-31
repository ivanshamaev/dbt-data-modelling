-- 3 · Согласование сумм: sum(order_lines.line_amount) = orders.total_amount.
-- Инвариант: 0 строк. Ретро-правки №3 правят total_amount и строки согласованно;
-- если строки появились — это баг генератора, а не «допустимый шум»
-- (порог-исключение есть только у payments: легитимные ретро-правки, L26).
-- Проверено 2026-10-24: 0 строк.
SELECT o.order_id, o.total_amount, sum(l.line_amount) AS lines_sum,
       o.total_amount - sum(l.line_amount) AS diff
FROM erp.orders o
JOIN erp.order_lines l USING (order_id)
GROUP BY o.order_id, o.total_amount
HAVING o.total_amount <> sum(l.line_amount);
