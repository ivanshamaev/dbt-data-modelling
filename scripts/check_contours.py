"""Проверка фактического графа dbt; запуск после чистого parse."""

import collections
import json
import sys
from pathlib import Path


def check(manifest):
    nodes = manifest["nodes"]
    models = {key: node for key, node in nodes.items() if node["resource_type"] == "model"}
    contours = {"inmon", "kimball", "vault", "anchor", "medallion"}
    known = set(nodes) | set(manifest.get("sources", {}))
    errors = []
    counts = collections.Counter()
    relations = collections.defaultdict(list)

    def contour(node):
        return Path(node["original_file_path"]).parts[1]

    for key, node in nodes.items():
        if node["resource_type"] not in {"model", "test"}:
            continue
        if not node["config"].get("enabled", True):
            errors.append(f"Неожиданно отключён узел: {key}")
        for dependency in node["depends_on"]["nodes"]:
            if dependency not in known:
                errors.append(f"Отсутствующая зависимость: {key} → {dependency}")
    for key, variants in manifest.get("disabled", {}).items():
        if any(node["resource_type"] in {"model", "test"} for node in variants):
            errors.append(f"Отключён узел: {key}")
    for key, node in models.items():
        own = contour(node)
        counts[own] += 1
        relations[node["relation_name"]].append(key)
        allowed = {own} if own in {"bronze", "medallion"} else {own, "bronze"}
        for dependency in node["depends_on"]["nodes"]:
            if dependency in models and contour(models[dependency]) not in allowed:
                errors.append(f"Чужой контур: {key} → {dependency}")
    for name in contours | {"bronze"}:
        if counts[name] == 0:
            errors.append(f"Нет моделей контура: {name}")
    for relation, owners in relations.items():
        if len(owners) != 1:
            errors.append(f"Коллизия физического имени {relation}: {owners}")
    return counts, errors


if __name__ == "__main__":
    counts, errors = check(json.loads(Path(sys.argv[1]).read_text()))
    for name, count in sorted(counts.items()):
        print(f"Контур {name}: {count} моделей")
    if errors:
        print("\n".join(errors), file=sys.stderr)
        raise SystemExit(1)
    print("OK: граф полный, модели контуров независимы")
