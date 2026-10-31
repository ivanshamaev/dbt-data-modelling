"""Проверка явных числовых ожиданий для малой сценарной истории."""
import csv
import sys
from decimal import Decimal

rows = list(csv.reader(sys.stdin, delimiter="\t"))
if not rows or rows[0] != ["check_name", "actual", "expected"]:
    raise SystemExit("Нет заголовка проверок истории")
if len(rows) != 17 or len({row[0] for row in rows[1:]}) != 16:
    raise SystemExit("Ожидались ровно 16 разных проверок истории")
for name, actual, expected in rows[1:]:
    if actual == "NULL" or Decimal(actual) != Decimal(expected):
        raise SystemExit(f"{name}: получили {actual}, ожидалось {expected}")
print("История: 16 проверок пройдены, включая same-day A→B→A, PIT и прежнее знание Anchor")
