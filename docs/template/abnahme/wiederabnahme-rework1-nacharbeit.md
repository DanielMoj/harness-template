# Nacharbeit zur Wiederabnahme — N-1 und N-2

Datum: 2026-08-06  
Grundlage: [Wiederabnahme Rework 1](wiederabnahme-rework1.md)  
Betreiber-Entscheid: E9 — R1 war beispielhaft gemeint; maßgeblich ist das
Schutzziel E8.

## Ergebnis

Die Befunde N-1 und N-2 sind behoben. Die Änderungen wurden in zwei getrennten
Commits nach `origin/master` gepusht. Der lokale und der entfernte Hash stimmen
überein; die abschließende Arbeitsbaumprüfung war leer.

## N-1 — Pfadvalidierung aller betroffenen MCP-Befehle

In `orchestrator/mcp/server.py` extrahiert `befehl()` jetzt das Pfad-Token von
`tail -n`, `wc -l` und `git diff` einschließlich `git diff --stat`. Vor der
Ausführung durchläuft jedes vorhandene Token `pruefe_pfad()`. Damit wird der
Realpfad geprüft: Das Ziel muss innerhalb des konfigurierten Repos liegen und
darf nach der Auflösung keinen `.env`-Pfad ergeben.

`orchestrator/mcp/tests/test_allowlist.py` enthält neun neue Regressionen:

| Befehl | Symlink auf `secrets.env` | Symlink auf `config.env` | Symlink nach außerhalb |
|---|---:|---:|---:|
| `tail -n 40` | abgelehnt | abgelehnt | abgelehnt |
| `wc -l` | abgelehnt | abgelehnt | abgelehnt |
| `git diff` | abgelehnt | abgelehnt | abgelehnt |

### Vorher-Reproduktion

Die Proben liefen in einem temporären Fixture-Repo mit ausschließlich
erkennbaren Attrappenwerten.

```text
--- befehl('tail -n 40 src/notiz')
Exit-Code: 0
OPENROUTER_API_KEY=sk-fixture-SECRETSENV999
--- befehl('tail -n 40 src/konfig')
Exit-Code: 0
AUTONOMY_LEVEL=3
ACCEPTANCE_SCENARIO=T2
--- befehl('tail -n 5 src/aussen')
Exit-Code: 0
OUTSIDE_FIXTURE=must-not-be-readable
```

Auch der Builder konnte den Symlink ohne Territoriumsverletzung anlegen:

```text
EXITCODE=0
Territoriumsmeldungen=0
120000 dd087ad77301feb5cab35816baa43be7c4ee60b6 0  src/notiz
tail -n 2 src/notiz:
OPENROUTER_API_KEY=sk-or-v1-SYMTEST
```

### Nachher-Reproduktion

Dieselben drei MCP-Proben wurden nach dem Fix erneut ausgeführt:

```text
--- befehl('tail -n 40 src/notiz')
abgelehnt: Pfad ausserhalb des konfigurierten Repos
--- befehl('tail -n 40 src/konfig')
abgelehnt: Pfad ausserhalb des konfigurierten Repos
--- befehl('tail -n 5 src/aussen')
abgelehnt: Pfad ausserhalb des konfigurierten Repos
```

Der Builder-Symlink bleibt als erlaubtes Builder-Artefakt anlegbar, der
Connector folgt ihm aber nicht mehr:

```text
EXITCODE=0
Territoriumsmeldungen=0
120000 dd087ad77301feb5cab35816baa43be7c4ee60b6 0  src/notiz
Symlink-Ziel=../orchestrator/secrets.env
abgelehnt: Pfad ausserhalb des konfigurierten Repos
```

Der gezielte Testlauf ergab:

```text
$ python3 -m py_compile orchestrator/mcp/server.py orchestrator/mcp/tests/test_allowlist.py
(keine Ausgabe; Exit 0)

$ python3 orchestrator/mcp/tests/test_allowlist.py
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
```

## N-2 — heartbeat-relative Watchdog-Uhr

