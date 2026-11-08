"""Проверка имён Anchor и фактов Kimball и сохранности графа при миграции."""

from __future__ import annotations

import argparse
from collections import Counter
import json
from pathlib import Path
import re

LEGACY_PREFIXES = {
    "a_": "anc_", "ac_": "attr_", "t_": "tie_", "kn_": "knot_",
    "wv_": "latest_anc_", "am_": "agg_anc_", "fct_": "fact_",
}


def rename_legacy(value: str) -> str:
    # Короткие SQL-алиасы сохраняют смысл и не являются именами моделей.
    value = re.sub(r"\b(wv_o|wv_l)\b", lambda match: {"wv_o": "o", "wv_l": "ol"}[match.group()], value)
    value = re.sub(r"\bfct\b", "fact", value)
    value = re.sub(r"(?<=['\"])wv(?=['\"])", "latest", value)
    return re.sub(r"\b(ac_|a_|t_|kn_|wv_|am_|fct_)", lambda match: LEGACY_PREFIXES[match.group()], value)


def model_signatures(manifest: dict, legacy: bool = False) -> dict:
    result = {}
    for node in manifest["nodes"].values():
        if node["resource_type"] != "model":
            continue
        signature = {
            "name": node["name"], "file": node["original_file_path"],
            "code": node["raw_code"], "relation": node["relation_name"],
            "materialized": node["config"]["materialized"],
            "dependencies": sorted(node["depends_on"]["nodes"]),
        }
        if legacy:
            signature = json.loads(rename_legacy(json.dumps(signature)))
            signature["dependencies"].sort()
        result[signature["name"]] = signature
    return result


def test_signatures(manifest: dict, legacy: bool = False) -> Counter:
    result = []
    for node in manifest["nodes"].values():
        if node["resource_type"] != "test":
            continue
        # Хеш служебного alias generic-теста зависит от переименованной модели.
        code = re.sub(r'\{\{\s*config\(alias="[^"]+"\)\s*\}\}', "", node["raw_code"])
        signature = {
            "file": node["original_file_path"], "code": code,
            "dependencies": sorted(node["depends_on"]["nodes"]),
            "metadata": node.get("test_metadata", {}), "enabled": node["config"]["enabled"],
        }
        if legacy:
            signature = json.loads(rename_legacy(json.dumps(signature)))
            signature["dependencies"].sort()
        result.append(json.dumps(signature, sort_keys=True))
    return Counter(result)


def check(manifest: dict, baseline: dict | None = None) -> dict:
    models = [node for node in manifest["nodes"].values() if node["resource_type"] == "model"]
    tests = [node for node in manifest["nodes"].values() if node["resource_type"] == "test"]
    core = [node for node in models if node["original_file_path"].startswith("models/anchor/core/")]
    families = Counter(node["name"].split("_", 1)[0] for node in core)
    if families != Counter({"anc": 5, "attr": 11, "tie": 4, "knot": 4, "latest": 3}):
        raise ValueError(f"Неожиданный состав Anchor-ядра: {dict(families)}")
    marts = [node for node in models if node["original_file_path"].startswith("models/anchor/marts/")]
    if len(marts) != 3 or any(not node["name"].startswith("agg_anc_") for node in marts):
        raise ValueError("Агрегаты Anchor должны использовать agg_anc_")
    facts = [node for node in models if node["name"].startswith("fact_")]
    if len(facts) != 6 or any(not node["original_file_path"].startswith("models/kimball/star/") for node in facts):
        raise ValueError("Ожидаются шесть фактов Kimball с префиксом fact_")
    for node in manifest["nodes"].values():
        for dependency in node["depends_on"]["nodes"]:
            if re.match(r"model\.retailco\.(ac_|a_|t_|kn_|wv_|am_|fct_)", dependency):
                raise ValueError(f"Осталась зависимость со старым именем: {dependency}")
    if baseline is not None:
        if model_signatures(baseline, True) != model_signatures(manifest):
            raise ValueError("Изменились SQL, материализация или зависимости моделей помимо имён")
        if test_signatures(baseline, True) != test_signatures(manifest):
            raise ValueError("Изменились договоры тестов помимо имён моделей")
    return {
        "result": "PASS", "models": len(models), "tests": len(tests),
        "anchor_models": sum(node["original_file_path"].startswith("models/anchor/") for node in models),
        "renamed_models": sum(
            rename_legacy(node["name"]) != node["name"]
            for node in (baseline or manifest)["nodes"].values() if node["resource_type"] == "model"
        ),
        "anchor_core_families": dict(families), "anchor_aggregates": len(marts),
        "kimball_facts": len(facts),
        "baseline_compared": baseline is not None,
        "normalized_model_sql_and_dependencies_equal": baseline is not None,
        "normalized_test_contracts_equal": baseline is not None,
        "dbt_core": manifest["metadata"]["dbt_version"], "database_execution": False,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path, help="Manifest после чистого dbt parse")
    parser.add_argument("--baseline", type=Path, help="Manifest до переименования")
    parser.add_argument("--output", type=Path, help="Файл JSON с результатом")
    args = parser.parse_args()
    baseline = json.loads(args.baseline.read_text()) if args.baseline else None
    result = check(json.loads(args.manifest.read_text()), baseline)
    text = json.dumps(result, ensure_ascii=False, indent=2) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text)
    print(text, end="")


if __name__ == "__main__":
    main()
