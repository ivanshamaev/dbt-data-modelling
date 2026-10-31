-- L70: исправление механики в том же бизнес-дне; последняя доставка должна победить.
UPDATE fixture_crm.promotions
SET mechanics='fixed', updated_at='2026-10-31 23:00+00'
WHERE promo_id='PR-1';
