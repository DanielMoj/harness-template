#!/usr/bin/env python3
"""Validate the T-5 inventory against an independent, versioned target list."""

from __future__ import annotations

import collections
import os
import pathlib
import re
import subprocess
import sys
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[2]
TABLE = ROOT / "docs" / "template" / "T5-INVENTAR.md"
TARGET = ROOT / "docs" / "template" / "T5-SOLL.md"


def clean_cell(value: str) -> str:
    value = value.strip()
    if value.startswith("`") and value.endswith("`"):
        return value[1:-1]
    return value


def target_contract() -> tuple[set[str], dict[str, str], dict[str, str]]:
    expected: set[str] = set()
    categories: dict[str, str] = {}
    behaviors: dict[str, str] = {}
    for line in TARGET.read_text(encoding="utf-8").splitlines():
        cells = [clean_cell(cell) for cell in line.strip().strip("|").split("|")]
        if len(cells) == 3 and re.fullmatch(r"[A-Z0-9]+", cells[0]):
            range_match = re.fullmatch(r"(\d{2})-(\d{2})", cells[1])
            if range_match:
                start, end = map(int, range_match.groups())
                categories[cells[0]] = cells[1]
                expected.update(f"T5-{cells[0]}-{number:02d}" for number in range(start, end + 1))
        if len(cells) == 3 and cells[0].startswith("T5-"):
            behaviors[cells[0]] = cells[1]
    return expected, categories, behaviors


def ensure_behavior_results(failures: list[str]) -> tuple[set[str], str | None]:
    configured = os.environ.get("HARNESS_BEHAVIOR_RESULTS")
    cleanup_path: str | None = None
    if configured:
        result_path = configured
    else:
        descriptor, result_path = tempfile.mkstemp(prefix="harness-t5-results.")
        os.close(descriptor)
        cleanup_path = result_path
        environment = os.environ.copy()
        environment["HARNESS_BEHAVIOR_RESULTS"] = result_path
        completed = subprocess.run(
            ["bash", str(ROOT / "tests" / "template" / "test-t5-behavior.sh")],
            cwd=ROOT,
            env=environment,
            check=False,
        )
        if completed.returncode != 0:
            failures.append(f"Verhaltens-T-5 fehlgeschlagen: rc={completed.returncode}")
    path = pathlib.Path(result_path)
    if not path.is_file():
        failures.append(f"Verhaltensergebnisse fehlen: {result_path}")
        return set(), cleanup_path
    return set(path.read_text(encoding="utf-8").splitlines()), cleanup_path


def validate_patch_15(failures: list[str]) -> None:
    # T5-PATCH-15: both halves are checked, not merely one substring.
    orchestrator = (ROOT / "orchestrator" / "orchestrate.sh").read_text(encoding="utf-8")
    if "CONFIG: AUTONOMY=" not in orchestrator:
        failures.append("T5-PATCH-15: CONFIG-Provenienz fehlt")
    for prompt in ("20-plan.md", "30-plan-review.md", "40-build.md", "50-code-review.md", "60-rework.md", "62-rebuild.md"):
        text = (ROOT / "orchestrator" / "prompts" / prompt).read_text(encoding="utf-8")
        if "orchestrator/LESSONS.md" not in text:
            failures.append(f"T5-PATCH-15: LESSONS-Lesepfad fehlt in {prompt}")


def validate_cross_file_rework(failures: list[str]) -> None:
    for prompt in (
        "10-acceptance.md",
        "20-plan.md",
        "30-plan-review.md",
        "40-build.md",
        "45-qa.md",
        "50-code-review.md",
        "60-rework.md",
        "62-rebuild.md",
        "70-arbiter.md",
    ):
        text = (ROOT / "orchestrator" / "prompts" / prompt).read_text(encoding="utf-8")
        if "Kontextmanifest" not in text:
            failures.append(f"L2-N-01: Kontextmanifest fehlt in {prompt}")
    example = (ROOT / "projektierung" / "beispiel" / "README.md").read_text(encoding="utf-8")
    for evidence in ("kein `tolerance`", "Repo-Pfad als `source_url`", "`retrieved`"):
        if evidence not in example:
            failures.append(f"B-19: historische Ankerabweichung nicht dokumentiert: {evidence}")
    readme = (ROOT / "README.md").read_text(encoding="utf-8")
    if "Zielprojekte dürfen diesen gesamten Ordner löschen" not in readme:
        failures.append("B-21: Löschhinweis für docs/template fehlt")
    for old_path in ("docs/BAUPLAN.md", "docs/ABNAHME.md", "docs/T5-INVENTAR.md"):
        if (ROOT / old_path).exists():
            failures.append(f"B-21: alter Template-Dokumentpfad existiert weiter: {old_path}")


