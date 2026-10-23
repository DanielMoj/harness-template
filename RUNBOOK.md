# RUNBOOK — Betreiber-Handgriffe

## PARKED / Exit 3

1. `orchestrator/ESCALATION-<MS>.md`, Handoff, `gates.json` und referenzierte
   Gate-Logs lesen.
2. Nur die benannte Betreiber-/Infrastrukturursache oder echte Spec-Lücke
   beheben; keine Tests, Gates oder Schwellen abschwächen.
3. Bei einer Spec-Entscheidung ein ADR beziehungsweise eine freigegebene
   Spec-Änderung schreiben.
4. Den Parkmarker gezielt entfernen und die Entfernung committen:
   `git rm orchestrator/state/<MS>/parked && git commit -m "betreiber: <MS> fortsetzen"`.
   Der Marker ist versioniert; nach einem bloßen `rm` gilt der Arbeitsbaum
   als unsauber, und der PREFLIGHT bricht mit FATAL ab.
5. `bash start.sh <MS>`; offene `deps` bleiben weiterhin gesperrt.

## Arbiter meldet HUMAN

`ARBITER.md` enthält die konkrete Frage und beide widersprüchlichen
Spec-Stellen. Entscheide nur diese Frage, dokumentiere den Entscheid als ADR
oder Spec-Korrektur und entferne anschließend den Parkmarker. Ein
`RESOLVE`-Verdict ist bereits bindend und benötigt keinen Betreiberentscheid.

## FATAL / Exit 2

Die letzte `FATAL`-Zeile in `orchestrator/logs/orchestrate.log`,
`STATUS.md` und `state/summary.json` lesen. Häufige Ursachen:

- schmutziger Arbeitsbaum vor dem Lauf,
- fehlendes/ungültiges Manifest oder Rollenkommando,
- reale CLI-Flags stimmen nicht mit config.env überein,
- verbotenes Muster im Rollenkommando (die FATAL-Zeile nennt es, etwa
  `--approval-mode yolo` oder `resume`),
- QA-Routenprobe gescheitert (Abschnitt unten),
- `Verdict fehlt`, `Verdict veraltet` oder `Verdict passt nicht zur Runde`:
  Die Review-Phase hat kein Verdict der laufenden Runde geschrieben. Ein
  liegengebliebenes Verdict einer früheren Runde entscheidet nie über neuen
  Code. Zuerst das Reviewer-Log der genannten Runde lesen
  (`orchestrator/logs/<MS>-30-plan-review-r<N>-*.log` beziehungsweise
  `<MS>-50-code-review-r<N>-*.log`). Danach den in der Meldung genannten
  Phasenmarker mit `git rm` entfernen, committen und neu starten; die
  Review-Phase läuft dann in derselben Runde erneut. Ein bloßes `rm` genügt
  nicht, weil der Marker versioniert ist,
- wiederholter Transport- oder Territoriumsfehler,
- Doppelstart/aktiver Lock.

Ein verwaister Lock, der nur eine tote `pid` enthält, wird automatisch und
atomar übernommen. Enthält `orchestrator/.lock/` dagegen fremde Dateien,
bricht der Start absichtlich ab: zuerst die gegebenenfalls eingetragene PID
mit `kill -0 <PID>` prüfen, dann ausschließlich dieses Lock-Verzeichnis
gezielt entfernen. Einen Lock mit lebender PID niemals verändern. Ein
abgewiesener Doppelstart schreibt weder Heartbeat noch Notify-Ereignis; der
laufende Orchestrator bleibt die einzige Statusquelle.

## PREFLIGHT: QA-Routenprobe fehlgeschlagen

`FATAL: QA-Routenprobe strict fehlgeschlagen.` Die vorangehende WARN-Zeile in
`orchestrator/logs/orchestrate.log` nennt rc und das Probe-Log
`orchestrator/logs/qa-probe-<zeitstempel>-<versuch>.log` mit der vollständigen
CLI-Ausgabe. Häufige Ursachen:

- `Approval mode overridden to "default" because the current folder is not
  trusted.` (Gemini CLI 0.65.0, gleichlautend Qwen Code 0.26.0): Der Ordner
  gilt der CLI nicht als vertraut. Die Gemini CLI liest dann auch
  `~/.gemini/.env` nicht, die Probe scheitert meist an der fehlenden
  Anmeldung; käme sie trotzdem durch, liefe QA ohne Schreib- und Shellrechte.
  Abhilfe: `security.folderTrust.enabled=false` in `~/.gemini/settings.json`
  (bei Qwen Code `~/.qwen/settings.json`, dort ist Ordner-Vertrauen ohne
  Eintrag aus) oder das Zielrepo in `~/.gemini/trustedFolders.json`
  eintragen.
