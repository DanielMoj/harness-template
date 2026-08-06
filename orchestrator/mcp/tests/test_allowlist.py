#!/usr/bin/env python3
"""test_allowlist.py — Abnahme der Allowlist und der grep-Pfadgrenzen.

Die statischen Regeln werden ohne Ausfuehrung geprüft. Eine kleine, klar als
Fixture markierte Temp-Struktur führt zusätzlich die rekursiven grep-Fälle
aus. Dazu eine Strukturprobe direkt auf den Regexen, die den
'..'-Pre-Filter bewusst umgeht: '..'-Traversal, absolute Pfade und
Options-Schmuggel ('-'-beginnende Tokens in Pfad-/Muster-Position) duerfen
strukturell KEIN Muster treffen KOENNEN.

Aufruf: python3 orchestrator/mcp/tests/test_allowlist.py
(Exit 0 = alles gruen)
"""

import os
import re
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import server  # noqa: E402  (Import nach sys.path-Erweiterung)

# Muessen matchen — realistische Analyse-Befehle fuer den Orchestrator-Apparat.
MUESSEN_MATCHEN = [
    "git status",
    "git status --short",
    "git log --oneline",
    "git log --oneline -8",
    "git log --oneline -120",
    "git diff",
    "git diff --stat",
    "git diff docs/07-roadmap.md",
    "git diff orchestrator/LESSONS.md",
    "git show 43146bd",
    "git show 43146bd --stat",
    "wc -l orchestrator/logs/M1-40-build-r1-20260715-1.log",
    "wc -l AGENTS.md",
    "tail -n 200 orchestrator/logs/M3-50-code-review-r3-20260717-025110.log",
    "tail -n 60 orchestrator/state/M1/gate-tests.log",
    "tail -n 5000 orchestrator/state/M3/gate-mutgate.log",
    "grep -rn ESCALATE orchestrator/logs",
    "grep -rn index.lock orchestrator/logs",
    "grep -n kappa docs/02-simulation-port.md",
    "grep -n REWORK orchestrator/handoff/M3/verdict-code.json",
]

# Muessen abgelehnt werden. Der Kanal ist rein lesend: keine Laeufe, kein rm,
# kein npm/npx, kein freies git — und die klassischen Umgehungen.
MUESSEN_ABLEHNEN = [
    "rm -rf .",
    "rm -rf .stryker-tmp",                  # selbst Aufraeumen ist Betreiber-Sache
    "bash start.sh",
    "bash orchestrate.sh",
    "npm test",
    "npx vitest run",
    "python3 tools/pipeline/build_all.py",
    "git push",
    "git commit -m x",                      # Schreiben nur via lessons_schreiben
    "git add -A",
    "git status; git log",
    "git log --oneline -1000",              # Zaehler auf 3 Stellen gedeckelt
    "git diff --stat orchestrator extra",   # nur EIN Pfad-Token
    "tail -n 40 ../anderes-repo/AGENTS.md",
    "tail -n 40 /etc/passwd",
    "tail -n 40 .env",
    "git diff orchestrator/config.env",     # .env-Filter: schuetzt den OpenRouter-Key
    "wc -l /etc/passwd",
    "wc -l --files0-from=liste.txt",
    "grep -rn -e orchestrator/logs",        # Muster darf nicht mit '-' beginnen
    "grep -rn muster /etc",
    "grep -Ern muster orchestrator",        # nur -n|-rn
    "cat AGENTS.md",                        # Lesen geht ueber lies()
    "echo hallo",                           # jeder nicht gelistete Befehl
]

# Strukturprobe direkt auf den Regexen (Pre-Filter bewusst umgangen):
# Traversal, absolute Pfade und '-'-Schmuggel duerfen KEIN Muster treffen.
STRUKTUR_BOESE = [
    "tail -n 40 ..",
    "tail -n 40 orchestrator/../..",
    "tail -n 40 orchestrator/..",
    "tail -n 40 a../b",
    "wc -l ..",
    "wc -l /etc/passwd",
    "wc -l C:/Users",
    "wc -l -",
    "wc -l --files0-from=x",
    "tail -n 40 /etc/passwd",
    "tail -n 40 -",
    "git diff /etc/passwd",
    "git diff ../andere-repo/datei",
    "grep -n muster /etc/passwd",
    "grep -n muster ..",
    "grep -n -e orchestrator/logs",
    "grep -n a orchestrator",               # Muster unter Mindestlaenge 2
]


