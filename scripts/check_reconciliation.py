"""Проверка табличного вывода mysql --batch --raw; ошибки SQL ловит pipefail."""

import csv
import sys
from collections import Counter
from decimal import Decimal, InvalidOperation


def check(text):
    counts = Counter()
    errors = []
    totals = {}
    seen = set()
    header = None
    expected = {"R1_kpi1_total_revenue", "R2_kpi7_ltv_by_segment", "R3_kpi13_promo_revenue",
                "R4_sales_daily", "R4_customer_ltv", "R4_promo_effect"}
    for row in csv.reader(text.splitlines(), delimiter="\t"):
        if not row:
            continue
        if row[0] == "check_name":
            header = row
            continue
        if header is None or len(row) != len(header) or row[0] not in expected:
            errors.append(f"Неожиданная строка сверки: {row}")
            continue
        item = dict(zip(header, row))
        name = item["check_name"]
        counts[name] += 1
        if name.startswith("R1_"):
            if item["core"] in totals:
                errors.append(f"Повтор ядра R1: {item['core']}")
            totals[item["core"]] = Decimal(item["value_amt"])
        elif item.get("status") != "OK":
            errors.append(f"Нарушение: {row}")
        if name.startswith("R4_"):
            key = (name, item["dim1"], item["dim2"])
            if key in seen or item["contours_cnt"] != "5":
                errors.append(f"Нарушены зерно или полнота: {row}")
            seen.add(key)
            for left, right in (("orders_cnt_min", "orders_cnt_max"),
                                ("revenue_amt_min", "revenue_amt_max")):
                try:
                    low, high = Decimal(item[left]), Decimal(item[right])
                    if not low.is_finite() or not high.is_finite() or low != high:
                        errors.append(f"R4: разные или неполные меры {key}: {left}/{right}")
                except (KeyError, InvalidOperation, ValueError):
                    errors.append(f"R4: некорректные числовые меры {key}: {left}/{right}")
    if set(totals) != {"3nf", "star", "vault", "anchor"} or len(set(totals.values())) != 1:
        errors.append(f"R1: неполные или разные суммы {totals}")
    for name in expected:
        if not counts[name]:
            errors.append(f"Пустая или отсутствующая секция: {name}")
    return counts, errors


if __name__ == "__main__":
    data = sys.stdin.read()
    sys.stdout.write(data)
    counts, errors = check(data)
    if errors:
        print("\n".join(errors), file=sys.stderr)
        raise SystemExit(1)
    print(f"Проверено: {sum(counts.values())} строк, все секции присутствуют", file=sys.stderr)