In `tests/template/test-t4-ops.sh` wird der Heartbeat vor dem abgewiesenen
Doppelstart gesichert und in Epoch-Sekunden umgerechnet. Die zweite
Watchdog-Probe verwendet diesen alten Heartbeat als feste Bezugsgröße, eine
30-Sekunden-Grenze und eine Prüfuhr bei `Heartbeat + 60 Sekunden`.

Bleibt der Heartbeat wie gefordert unverändert, meldet der Watchdog `STALE`.
Würde der Altstand ihn auf den aktuellen Zeitpunkt verjüngen, wäre die
heartbeat-relative Prüfuhr älter als der neue Zeitstempel; der Watchdog würde
`fresh` melden und die Assertion mit dem erwarteten Exit 1 brechen.

```text
$ bash -n tests/template/test-t4-ops.sh
(keine Ausgabe; Exit 0)

$ bash tests/template/test-t4-ops.sh
notify: sent event=DONE
notify: sent event=PARKED
watchdog: STALE age=1053315200s pid=1
watchdog: STALE age=60s pid=1
notify-capture: done,fatal,parked,stale
T-4 PASS: notify=DONE,PARKED watchdog=STALE double-start=isolated foreign-lock=FATAL status-precedence=parked watchdog-exit=1
```

## Vollständiger Abnahmelauf

Der erste Aufruf in der eingeschränkten Sandbox erreichte T-1 und scheiterte
ausschließlich an der dort gesperrten DNS-Auflösung beim temporären, gepinnten
Download:

```text
$ bash tests/template/run-all.sh
ERROR: Could not find a version that satisfies the requirement mcp==1.28.1
ERROR: No matching distribution found for mcp==1.28.1
```

Der Befehl wurde unverändert mit genehmigtem Netzwerkzugriff wiederholt. Das
Paket `mcp==1.28.1` wurde im temporären externen venv installiert; anschließend
lief die komplette Suite durch:

```text
$ bash tests/template/run-all.sh
T-1 PASS: bootstrap=2 summary=contract-v1 repo-env=absent mcp-manifest=pinned secrets=isolated tunnel=0
T-2 PASS: milestones=2 gates=2 red=1 rework=1 transport-retry=1 territory-retry=1 done=2 exit=0
T-3 PASS: rebuild=r4 arbiter=HUMAN parked=M0 escalation=present exit=3
T-4 PASS: notify=DONE,PARKED watchdog=STALE double-start=isolated foreign-lock=FATAL status-precedence=parked watchdog-exit=1
test_allowlist: 72/72 OK
T-6 PASS: qa=active qa-park=pre-round autonomy0=8-distinct-phases digit-free-ids=2
T-7 PASS: hidden-territory=rollback logs=hash-protected env=allowlisted flags=expanded guards=explicit preflight=contracts manifest=cycle qa-bound=validated deps=FATAL identity=FATAL preset-hooks=accepted
T-8 PASS: gate-error=2-retries-no-round rc5=fail mutgate=pass,ratchet-fail,error trace=pass golden-adr=fail,pass territory-marker=current
T-5B PASS: territory-enforcement flag-ban sandbox-guard lock-orphan qa-park mcp-allowlist executed
T-5 PASS: target=versioned rows=112 static=101 behavior=6 omitted=5 categories=ORCH=12,AGENT=5,D12=64,PATCH=15,D14=7,NEW=9 exact-ids=PASS cross-file=PASS

A6 PASS: T-1 T-2 T-3 T-4 MCP-Allowlist T-5B T-5 T-6 T-7 T-8
```

## Commits, Push und Endkontrolle

```text
c6494b69d50f7e12dd96aee587c21c3b844887ee fix(security): close MCP symlink path escape (N-1)
dc021ee4af25c0d1c2fbcea80d95751092897311 test(ops): make watchdog clock heartbeat-relative (N-2)
```

Push-Ausgabe:

```text
To https://github.com/DanielMoj/harness-template.git
   3d95ed7..dc021ee  master -> master
```

Lokaler und tatsächlicher Remote-Hash:

```text
local:  dc021ee4af25c0d1c2fbcea80d95751092897311
remote: dc021ee4af25c0d1c2fbcea80d95751092897311  refs/heads/master
```

Abschließende Prüfung des damals gepushten Stands:

```text
$ git status --short
(keine Ausgabe)
```
