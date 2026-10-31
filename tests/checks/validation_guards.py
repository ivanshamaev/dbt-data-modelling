"""Проверки отказа защитных команд на сохранённых корректных артефактах."""
import copy
import csv
import json
import subprocess
import sys
import tempfile
from decimal import Decimal
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def run(label, script, arguments=(), data=None, success=False):
    result = subprocess.run([sys.executable, str(ROOT / 'scripts' / script), *arguments],
                            input=data, text=True, capture_output=True)
    if (result.returncode == 0) != success:
        raise AssertionError(f'{label}: неверный код {result.returncode}: {result.stderr}')
    print(f'{label}: ожидаемый код {result.returncode}')


manifest_path = ROOT / 'docs/live-run/course-final-2026-10-31/scenarios03/manifest.json'
base = json.loads(manifest_path.read_text())
run('Полный независимый граф', 'check_contours.py', [str(manifest_path)], success=True)
with tempfile.TemporaryDirectory() as directory:
    path = Path(directory) / 'manifest.json'
    wrong = copy.deepcopy(base)
    wrong['nodes']['model.retailco.brz_erp__orders']['depends_on']['nodes'].append('model.retailco.raw_erp__orders')
    path.write_text(json.dumps(wrong))
    run('Чужой предок Medallion', 'check_contours.py', [str(path)])
    wrong = copy.deepcopy(base)
    wrong['disabled']['test.hidden'] = [{'resource_type': 'test'}]
    path.write_text(json.dumps(wrong))
    run('Неожиданно отключённый тест', 'check_contours.py', [str(path)])
    path.write_text(json.dumps({'nodes': {}}))
    run('Пустой граф', 'check_contours.py', [str(path)])

report = (ROOT / 'docs/live-run/dbt-audit-2026-10-31/reconcile.log').read_text()
run('Корректные R1–R4', 'check_reconciliation.py', data=report, success=True)
run('FAIL в результате SQL', 'check_reconciliation.py', data=report.replace('\tOK', '\tFAIL', 1))
run('Пустой вывод SQL', 'check_reconciliation.py', data='')
run('Пропущен раздел R4', 'check_reconciliation.py',
    data='\n'.join(line for line in report.splitlines() if not line.startswith('R4_')))


def changed_r4(field, value):
    rows = list(csv.reader(report.splitlines(), delimiter='\t'))
    header = None
    for row in rows:
        if row and row[0] == 'check_name':
            header = row
        elif row and row[0].startswith('R4_'):
            index = header.index(field)
            row[index] = value(row[index])
            return '\n'.join('\t'.join(item) for item in rows)
    raise AssertionError('В исходном артефакте нет R4')


run('R4: OK не скрывает разные меры', 'check_reconciliation.py',
    data=changed_r4('revenue_amt_max', lambda x: str(Decimal(x)+1)))
run('R4: NULL не является числом', 'check_reconciliation.py',
    data=changed_r4('revenue_amt_min', lambda x: 'NULL'))
rows = list(csv.reader(report.splitlines(), delimiter='\t'))
number = 0
for row in rows:
    if row and row[0] == 'R1_kpi1_total_revenue':
        row[2] = str(9007199254740992 + (number == 3))
        number += 1
assert number == 4
run('R1: различие на копейку выше точности float', 'check_reconciliation.py',
    data='\n'.join('\t'.join(row) for row in rows))
print('Все одиннадцать проверок защитных команд пройдены')