def main() -> int:
    failures: list[str] = []
    expected_ids, target_categories, target_behaviors = target_contract()
    if not expected_ids:
        failures.append("T5-SOLL enthält keine auswertbaren ID-Bereiche")

    rows: list[list[str]] = []
    for line_no, line in enumerate(TABLE.read_text(encoding="utf-8").splitlines(), 1):
        if not line.startswith("| T5-"):
            continue
        cells = [clean_cell(cell) for cell in line.strip().strip("|").split("|")]
        if len(cells) != 5:
            failures.append(f"Zeile {line_no}: erwartet 5 Spalten, erhalten {len(cells)}")
            continue
        rows.append(cells)

    actual_ids = [row[0] for row in rows]
    duplicates = sorted(item for item, count in collections.Counter(actual_ids).items() if count > 1)
    for item in duplicates:
        failures.append(f"doppelte ID: {item}")
    missing = sorted(expected_ids - set(actual_ids))
    extra = sorted(set(actual_ids) - expected_ids)
    if missing:
        failures.append(f"Soll-IDs fehlen: {', '.join(missing)}")
    if extra:
        failures.append(f"nicht in T5-SOLL enthaltene IDs: {', '.join(extra)}")

    behavior_results, cleanup_path = ensure_behavior_results(failures)
    counts: collections.Counter[str] = collections.Counter()
    mapped = 0
    behavioral = 0
    omitted = 0
    for item_id, _source, status, locator, evidence in rows:
        category = item_id.split("-")[1]
        counts[category] += 1
        path = ROOT / locator

        if status == "belegt":
            mapped += 1
            if not path.is_file():
                failures.append(f"{item_id}: Fundstelle fehlt: {locator}")
                continue
            if evidence not in path.read_text(encoding="utf-8"):
                failures.append(f"{item_id}: Suchanker fehlt in {locator}: {evidence!r}")
        elif status == "verhalten":
            behavioral += 1
            expected_key = target_behaviors.get(item_id)
            if expected_key is None:
                failures.append(f"{item_id}: kein Verhaltensvertrag in T5-SOLL")
            elif evidence != expected_key:
                failures.append(f"{item_id}: Ergebnis-Schlüssel {evidence!r} statt {expected_key!r}")
            if not path.is_file():
                failures.append(f"{item_id}: ausführender Test fehlt: {locator}")
            if evidence not in behavior_results:
                failures.append(f"{item_id}: Verhalten nicht erfolgreich ausgeführt: {evidence}")
        elif status == "bewusst weggelassen":
            omitted += 1
            if locator != "—":
                failures.append(f"{item_id}: Weglassung darf keine Schein-Fundstelle tragen")
            if len(evidence) < 40:
                failures.append(f"{item_id}: Weglassungsbegruendung ist zu kurz")
        else:
            failures.append(f"{item_id}: unbekannter Status {status!r}")

    validate_patch_15(failures)
    validate_cross_file_rework(failures)

    bauplan = (ROOT / "docs" / "template" / "BAUPLAN.md").read_text(encoding="utf-8")
    for required in (
        "Konstruktionsprinzipien",
        "Rollen (§1)",
        "Phasen (§2)",
        "Verhandlung (§3)",
        "Gates mit Zweck (§4)",
        "Anti-Halluzination (§7a)",
        "Sicherheitsschienen (§5)",
        "Kontexthygiene (§5b)",
        "Betrieb (§6)",
        "Autonomie (Patch v2)",
        "Toolchain (neu gegenüber Demiurg",
        "Lernen und Spur",
    ):
        if required not in bauplan:
            failures.append(f"A9-Prueflistenblock fehlt: {required}")

    if cleanup_path:
        pathlib.Path(cleanup_path).unlink(missing_ok=True)
    if failures:
        for failure in failures:
            print(f"FAIL  {failure}")
        print(f"T-5 FAIL: rows={len(rows)} failures={len(failures)}")
        return 1

    categories = ",".join(f"{name}={counts[name]}" for name in target_categories)
    print(
        f"T-5 PASS: target=versioned rows={len(rows)} static={mapped} "
        f"behavior={behavioral} omitted={omitted} categories={categories} exact-ids=PASS cross-file=PASS"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
