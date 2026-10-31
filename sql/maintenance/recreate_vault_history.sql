-- Миграция схемы спутников: добавлено точное время наблюдения load_ts.
-- Источник реконструкции — сохранённая bronze; рабочие erp/crm этим SQL не затрагиваются.
-- Выполнять только перед полной сборкой. Между DROP и сборкой не читать эти отношения.
-- FORCE не применяется: ограничения восстановления описаны в runbook проекта.
DROP TABLE IF EXISTS iceberg.vault_core.s_customer_erp;
DROP TABLE IF EXISTS iceberg.vault_core.s_product_erp;
DROP TABLE IF EXISTS iceberg.vault_core.s_order_lifecycle;
DROP TABLE IF EXISTS iceberg.vault_core.s_order_amounts;
DROP TABLE IF EXISTS iceberg.vault_core.s_promo_crm;
-- Удалённые при L52 ошибочные возвраты больше не должны находиться в текущей связи.
DROP TABLE IF EXISTS iceberg.vault_core.l_return_order_line;

-- Указателю PIT также требуется load_ts для однозначного выбора A→B→A.
DROP TABLE IF EXISTS iceberg.vault_core.pit_customer;
