"""Строгая инвентаризация по manifest; размеры файлов и сохранённых S3-префиксов."""
import collections
import csv
import json
import re
import sys
from pathlib import Path


def read_manifest(path):
    nodes = json.loads(Path(path).read_text())["nodes"]
    models = {key: node for key, node in nodes.items() if node["resource_type"] == "model"}
    for node in models.values():
        if node["schema"] not in {
            "analytics", "iceberg.bronze", "iceberg.inmon_stage", "iceberg.inmon_core",
            "iceberg.inmon_marts", "iceberg.kimball_stage", "iceberg.vault_stage",
            "iceberg.vault_core", "iceberg.vault_marts", "iceberg.anchor_stage",
            "iceberg.anchor_core", "iceberg.anchor_marts", "iceberg.med_bronze",
            "iceberg.med_silver", "iceberg.med_gold",
        }:
            raise SystemExit(f"Измерение требует основного профиля без fixture: {node['schema']}")
    return nodes, models


def owner(node):
    return Path(node["original_file_path"]).parts[1]


def physical(models):
    return [node for node in models.values() if node["config"]["materialized"] in {"table", "incremental"}]


def relation(node, suffix=""):
    parts = node["schema"].split(".") + [node["alias"] + suffix]
    return ".".join("`" + part.replace("`", "``") + "`" for part in parts)


def emit(manifest):
    _, models = read_manifest(manifest)
    for node in physical(models):
        kind = "external" if node["schema"].startswith("iceberg.") else "internal"
        print("\t".join((node["name"], kind, relation(node))))


def emit_sql(manifest):
    _, models = read_manifest(manifest)
    for node in physical(models):
        if not node["schema"].startswith("iceberg."):
            continue
        print(f"SELECT '{node['name']}',count(*),coalesce(sum(file_size_in_bytes),0) FROM {relation(node, '$files')};")


def size_bytes(value):
    match = re.fullmatch(r"([\d.]+)\s*(B|KB|MB|GB|TB|KiB|MiB|GiB|TiB)", value)
    if not match:
        raise ValueError(f"Неизвестная единица размера: {value!r}")
    units = {"B": 0, "KB": 1, "MB": 2, "GB": 3, "TB": 4,
             "KiB": 1, "MiB": 2, "GiB": 3, "TiB": 4}
    return round(float(match[1]) * 1024 ** units[match[2]])


