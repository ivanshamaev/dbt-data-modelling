-- PostgreSQL: проверяем сумму частичных возвратов по строке заказа.
SELECT r.order_line_id, sum(r.qty) AS returned_qty, max(l.qty) AS bought_qty
FROM erp.returns r
INNER JOIN erp.order_lines l ON l.order_line_id = r.order_line_id
GROUP BY r.order_line_id
HAVING sum(r.qty) > max(l.qty);
