# Nachprüfung N-1 — MCP-Symlink-Pfadflucht

Prüfzeitpunkt: 2026-08-06T18:33+02:00. Prüfstand: `/home/danie/dev/harness-template`,
HEAD `dc021ee` („test(ops): make watchdog clock heartbeat-relative (N-2)"),
Linux 6.6.87.2-microsoft-standard-WSL2, bash 5.3.9(1), git 2.53.0, Python 3.14.4.
Eigener Fall: `/tmp/n1-nachpruefung.oGZbGs/repo`.

Gegenstand ist ausschließlich Befund **N-1** aus
[`wiederabnahme-rework1.md`](wiederabnahme-rework1.md) Abschnitt 6 („MCP-Connector
gibt `secrets.env` und `config.env` über `tail -n N <symlink>` heraus", MITTEL bis
HOCH). Der Fix liegt in `c6494b6` („fix(security): close MCP symlink path escape
(N-1)"), 9 Zeilen in `orchestrator/mcp/server.py` und 23 in
`orchestrator/mcp/tests/test_allowlist.py`.

Die Prüfung lief vollständig lesend. Nach Abschluss war
`git status --porcelain --untracked-files=all` leer und HEAD unverändert bei
`dc021ee`. Einzige nachträgliche Änderung am Repo ist diese Berichtsdatei.

---

## 1. Urteil: **N-1 GESCHLOSSEN**

Alle neun Symlink-Zugriffe über `tail`, `wc -l` und `git diff` werden vor der
Ausführung abgelehnt, der legitime `tail` funktioniert unverändert, und die
Gegenprobe gegen `c6494b6^` zeigt an derselben Fixture 9 Durchläufe mit 3 echten
Klartext-Leaks.

Eine Präzisierung gegenüber dem Ursprungsbefund steht in Abschnitt 5: für
`git diff` ist der neue Pfadcheck eine Härtung, kein nachgewiesener Leckkanal.

---

## 2. Mitgelieferte Suite

```text
$ python3 orchestrator/mcp/tests/test_allowlist.py
…
OK    tail -n 40 lehnt Symlink auf secrets.env ab
OK    tail -n 40 lehnt Symlink auf config.env ab
OK    tail -n 40 lehnt Symlink auf Repo-Aussengrenze ab
OK    wc -l lehnt Symlink auf secrets.env ab
OK    wc -l lehnt Symlink auf config.env ab
OK    wc -l lehnt Symlink auf Repo-Aussengrenze ab
OK    git diff lehnt Symlink auf secrets.env ab
OK    git diff lehnt Symlink auf config.env ab
OK    git diff lehnt Symlink auf Repo-Aussengrenze ab

test_allowlist: 72/72 OK
EXITCODE=0
```

Die drei in N-1 verlangten Negativtests je Befehl sind vorhanden und grün
(vorher 63 Fälle, jetzt 72).

## 3. Eigener Fall

Neu angelegte Fixture, nicht die mitgelieferte: echtes `git init` plus Commit,
Symlinks getrackt, Geheimnisse mit eigenen Markern.

```text
$ ls -l src/
lrwxrwxrwx aussen -> /etc/passwd
lrwxrwxrwx konfig -> ../orchestrator/config.env
-rw-r--r-- main.txt
lrwxrwxrwx notiz  -> ../orchestrator/secrets.env

$ git ls-files -s src/
120000 3594e94c… 0  src/aussen
120000 281d2462… 0  src/konfig
100644 83ed72a4… 0  src/main.txt
120000 dd087ad7… 0  src/notiz
```

Inhalte: `orchestrator/secrets.env` = `OPENROUTER_API_KEY=sk-or-v1-SECRETSENV999`,
`NOTIFY_TOKEN=GEHEIM-NOTIFY-999`; `orchestrator/config.env` = `AUTONOMY_LEVEL=3`,
`ACCEPTANCE_SCENARIO=T2`, `TUNNEL_TOKEN=GEHEIM-TUNNEL-777`.

Zwei bewusste Abweichungen von `test_allowlist.py`, damit der Fall nicht denselben
Codepfad wie die mitgelieferte Suite nimmt:

- Das Repo kommt über die Umgebungsvariable `REPO_PATH` und läuft damit beim
  Import durch `os.path.realpath` (`server.py:32`). Die Suite setzt stattdessen
  `server.REPO` nach dem Import direkt.
- Die Außengrenze zeigt auf das echte `/etc/passwd`, nicht auf ein zweites
  Temp-Verzeichnis.

Das Audit-Log wurde per `MCP_AUDIT_LOG` nach `/tmp` umgeleitet, damit der Fall
nichts in `orchestrator/mcp/calls.log` schreibt.

## 4. Proben gegen `server.py` @ `dc021ee`

| Probe | Ergebnis | Exit |
|---|---|---|
| `tail -n 40 src/notiz` | `abgelehnt: Pfad ausserhalb des konfigurierten Repos` | kein Prozessstart |
| `tail -n 40 src/konfig` | dito | kein Prozessstart |
| `tail -n 5 src/aussen` | dito | kein Prozessstart |
| `wc -l src/notiz` | dito | kein Prozessstart |
| `wc -l src/konfig` | dito | kein Prozessstart |
| `wc -l src/aussen` | dito | kein Prozessstart |
| `git diff src/notiz` | dito | kein Prozessstart |
| `git diff src/konfig` | dito | kein Prozessstart |
| `git diff src/aussen` | dito | kein Prozessstart |
| `tail -n 3 src/main.txt` (legitim) | `Exit-Code: 0` · `Zeile eins/zwei/drei` | **0** |

```text
Verletzungen: 0
EXITCODE=0
```

Kein Marker aus `secrets.env`, `config.env` oder `/etc/passwd` erschien in einer
Antwort. „Kein Prozessstart" ist wörtlich zu nehmen: die Ablehnung greift in
`befehl()` (`server.py:301-309`) vor dem `subprocess.run`, es gibt also keinen
Kindprozess und keinen Exitcode — genau die in N-1 empfohlene Korrektur („alle
Allowlist-Regeln mit `{PFAD}`-Gruppe vor der Ausführung durch `pruefe_pfad()`").

Die Ablehnung trägt für alle drei Ziele denselben Text. Bei `secrets.env` und
`config.env` ist er streng genommen ungenau — der realpath liegt *innerhalb* des
Repos und scheitert am `.env`-Filter (`server.py:128`), nicht an der Repogrenze.
Das ist eine Meldungsunschärfe ohne Schutzwirkung, kein Befund.

## 5. Gegenprobe gegen `c6494b6^`

Damit das Grün aus Abschnitt 4 nicht bloß behauptet ist: derselbe Fixture,
dasselbe Prüfskript, nur der Stand vor dem Fix.

```text
$ git show c6494b6^:orchestrator/mcp/server.py > server-vor-fix.py

tail -n 40 src/notiz   Exit-Code: 0 | OPENROUTER_API_KEY=sk-or-v1-SECRETSENV999
                                    | NOTIFY_TOKEN=GEHEIM-NOTIFY-999
tail -n 40 src/konfig  Exit-Code: 0 | AUTONOMY_LEVEL=3 | ACCEPTANCE_SCENARIO=T2
                                    | TUNNEL_TOKEN=GEHEIM-TUNNEL-777
tail -n 5  src/aussen  Exit-Code: 0 | danie:x:1000:1000::/home/danie:/bin/bash
wc -l src/notiz        Exit-Code: 0 | 2 src/notiz
wc -l src/konfig       Exit-Code: 0 | 3 src/konfig
wc -l src/aussen       Exit-Code: 0 | 27 src/aussen
git diff src/{notiz,konfig,aussen}  Exit-Code: 0 | (keine Ausgabe)
tail -n 3 src/main.txt Exit-Code: 0 | Zeile eins/zwei/drei

Verletzungen: 9
EXITCODE=1
```

Das Prüfskript diskriminiert also. Zugleich präzisiert die Gegenprobe den
Ursprungsbefund: `git diff <symlink>` lief vor dem Fix durch, gab aber **keinen
Dateiinhalt** heraus — git diffed das Link-Blob, nicht dessen Ziel. Belegt
leakend sind `tail` (Klartext) und `wc -l` (Zeilenzahl der Zieldatei, also ein
schmaler Seitenkanal). Für `git diff` ist der Pfadcheck damit eine konsistente
Härtung des Guards, kein geschlossener Leckkanal. Am Urteil ändert das nichts,
an der Schwere-Begründung schon: der Klartext-Pfad war `tail`.

## 6. Repo-Zustand

```text
$ git status --porcelain --untracked-files=all
(leer)                                                   Exit 0
$ git rev-parse --short HEAD
dc021ee
```

Keine Commits. Eine Nebenwirkung ist festzuhalten: der Suitelauf aus Abschnitt 2
hängt seine Proben an `orchestrator/mcp/calls.log` an, weil `test_allowlist.py`
`MCP_AUDIT_LOG` nicht setzt und `server.py:47` dann auf
`orchestrator/mcp/calls.log` zurückfällt. Die Datei ist über `.gitignore:34`
(`orchestrator/mcp/*.log`) ignoriert, `git status` bleibt daher sauber. Wer die
Suite in einem Zielprojekt fährt, sollte das wissen; ein Defekt ist es nicht.

## 7. Ausgeführte Kommandos

| # | Kommando | Exit |
|---|---|---|
| 1 | `python3 orchestrator/mcp/tests/test_allowlist.py` | **0** — 72/72 |
| 2 | Fixture-Aufbau (`git init`, Commit, 3 Symlinks) | 0 |
| 3 | 10 Connector-Proben gegen `server.py` @ `dc021ee` | **0** — 0 Verletzungen |
| 4 | `git show c6494b6^:orchestrator/mcp/server.py` | 0 |
| 5 | 10 Connector-Proben gegen `c6494b6^` (Gegenprobe) | **1** — 9 Verletzungen, 3 Leaks |
| 6 | `git status --porcelain --untracked-files=all`, `git rev-parse HEAD` | 0 |
| 7 | `git check-ignore -v orchestrator/mcp/calls.log` | 0 |

## 8. Offene Frage aus N-1

Unberührt bleibt die Betreiberfrage aus `wiederabnahme-rework1.md:310-313`: ob R1
(„`grep`-Pfadargumente") abschließend oder als Beispiel gemeint war. Diese
Nachprüfung stellt nur fest, dass die Lücke technisch geschlossen ist; die
Einordnung als Nacharbeitspunkt aus Rework 1 oder als eigenes Paket ist damit
nicht entschieden.
