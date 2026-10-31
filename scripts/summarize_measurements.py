"""Сводка семплов Docker во время последовательных сборок пяти контуров."""
import csv
import json
import statistics
import sys
from pathlib import Path

from resource_inventory import size_bytes


def samples(folder, names, start=None, end=None):
    result = []
    with (folder / "samples.tsv").open() as handle:
        for at, filename in csv.reader(handle, delimiter="\t"):
            moment = int(at)
            if start is not None and not start <= moment <= end:
                continue
            rows = [json.loads(line) for line in (folder / filename).read_text().splitlines()]
            if {row["Name"] for row in rows} != names or len(rows) != len(names):
                raise ValueError(f"Неполный семпл {folder / filename}")
            cpu = sum(float(row["CPUPerc"].rstrip("%")) / 100 for row in rows)
            ram = sum(size_bytes(row["MemUsage"].split("/")[0].strip()) for row in rows)
            result.append((cpu, ram))
    if not result:
        raise ValueError(f"Нет семплов в {folder}")
    return {"samples": len(result), "cpu_mean_cores": statistics.mean(x[0] for x in result),
            "cpu_peak_cores": max(x[0] for x in result), "ram_peak_mib": max(x[1] for x in result) / 1024**2}


def main(folder):
    root = Path(folder)
    names = set((root / "container-names.txt").read_text().splitlines())
    if len(names) < 5:
        raise ValueError("Нет пяти основных сервисов стенда")
    report = {}
    for contour in ("inmon", "kimball", "vault", "anchor", "medallion"):
        path = root / contour
        start = int((path / "start-us.txt").read_text())
        end = int((path / "end-us.txt").read_text())
        run = json.loads((path / "run_results.json").read_text())
        if any(item["status"] not in {"success", "pass"} for item in run["results"]):
            raise ValueError(f"Неуспешная сборка {contour}")
        values = samples(path, names, start, end)
        values["idle"] = samples(path / "idle", names)
        values["wall_seconds"] = (end - start) / 1_000_000
        values["nodes"] = len(run["results"])
        values["models"] = sum(item["unique_id"].startswith("model.") for item in run["results"])
        values["tests"] = sum(item["unique_id"].startswith("test.") for item in run["results"])
        report[contour] = values
    (root / "measurements.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print("| Контур | Сборка, с | Модели / тесты с предками | Семплы | CPU, среднее ядер | CPU, максимум ядер | RAM, максимум MiB | CPU до сборки, ядра |")
    print("|---|---:|---:|---:|---:|---:|---:|---:|")
    for key, value in report.items():
        print(f"| {key} | {value['wall_seconds']:.2f} | {value['models']} / {value['tests']} | {value['samples']} | {value['cpu_mean_cores']:.2f} | {value['cpu_peak_cores']:.2f} | {value['ram_peak_mib']:.1f} | {value['idle']['cpu_mean_cores']:.2f} |")
    print("\nОдин повтор каждой сборки на неизменном источнике; это не медианы build.")
    print("CPU/RAM — сумма контейнеров стенда во время одной активной сборки, включая фоновые работы.")
    print("CPU: 100% Docker = одно ядро; среднее — по семплам. RAM — Docker CLI без inactive file cache.")
    print("Общий bronze входит в команды первых четырёх контуров. Порядок фиксирован; сброса кэшей нет.")


if __name__ == "__main__":
    main(sys.argv[1])
