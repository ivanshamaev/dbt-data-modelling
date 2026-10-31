"""Малые контрпримеры для настоящих CASE-предикатов R4 из tests/reconcile.sql.

Режим sql печатает read-only запрос StarRocks; expected — ручной эталон TSV.
Проверяется реальный SQL проверки, а не отдельно написанная копия новой логики.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONTOURS = ('inmon', 'kimball', 'vault', 'anchor', 'medallion')
MARTS = ('sales_daily', 'customer_ltv', 'promo_effect')
CASES = ('valid', 'zero_amount', 'duplicate', 'missing', 'null_orders',
         'null_amount', 'null_customers', 'different_amount')


def expected(case, mart):
    return 'OK' if (case in {'valid', 'zero_amount'}
                    or (case == 'null_customers' and mart != 'customer_ltv')) else 'FAIL'


if sys.argv[1] == 'expected':
    print('case_name\tmart\tstatus')
    for case in sorted(CASES):
        for mart in sorted(MARTS):
            print(case, mart, expected(case, mart), sep='\t')
elif sys.argv[1] == 'sql':
    rows = []
    for case in CASES:
        contours = CONTOURS[:-1] if case == 'missing' else CONTOURS
        if case == 'duplicate':
            contours = (*contours, 'inmon')
        for index, contour in enumerate(contours):
            orders = 'NULL' if case == 'null_orders' and index == 0 else '1'
            customers = 'NULL' if case == 'null_customers' and index == 0 else '1'
            amount = ('NULL' if case == 'null_amount' and index == 0 else
                      '0' if case == 'zero_amount' else
                      '10001' if case == 'different_amount' and index == 0 else '10000')
            rows.append(f"select '{case}' as case_name, '{contour}' as contour, "
                        f"cast({orders} as bigint) as orders_cnt, "
                        f"cast({customers} as bigint) as customers_cnt, "
                        f"cast({amount} as bigint) as revenue_amt, "
                        f"cast({amount} as bigint) as ltv_amt")
    source = (ROOT / 'tests/reconcile.sql').read_text()
    queries = []
    for mart in MARTS:
        match = re.search(r"select\s+'R4_" + mart + r"'.*?(case\s+when.*?end) as status",
                          source, re.S)
        assert match is not None, mart
        queries.append(f"select case_name, '{mart}' as mart, {match[1]} as status "
                       "from samples group by case_name")
    print('with samples as (\n' + '\nunion all\n'.join(rows) + '\n)\n'
          + '\nunion all\n'.join(queries) + '\norder by case_name, mart;')
else:
    raise SystemExit('Режим: sql или expected')
