"""Ручной эталон маленького RetailCo; не вычисляется из проверяемых витрин."""

import csv
import sys
from collections import Counter


def expected(phase):
    if phase == "00":
        sales = [("2026-10-10", "shop", 30000), ("2026-10-29", "shop", 5000), ("2026-10-31", "web", 10000)]
        ltv = [("standard", 1, 1, 30000), ("premium", 1, 2, 15000)]
        promo = [("promo", 1, 30000), ("organic", 2, 15000)]
    else:
        first = 28000 if phase == "01" else 30000
        sales = [("2026-10-10", "shop", first), ("2026-10-28", "web", 40000),
                 ("2026-10-29", "shop", 5000), ("2026-10-31", "shop", 2000)]
        if phase != "03":
            sales.append(("2026-10-31", "web", 10000))
        ltv = [("standard", 1, 2, first + 40000)]
        if phase == "01":
            ltv += [("premium", 1, 2, 15000), ("vip", 1, 1, 2000)]
        else:
            ltv += [("premium", 2, 2 if phase == "03" else 3, 7000 if phase == "03" else 17000)]
        promo = [("promo", 2, first + 40000), ("organic", 2 if phase == "03" else 3, 7000 if phase == "03" else 17000)]
    result = []
    for contour in ("inmon", "kimball", "vault", "anchor", "medallion"):
        result.extend((contour, "sales_daily", d, ch, "0", "1", str(amt)) for d, ch, amt in sales)
        result.extend((contour, "customer_ltv", seg, "", str(c), str(o), str(a)) for seg, c, o, a in ltv)
        result.extend((contour, "promo_effect", kind, "", "0", str(o), str(a)) for kind, o, a in promo)
    return Counter(result)


if __name__ == "__main__":
    phase = sys.argv[1]
    if phase not in {"00", "01", "02", "03"}:
        raise SystemExit("Неизвестная фаза")
    rows = list(csv.reader(sys.stdin, delimiter="\t"))
    if not rows or rows[0] != ["contour", "mart", "dim1", "dim2", "customers", "orders", "amount"]:
        raise SystemExit("Нет ожидаемого заголовка SQL")
    actual = Counter(tuple(row) for row in rows[1:])
    wanted = expected(phase)
    if actual != wanted:
        print("Недостающие/неверные строки:", wanted - actual)
        print("Лишние/неверные строки:", actual - wanted)
        raise SystemExit(1)
    print(f"Фаза {phase}: все 15 витрин совпали с ручным эталоном, {sum(actual.values())} строк")
