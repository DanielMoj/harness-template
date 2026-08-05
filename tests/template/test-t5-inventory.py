#!/usr/bin/env python3
"""Validiert die T-5-Nachweistabelle ohne Zugriff auf ein Quell-Repo."""

from __future__ import annotations

import collections
import pathlib
import sys


ROOT = pathlib.Path(__file__).resolve().parents[2]
TABLE = ROOT / "docs" / "T5-INVENTAR.md"


def clean_cell(value: str) -> str:
    value = value.strip()
    if value.startswith("`") and value.endswith("`"):
        return value[1:-1]
    return value


def main() -> int:
    failures: list[str] = []
    rows: list[list[str]] = []
    for line_no, line in enumerate(TABLE.read_text(encoding="utf-8").splitlines(), 1):
        if not line.startswith("| T5-"):
            continue
        cells = [clean_cell(cell) for cell in line.strip().strip("|").split("|")]
        if len(cells) != 5:
            failures.append(f"Zeile {line_no}: erwartet 5 Spalten, erhalten {len(cells)}")
            continue
        rows.append(cells)

    seen: set[str] = set()
    counts: collections.Counter[str] = collections.Counter()
    mapped = 0
    omitted = 0
    for item_id, _source, status, locator, evidence in rows:
        if item_id in seen:
            failures.append(f"doppelte ID: {item_id}")
        seen.add(item_id)
        category = item_id.split("-")[1]
        counts[category] += 1

        if status == "belegt":
            mapped += 1
            path = ROOT / locator
            if not path.is_file():
                failures.append(f"{item_id}: Fundstelle fehlt: {locator}")
                continue
            if evidence not in path.read_text(encoding="utf-8"):
                failures.append(f"{item_id}: Suchanker fehlt in {locator}: {evidence!r}")
        elif status == "bewusst weggelassen":
            omitted += 1
            if locator != "—":
                failures.append(f"{item_id}: Weglassung darf keine Schein-Fundstelle tragen")
            if len(evidence) < 40:
                failures.append(f"{item_id}: Weglassungsbegruendung ist zu kurz")
        else:
            failures.append(f"{item_id}: unbekannter Status {status!r}")

    minimum = {"ORCH": 12, "AGENT": 5, "D12": 64, "PATCH": 15, "D14": 7, "NEW": 9}
    for category, expected in minimum.items():
        if counts[category] < expected:
            failures.append(
                f"Kategorie {category}: {counts[category]} Zeilen, mindestens {expected} erwartet"
            )

    bauplan = (ROOT / "docs" / "BAUPLAN.md").read_text(encoding="utf-8")
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

    if failures:
        for failure in failures:
            print(f"FAIL  {failure}")
        print(f"T-5 FAIL: rows={len(rows)} failures={len(failures)}")
        return 1

    categories = ",".join(f"{name}={counts[name]}" for name in minimum)
    print(
        f"T-5 PASS: rows={len(rows)} mapped={mapped} omitted={omitted} "
        f"categories={categories} locators=PASS"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