- `Gemini CLI is not running in a trusted directory.` (Headless-Abbruch der
  Gemini CLI): dieselbe Ursache, dieselbe Abhilfe.
- Fehlender oder nicht freigeschalteter Schlüssel, Modell unbekannt, kein
  Guthaben: Die Fehlermeldung des Anbieters steht im Probe-Log. Gemini 4 Argon
  hat keinen kostenlosen Zugang; die Abrechnung des Projekts muss aktiv sein.
- rc 124: Zeitüberschreitung (`QA_PROBE_TIMEOUT`). Ein Hänger ohne Terminal
  ist für den Druckmodus der Antigravity CLI gemeldet (Weg B unten).
- `Ripgrep is not available`: kein Abbruchgrund, die Suche ist nur langsamer;
  `ripgrep` installieren.

Nachstellen ohne Terminal, aus der Repo-Wurzel:

```bash
echo "Antworte nur: OK" | timeout 300 gemini -m gemini-4-argon --approval-mode auto_edit \
  --policy orchestrator/policies/qa-gemini.toml > /tmp/qa-probe.txt 2>&1; echo "rc=$?"; cat /tmp/qa-probe.txt
```

Erwartet sind `rc=0` und `OK`. Zwischen zwei Versuchen wartet der PREFLIGHT
`QA_PROBE_SLEEP` Sekunden (Vorgabe 300).

## QA-Zugang

- **Weg A, Gemini CLI (gewählt):** bezahlter Gemini-API-Schlüssel in
  `~/.gemini/.env` (`GEMINI_API_KEY=…`, Modus 600), Ordner-Vertrauen wie oben,
  `ripgrep`, Kommando und Policy nach `config.env.example`. Die Gemini CLI
  bedient seit 18.06.2026 keine Privat-, Google-AI-Pro- und Ultra-Konten mehr;
  „Login with Google“ fällt damit weg.
- **Weg B, Antigravity CLI (`agy`, nicht gewählt):** Flags vor dem Einsatz mit
  `agy --help` belegen; als sicherer Modus ist in Drittdokumentation
  `--mode accept-edits` genannt, die Shell-Freigabe läuft über
  `permissions.allow` in den Einstellungen. `--dangerously-skip-permissions`
  bleibt verboten (der Wächter sperrt es). Die Einstellung
  `toolPermission: always-proceed` wirkt wie ein Bypass, steht aber nicht im
  Kommando: Der Betreiber prüft die Antigravity-Einstellungen vor jedem Lauf
  und lässt diese Einstellung aus. Für `agy -p` ist ein Hänger ohne Terminal
  gemeldet (google-antigravity/antigravity-cli, Issue 318); der Orchestrator
  startet Rollen genau so.
- **Weg C, Qwen Code (Ersatz):** OpenRouter-Konto mit Guthaben; in
  `~/.qwen/.env` stehen `OPENAI_API_KEY`, `OPENAI_BASE_URL` und
  `OPENAI_MODEL`. Qwen Code liest diese Datei auch unter `env -i`.
  `--approval-mode auto-edit` (Bindestrich); ohne den Schalter liefe Qwen Code
  im Klassifikator-Modus `auto`.
- Läuft keiner der Wege: `QA_ENABLED=0`. Ist `QA_REQUIRED_FROM` gesetzt, parkt
  der Meilenstein dort; kein anderes Modell stillschweigend eintragen.

Allgemein gilt: Freigaben in den Einstellungsdateien der CLIs unter `HOME`
(`tools.allowed` in `~/.gemini/settings.json`, `permissions.allow` in
`~/.qwen/settings.json` oder `~/.claude/settings.json`) sieht der Wächter
nicht. Sie vor einem Lauf zu prüfen ist Betreiberpflicht.

## Modellwechsel im Reviewer-Log

Claude Code kann markierte Anfragen automatisch auf einem anderen Modell
wiederholen; der Hinweis erscheint in der Sitzung, und die Antwort trägt das
Modell, das geantwortet hat. Laut Anthropic betrifft das Fable 5 und Fable 5.1
ebenso wie Opus 5.5: Bei Opus 5.5 fallen Biologie- und eng gefasste
„frontier LLM development“-Anfragen auf Opus 5 zurück, offensive
Cybersecurity-Anfragen auf Opus 4.8. Im Textmodus von `claude -p` steht im
Phasenlog `orchestrator/logs/<MS>-<phase>-r<runde>-a<versuch>-*.log` nur die
Schlussantwort; den Wortlaut des Hinweises dokumentiert Anthropic nicht.
Nachweise:

