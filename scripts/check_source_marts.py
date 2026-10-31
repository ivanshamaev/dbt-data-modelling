"""Сверяет 15 витрин с независимым эталоном PostgreSQL, включая зерно и количества."""
import csv
import sys
from collections import Counter

header = ['contour', 'mart', 'dim1', 'dim2', 'customers', 'orders', 'amount']
rows = list(csv.reader(sys.stdin, delimiter='\t'))
if not rows or rows[0] != header:
    raise SystemExit('Нет ожидаемого заголовка эталона')
rows = [tuple(row) for row in rows if row != header]
if any(len(row) != 7 for row in rows):
    raise SystemExit('Повреждённая строка сверки')
source = [row[1:] for row in rows if row[0] == 'source']
if {row[0] for row in source} != {'sales_daily', 'customer_ltv', 'promo_effect'}:
    raise SystemExit('Неполный эталон источника')
if len(source) != len(set(row[:3] for row in source)):
    raise SystemExit('Неуникальное зерно эталона')
expected = Counter((contour, *row) for contour in ('inmon', 'kimball', 'vault', 'anchor', 'medallion') for row in source)
actual = Counter(row for row in rows if row[0] != 'source')
if actual != expected:
    print('Недостающие/неверные строки:', list((expected-actual).items())[:20])
    print('Лишние/неверные строки:', list((actual-expected).items())[:20])
    raise SystemExit(1)
print(f'Источник и 15 витрин совпали: {len(source)} исходных групп, {sum(actual.values())} строк контуров')