def main():
    faelle = []

    def fall(beschreibung, bestanden):
        faelle.append(bestanden)
        print(f"{'OK  ' if bestanden else 'FAIL'}  {beschreibung}")

    for cmd in MUESSEN_MATCHEN:
        ok, wert = server.pruefe_befehl(cmd)
        fall(f"match:  {cmd}", ok and isinstance(wert, int))

    for cmd in MUESSEN_ABLEHNEN:
        ok, _ = server.pruefe_befehl(cmd)
        fall(f"reject: {cmd}", not ok)

    for boese in STRUKTUR_BOESE:
        treffer = [m for m, _t in server.ALLOWLIST if re.fullmatch(m, boese)]
        fall(f"strukturell kein Regex-Treffer: {boese}", not treffer)

    original_repo = server.REPO
    with tempfile.TemporaryDirectory(prefix="harness-mcp-allowlist-") as temp_repo, \
            tempfile.TemporaryDirectory(prefix="harness-mcp-outside-") as temp_outside:
        server.REPO = temp_repo
        os.makedirs(os.path.join(temp_repo, "orchestrator", "logs"))
        os.makedirs(os.path.join(temp_repo, "orchestrator", "state"))
        os.makedirs(os.path.join(temp_repo, "orchestrator", "handoff"))
        os.makedirs(os.path.join(temp_repo, "docs"))
        os.makedirs(os.path.join(temp_repo, "src"))
        with open(os.path.join(temp_repo, "orchestrator", "config.env"), "w", encoding="utf-8") as datei:
            datei.write("OPENROUTER_API_KEY=sk-fixture-MUST-NOT-LEAK\n")
        with open(os.path.join(temp_repo, "orchestrator", "secrets.env"), "w", encoding="utf-8") as datei:
            datei.write("OPENROUTER_API_KEY=sk-fixture-MUST-NOT-LEAK\n")
        with open(os.path.join(temp_repo, "orchestrator", "logs", "probe.env"), "w", encoding="utf-8") as datei:
            datei.write("API=sk-fixture-MUST-NOT-LEAK\n")
        with open(os.path.join(temp_repo, "orchestrator", "logs", "safe.log"), "w", encoding="utf-8") as datei:
            datei.write("ordinary log line\n")
        outside_file = os.path.join(temp_outside, "outside.txt")
        with open(outside_file, "w", encoding="utf-8") as datei:
            datei.write("outside fixture must not be readable\n")
        symlink_faelle = (
            ("secrets.env", "src/notiz", "../orchestrator/secrets.env"),
            ("config.env", "src/konfig", "../orchestrator/config.env"),
            ("Repo-Aussengrenze", "src/aussen", outside_file),
        )
        for _ziel, link, quelle in symlink_faelle:
            os.symlink(quelle, os.path.join(temp_repo, link))

        antwort = server.befehl("grep -rn API orchestrator")
        fall(
            "rekursiver grep auf orchestrator-Wurzel gibt config.env nicht heraus",
            "sk-fixture-MUST-NOT-LEAK" not in antwort and antwort.startswith("abgelehnt:"),
        )
        antwort = server.befehl("grep -rn API orchestrator/logs")
        fall(
            "rekursiver grep erzwingt --exclude=*.env",
            "sk-fixture-MUST-NOT-LEAK" not in antwort and antwort.startswith("Exit-Code: 1"),
        )
        for befehlsanfang in ("tail -n 40", "wc -l", "git diff"):
            for ziel, link, _quelle in symlink_faelle:
                antwort = server.befehl(f"{befehlsanfang} {link}")
                fall(
                    f"{befehlsanfang} lehnt Symlink auf {ziel} ab",
                    antwort.startswith("abgelehnt:"),
                )
    server.REPO = original_repo

    result_file = os.environ.get("HARNESS_BEHAVIOR_RESULTS")
    if result_file and all(faelle):
        with open(result_file, "a", encoding="utf-8") as datei:
            datei.write("mcp-allowlist\n")

    print(f"\ntest_allowlist: {sum(faelle)}/{len(faelle)} OK")
    return 0 if all(faelle) else 1


if __name__ == "__main__":
    sys.exit(main())