- Sitzungsprotokoll von Claude Code: Jede `-p`-Sitzung liegt unter
  `~/.claude/projects/<Repo-Pfad mit - statt />/<sitzung>.jsonl`.
  `jq -r 'select(.type=="assistant") | .message.model' <datei> | sort | uniq -c`
  listet die antwortenden Modelle; mehr als `claude-opus-5-5` heißt Wechsel.
- Wer den Nachweis im Phasenlog selbst haben will, ergänzt im
  `REVIEWER_CMD` `--output-format json`. Das Log endet dann mit einem
  JSON-Objekt; `jq -r '.modelUsage | keys[]' <log>` nennt jedes Modell, das in
  der Phase geantwortet hat. Verdicts und Handoffs bleiben unverändert.
- Ohne Wechsel: In Claude Code unter Config > MODEL & OUTPUT „Switch models
  when a message is flagged“ ausschalten. Eine markierte Anfrage hält dann laut
  Anthropic an, statt das Modell zu wechseln; wie sich das im Druckmodus
  zeigt, ist nicht dokumentiert und hier nicht geprüft. Das ist eine
  Betreiberentscheidung.

## Codex CLI

- Warnung wegen `bwrap` beim Start: `sudo apt install bubblewrap`; die
  Linux-Sandbox nimmt das erste `bwrap` im `PATH`.
- Den Modellkatalog zeigt `codex debug models` (`codex models` gibt es in
  0.164.0 nicht). Lehnt ein echter Aufruf `gpt-6-astra` ab, ist das Modell für
  das Konto nicht freigeschaltet; die Rolle muss neu besetzt werden.
- `--sandbox workspace-write` hat kein Netz. Fehlt dem Builder ein Paket, ist
  das ein Fall für das deps-Gate, nicht für eine Netzfreigabe.

## Ausführungsrechte

Auf `/mnt/c` gilt `core.filemode=false`; ein gewöhnliches `git add` trägt neue
Dateien als 100644 ein. Prüfen mit
`git ls-files -s orchestrator/*.sh orchestrator/lib/*.sh orchestrator/gates.d/[0-9][0-9]-*.sh`
(jede Zeile 100755), nachtragen mit `git add --chmod=+x <datei>` und
committen. `core.filemode` bleibt auf `/mnt/c` `false`.

## Bootstrap und Einsetzen

- `bash bootstrap.sh --no-start --non-interactive` öffnet keinen Editor und
  nimmt den Tunnelmodus `quick`; danach `orchestrator/config.env` bearbeiten.
  Interaktiv öffnet der erste Lauf `${EDITOR:-vi}` (etwa `EDITOR=nano` setzen)
  und fragt auch mit `--no-start` nach dem Tunnelmodus.
- `tools/install-into.sh` (im Template) endet mit Exit 3, wenn offene Punkte
  bleiben: Konflikte mit vorhandenen Dateien, ein ignoriertes `docs/`,
  pkgdown nach `docs/` oder CRLF im Index. Der Bericht nennt jeden Punkt und
  bei pkgdown die nötigen Änderungen; das Skript selbst ändert diese
  Projektdateien nicht.

## STOP

`touch orchestrator/STOP` hält den Orchestrator vor der nächsten Phase mit
FATAL/Exit 2. Nach Sichtung die Datei gezielt entfernen und neu starten.

## Tunnel neu starten

```bash
tmux kill-session -t mcp-<slug>
bash bootstrap.sh --non-interactive
```

Quick Tunnel erzeugt eine neue URL. Beim benannten Tunnel bleiben Hostname
und zufälliger MCP-Pfad stabil. Die aktuelle Connector-Adresse steht lokal
in `orchestrator/mcp/connector.url` und wird nie committet.

## Watchdog

Cron-Beispiel (alle 15 Minuten):

```cron
*/15 * * * * cd /pfad/zum/repo && bash orchestrator/watchdog.sh
```

Nur wenn eine Lock-PID lebt und der `summary.json`-Heartbeat älter als 30
Minuten ist, wird STALE gemeldet. Leeres `NOTIFY_URL` deaktiviert Versand.
