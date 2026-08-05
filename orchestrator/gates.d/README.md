# Gate-Steckplätze

Aktiv ist nur eine ausführbare Datei `NN-name.sh` direkt in diesem
Verzeichnis. Dateien `*.sh.example` sind entkoppelte Vorlagen und werden
nicht automatisch ausgeführt.

Ein Gate erhält:

- `REPO_ROOT`: absolute Repo-Wurzel,
- `ORCH`: absolutes Orchestrator-Verzeichnis,
- `MILESTONE`, `ROUND`, `BASE_SHA`,
- `GATE_ARTIFACT_DIR` für Bilder/Reports,
- `GATES_PROGRESS_JSON` mit den Status bereits gelaufener Gates.

Exit 0 = pass, 1 = fail, 2 = error/Infrastructure. Die letzte nichtleere
stdout-Zeile ist der Kurzbefund. Ausführliche Diagnose geht nach stdout oder
stderr und landet vollständig in `state/<MS>/gate-<name>.log`.

Aktivierung, Beispiel:

```bash
cp orchestrator/gates.d/10-deps.sh.example orchestrator/gates.d/10-deps.sh
chmod +x orchestrator/gates.d/10-deps.sh
```

Die Beispiele referenzieren ausschließlich `config.env`-Variablen und
Repo-Dateien. Sie enthalten keinen Pfad und kein Kommando aus dem
Extraktionsprojekt.

## Zusätzliche Formate

`90-laengenkorridor.sh.example` erwartet einen Anker mit `bands`:

```json
{"bands":[{"path":"kapitel/01.md","min_words":1000,"max_words":1400}]}
```

Kontinuität, Zitate und Datengates werden als konfigurierte Kommandos
ausgeführt. Ein Judge-Kommando muss genau ein JSON-Objekt mit
`{"verdict":"PASS|FAIL","reason":"..."}` auf stdout liefern.
