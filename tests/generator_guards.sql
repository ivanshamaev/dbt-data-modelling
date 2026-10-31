-- Отказ происходит до генерации: ни повтор даты, ни пропуск дня не допускаются.
DO $$
DECLARE last_day date; message text;
BEGIN
    SELECT max(sim_date) INTO last_day FROM meta.simulated_days;
    BEGIN
        PERFORM meta.simulate_day(last_day);
        RAISE EXCEPTION 'Проверка: генератор ошибочно разрешил повтор дня';
    EXCEPTION WHEN raise_exception THEN
        GET STACKED DIAGNOSTICS message = MESSAGE_TEXT;
        IF message NOT LIKE 'день % уже прожит%' THEN RAISE; END IF;
        RAISE NOTICE 'Повтор дня отклонён: %',message;
    END;
    BEGIN
        PERFORM meta.simulate_day(last_day+2);
        RAISE EXCEPTION 'Проверка: генератор ошибочно разрешил пропуск дня';
    EXCEPTION WHEN raise_exception THEN
        GET STACKED DIAGNOSTICS message = MESSAGE_TEXT;
        IF message NOT LIKE 'ожидался следующий день %' THEN RAISE; END IF;
        RAISE NOTICE 'Пропуск дня отклонён: %',message;
    END;
END $$;
