# Benchmark канонических витрин · 2026-10-31

Окончательный протокол редакции 2.1.0-rc.1: один прогрев и пять измерений каждой пары «витрина × контур», 75 измеренных запусков. Время включает Docker Compose, MySQL-клиент, SQL, передачу и форматирование результата. Это не чистое engine-time.

Источник зафиксирован после виртуального 2026-11-01; 16 CPU, около 32 GiB RAM, один последовательный исполнитель, без сброса кэшей. R1–R4 выполнялись до и после серии. Физические форматы и покрытие ядер различаются; результаты не доказывают универсального превосходства методологии.

| Витрина | Контур | Медиана, мс | Замеров |
|---|---|---:|---:|
| sales_daily | inmon | 438.407 | 5 |
| sales_daily | kimball | 480.449 | 5 |
| sales_daily | vault | 802.349 | 5 |
| sales_daily | anchor | 927.983 | 5 |
| sales_daily | medallion | 435.500 | 5 |
| customer_ltv | inmon | 587.732 | 5 |
| customer_ltv | kimball | 639.973 | 5 |
| customer_ltv | vault | 852.611 | 5 |
| customer_ltv | anchor | 1089.430 | 5 |
| customer_ltv | medallion | 500.037 | 5 |
| promo_effect | inmon | 542.117 | 5 |
| promo_effect | kimball | 450.104 | 5 |
| promo_effect | vault | 1154.298 | 5 |
| promo_effect | anchor | 1024.697 | 5 |
| promo_effect | medallion | 431.783 | 5 |

[Сырые измерения](../../docs/live-run/course-final-2026-10-31/bench-v3/timings.tsv), [SQL и планы](../../docs/live-run/course-final-2026-10-31/bench-v3/), [проверка кода](../../docs/live-run/course-final-2026-10-31/final-code-v3.sha256). Полный разбор стоимости, CPU/RAM и объёмов — [М9.2](../../guide/cource-final/module-09-comparison/02-resources-benchmarks.md).
