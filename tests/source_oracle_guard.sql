DO $$
DECLARE baseline date; last_day date;
BEGIN
    SELECT min(baseline_day) INTO baseline FROM meta.course_customer_baseline_20261031;
    SELECT max(sim_date) INTO last_day FROM meta.simulated_days;
    IF baseline IS NULL OR last_day NOT IN (baseline,baseline+1) THEN
        RAISE EXCEPTION 'Эталон применим только к базовому дню % и одному следующему; сейчас %',baseline,last_day;
    END IF;
END $$;
