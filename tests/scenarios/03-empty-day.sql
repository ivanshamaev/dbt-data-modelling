-- Единственная продажа 31 октября в web перестаёт входить в витрину.
UPDATE fixture_erp.orders SET status='cancelled',cancelled_at='2026-11-02 10:00+00',updated_at='2026-11-02 10:00+00' WHERE order_id=104;
UPDATE fixture_erp.payments SET status='refunded',refunded_at='2026-11-02 10:00+00',updated_at='2026-11-02 10:00+00' WHERE payment_id=304;
