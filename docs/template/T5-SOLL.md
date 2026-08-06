# T‑5 — versionierte Sollliste

Diese Liste wurde für Rework 1 einmalig aus `docs/12-autonomer-bau.md`,
`docs/14-verifikation.md`, dem Patch-v2-README, dem damaligen
Demiurg-Orchestrator und `AGENTS.md` abgeleitet. Die Quell-Repositories sind
keine Laufzeitabhängigkeit des Templates. Änderungen an dieser Sollmenge
benötigen eine fachliche Begründung; das Prüfskript vergleicht die
Inventar-IDs exakt mit den hier festgelegten Bereichen.

| Kategorie | ID-Bereich | Ableitung |
|---|---:|---|
| ORCH | 01-12 | Funktionsfläche des extrahierten Orchestrators: Zeit/Log, Fehler, STOP, Status, Prompt, Modellaufruf, Territorium, Assets, Verdict, Marker/Commit, Eskalation/Schleife. |
| AGENT | 01-05 | Pflichtlektüre, Rollen/Territorien, Integrität/Handoff sowie zwei bewusst projektspezifische Weglassungen. |
| D12 | 01-64 | Konstruktionsprinzipien, Rollen, Phasen, Verhandlung, Gates, Sicherheit, Kontext, Betrieb und Anti-Halluzination aus docs/12. |
| PATCH | 01-15 | Retry, Lock, Notify, Leiter, Graph, QA-Park, Findings, Mutgate, LESSONS und CONFIG aus Patch v2. |
| D14 | 01-07 | Verifikationsstufen V0–V7 und Anker-/ADR-Integrität aus docs/14. |
| NEW | 01-09 | Neue Template-Verträge für Gate-Runner, Status, Toolchain, Projektierung und MCP. |

## Verpflichtende Verhaltensnachweise

Die in beiden Abnahmeläufen praktisch widerlegten Sicherungen dürfen nicht
mehr durch einen bloßen Suchanker als belegt gelten. Für diese IDs ist der
erfolgreich ausgeführte Ergebnis-Schlüssel bindend:

| ID | Ergebnis-Schlüssel | Ausführender Test |
|---|---|---|
| T5-D12-31 | territory-enforcement | `tests/template/test-t7-integrity.sh` |
| T5-D12-40 | flag-ban | `tests/template/test-t7-integrity.sh` |
| T5-D12-41 | sandbox-guard | `tests/template/test-t7-integrity.sh` |
| T5-PATCH-04 | lock-orphan | `tests/template/test-t4-ops.sh` |
| T5-PATCH-10 | qa-park | `tests/template/test-t6-qa-autonomy.sh` |
| T5-NEW-09 | mcp-allowlist | `orchestrator/mcp/tests/test_allowlist.py` |