def summarize(manifest, output):
    out = Path(output)
    nodes, models = read_manifest(manifest)
    metrics = collections.defaultdict(lambda: collections.Counter())
    for node in models.values():
        metrics[owner(node)]["models"] += 1
        metrics[owner(node)]["views"] += node["config"]["materialized"] == "view"
    for node in nodes.values():
        if node["resource_type"] != "test":
            continue
        owners = {owner(models[dep]) for dep in node["depends_on"]["nodes"] if dep in models} - {"bronze"}
        label = next(iter(owners)) if len(owners) == 1 else "bronze" if not owners else "cross_contour"
        metrics[label]["tests"] += 1

    current = {}
    with (out / "current-files.tsv").open() as handle:
        for name, files_count, size in csv.reader(handle, delimiter="\t"):
            if name in current:
                raise ValueError(f"Повтор размера модели: {name}")
            current[name] = (int(files_count), int(size))
    locations = {}
    table_details = []
    for node in physical(models):
        name, contour = node["name"], owner(node)
        item = {"model": name, "contour": contour, "relation": relation(node)}
        if node["schema"].startswith("iceberg."):
            files_count, size = current.pop(name)
            ddl = (out / "ddl" / f"{name}.tsv").read_text()
            found = set(re.findall(r"s3://([^/\s]+)/([0-9a-f-]{36})", ddl))
            if len(found) != 1:
                raise ValueError(f"Не определена единственная S3-локация {name}: {found}")
            bucket, prefix = found.pop()
            if bucket != (out / "bucket.txt").read_text().strip():
                raise ValueError(f"Неожиданный bucket {bucket} у {name}")
            if prefix in locations:
                raise ValueError(f"S3-локация общая у нескольких моделей: {prefix}")
            locations[prefix] = (contour, item)
            metrics[contour]["iceberg_current_bytes"] += size
            metrics[contour]["iceberg_current_files"] += files_count
            item.update(kind="iceberg", current_bytes=size, current_files=files_count, retained_bytes=0)
        else:
            with (out / "internal" / f"{name}.tsv").open() as handle:
                rows = list(csv.DictReader(handle, delimiter="\t"))
            totals = [row for row in rows if row.get("IndexName") == "Total" or row.get("TableName") == "Total"]
            if len(totals) != 1:
                raise ValueError(f"Нет единственной строки Total у {name}")
            size = size_bytes(totals[0]["Size"])
            metrics[contour]["internal_reported_bytes"] += size
            item.update(kind="internal", reported_bytes=size)
        table_details.append(item)
    if current:
        raise ValueError(f"Лишние строки размеров: {sorted(current)}")

    all_objects = all_bytes = unmapped_bytes = 0
    with (out / "s3-objects.tsv").open() as handle:
        for key, size_text in csv.reader(handle, delimiter="\t"):
            size = int(size_text)
            all_objects += 1
            all_bytes += size
            prefix = key.split("/", 1)[0]
            if prefix in locations:
                contour, item = locations[prefix]
                metrics[contour]["iceberg_retained_prefix_bytes"] += size
                item["retained_bytes"] += size
            else:
                unmapped_bytes += size
    if not all_objects:
        raise ValueError("Пустая инвентаризация S3")
    for _, item in locations.values():
        if item["retained_bytes"] < item["current_bytes"]:
            raise ValueError(f"Префикс меньше текущих файлов: {item['model']}")

    results = json.loads((out / "run_results.json").read_text())
    if any(row["status"] not in {"success", "pass"} for row in results["results"]):
        raise ValueError("Последний run_results содержит неуспешные узлы")
    for row in results["results"]:
        node = models.get(row["unique_id"])
        if node:
            metrics[owner(node)]["last_run_models"] += 1
            metrics[owner(node)]["last_run_model_seconds"] += row["execution_time"]
    report = {"contours": dict(metrics), "tables": table_details,
              "bucket_objects": all_objects, "bucket_bytes": all_bytes,
              "unmapped_prefix_bytes": unmapped_bytes,
              "run_generated_at": results.get("metadata", {}).get("generated_at")}
    (out / "inventory.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print("| Контур | Модели | Тесты | Текущие Iceberg-файлы, MiB | Все объекты активных префиксов, MiB | Internal, MiB |")
    print("|---|---:|---:|---:|---:|---:|")
    for contour, values in sorted(metrics.items()):
        mib = lambda key: f"{values[key] / 1024**2:.2f}"
        print(f"| {contour} | {values['models']} | {values['tests']} | {mib('iceberg_current_bytes')} | {mib('iceberg_retained_prefix_bytes')} | {mib('internal_reported_bytes')} |")
    print("\nОбщая bronze учитывается отдельно. Views не имеют собственных файлов данных.")
    print("S3-префиксы включают старые snapshots и метаданные; немаппированные префиксы не приписаны контурам.")
    print("Internal получен из SHOW DATA, с округлением вывода; source включает индексы PostgreSQL.")
    print("Времена последнего запуска в JSON относятся только к реально выбранным моделям и не являются wall-clock всей сборки.")


if __name__ == "__main__":
    command, manifest = sys.argv[1:3]
    if command == "list":
        emit(manifest)
    elif command == "sql":
        emit_sql(manifest)
    elif command == "summary":
        summarize(manifest, sys.argv[3])
    else:
        raise SystemExit(f"Неизвестная команда: {command}")
