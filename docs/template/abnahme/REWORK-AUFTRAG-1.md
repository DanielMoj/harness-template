# REWORK-AUFTRAG 1 — harness-template nach Abnahme-Läufen 1+2

> Historischer Auftrag, nach E7 in den template-internen Dokumentationsraum verschoben.

Kontext: Zwei unabhängige adversarielle Abnahmen (docs/abnahme/
abnahme-lauf1.md, abnahme-lauf2.md) haben die A6-Basislinie
reproduziert und zugleich mit ausgeführten Gegenbeispielen belegt,
dass mehrere zugesagte Sicherungen im Realbetrieb nicht greifen.
Gesamturteil beider Läufe: FAIL. Dieser Auftrag behebt die Befunde
in acht Paketen. Lies beide Berichte vollständig, bevor du beginnst.

## Regeln

1. Beleg-Regel unverändert: Jede Fertig-Meldung nur mit ausgeführtem
   Kommando-Output. Für jeden behobenen Befund gilt: Das
   Repro-Kommando aus dem Bericht wird als Negativtest in die Suite
   übernommen (erst rot gegen den alten Stand nachvollziehbar
   dokumentiert, dann grün) — nicht nur von Hand nachgefahren.
2. Ein Commit je Paket (R1…R8), sprechende Message mit Befund-IDs.
3. Bei Unklarheiten fragen, nichts erfinden. Die Entscheidungen im
   nächsten Abschnitt gelten als Betreiber-Entscheid und sind nicht
   neu zu verhandeln.
4. Keine Geschichte umschreiben: B-14 (Commit-Bündelung, nicht
   lauffähiger Zwischenstand) wird NICHT rückwirkend repariert.
   Die Ein-Paket-Regel gilt ab jetzt.
5. Am Ende: run-all.sh grün, docs/ABNAHME.md komplett neu erzeugen
   (behebt B-13), docs/T5-INVENTAR.md aktualisieren.

## Betreiber-Entscheidungen zu den offenen Spezifikationsfragen

E1 (→B-05): Gate-Status `error` ohne gleichzeitige `fail`-Gates
    erhöht KEINE Runde und löst KEINEN Rebuild aus. Das Gate wird
    maximal 2× wiederholt; bleibt `error`, wird der Meilenstein mit
    eigener Begründung „Infrastruktur (Gate error)" geparkt
    (needs_human=true, Notify PARKED). `error` zusammen mit `fail`
    verhält sich wie bisher fail.
E2 (→B-04): `AUTONOMY_LEVEL=0` heißt: genau EINE Phase pro Aufruf,
    jede Phase hinterlässt einen runden-bezogenen Marker (auch
    20-plan), sieben Aufrufe = sieben verschiedene Phasen.
E3 (→B-06): Ein deps-Zyklus ist ein Manifestfehler:
    `validate_manifest` erkennt Zyklen und bricht in PREFLIGHT mit
    FATAL (Exit 2, Notify FATAL) ab.
E4 (→B-07): `orchestrate.sh <MS>` mit offenen deps ist FATAL
    (Patch-v2-Verhalten wiederhergestellt), kein stiller Exit 0.
E5 (→B-02): Modelltranskripte bleiben unversioniert. Schutz
    stattdessen: Die Territoriumsprüfung wird von `.gitignore`
    unabhängig (R2); zusätzlich Hash-Manifest über
    `orchestrator/logs/**` vor jeder Modellphase, Gegenprüfung
    danach — Abweichung = Territoriumsverletzung.
E6 (→B-10): T-5 erhält eine versionierte Sollliste
    (`docs/template/T5-SOLL.md`), beim Rework einmalig aus den
    Quellen (docs/12, docs/14, Patch-v2-README, AGENTS) abgeleitet;
    das Prüfskript liest die Sollzeilen von dort statt aus der
    eigenen Tabelle. Die sechs in Lauf 2 §4 widerlegten Zeilen
    werden von Suchankern auf ausführende Tests umgestellt.
E7 (→B-21): `docs/BAUPLAN.md`, `docs/ABNAHME.md`,
    `docs/T5-INVENTAR.md`, Abnahmeberichte → nach `docs/template/`
    verschieben; README-Satz, dass Projekte diesen Ordner löschen
    dürfen. `docs/` bleibt damit projektleer im Sinne von A1.
E8 (→B-08, L2-B-01): Geheimnisse verlassen `config.env`:
    neue Datei `orchestrator/secrets.env` (chmod 600, untracked,
    von bootstrap befüllt: TUNNEL_TOKEN, API-Keys). Modellrollen
    erhalten eine Umgebungs-Allowlist (PROMPT_FILE, PATH, HOME,
    LANG, rollenspezifische Pflichtvariablen) statt des vollen
    Exports; `secrets.env` wird nur von bootstrap/start gelesen,
    nie in `run_model` exportiert.

## Arbeitspakete (Reihenfolge = Priorität)

### R1 — Geheimnisse (L2-B-01, B-08) [KRITISCH]
- `server.py`: `grep`-Pfadargumente vor Ausführung durch
  `pruefe_pfad()`; `grep -rn` nur auf Verzeichnis-Allowlist
  (`orchestrator/logs`, `orchestrator/state`,
  `orchestrator/handoff`, `docs`); zusätzlich `--exclude=*.env`
  erzwungen.
- E8 umsetzen (secrets.env + Umgebungs-Allowlist in `run_model`).
- `orchestrator/mcp/tests/test_allowlist.py` in `run-all.sh`
  aufnehmen; neuer Testfall: Attrappen-Key in config.env, danach
  `befehl('grep -rn API orchestrator')` → muss abgelehnt werden
  oder ohne Treffer bleiben; `LEAK`-Probe aus B-08 als Negativtest.

### R2 — Territorium & Lock (B-02, L2-B-02, B-17, L2-B-04) [KRITISCH]
- `changed_paths()` von `.gitignore` entkoppeln: `git ls-files
  --others` OHNE `--exclude-standard`, gefiltert gegen eine
  explizite, versionierte Artefakt-Allowlist (node_modules, dist,
  reports, coverage, .pnpm-store, Umgebungen); `orchestrator/**`
  wird IMMER geprüft.
- Hash-Manifest über `orchestrator/logs/**` je Modellphase (E5).
- `.gitignore`: `!orchestrator/.lock` ergänzen bzw. Lock-Pfad aus
  `*.lock` herausnehmen; `acquire_lock` atomar (tmp-Verzeichnis +
  `mv` oder `flock`); Fremdinhalt im Lock → FATAL mit benanntem
  Aufräumhinweis, RUNBOOK-Abschnitt dazu.
- `acquire_lock` bei fremdem, lebendem Lock: eigener Ausstieg OHNE
  `refresh_status` und OHNE `notify_event` (stderr + Exit 2) —
  der Heartbeat des laufenden Orchestrators bleibt unberührt.
- Tests: (a) Builder schreibt `orchestrator/.lock/stray` und
  `reports/evil.txt` → Verletzung erkannt, Rollback, Retry-Logik
  wie beim sichtbaren Fall; (b) Prompt-/Log-Fälschung aus B-02 →
  erkannt; (c) Doppelstart bei gehaltenem Lock → Exit 2, Heartbeat
  unverändert, Watchdog meldet weiterhin STALE (Szenario aus
  L2-B-04 als T-4-Erweiterung).

### R3 — Fehlerdisziplin der Schleife (B-01, B-06, B-07) [KRITISCH]
- `run_ms`-Aufruf so umbauen, dass Fehler nicht von der
  `if`-Bedingung verschluckt werden; `commit_phase`, `tag_once`
  und die PROGRESS-Prüfung prüfen ihre git-Kommandos einzeln und
  rufen bei Fehlschlag `fatal`.
- bootstrap.sh und PREFLIGHT verifizieren `git config user.name`
  und `user.email`; fehlend → FATAL mit Hinweis.
- E3 (Zyklenprüfung, FATAL) und E4 (Ziel mit offenen deps → FATAL)
  umsetzen; das `exit 1` in der Auswahlschleife entfernen.
- Tests: Lauf ohne git-Identität → FATAL statt DONE; Zyklus-
  Manifest → PREFLIGHT-FATAL; `orchestrate.sh M1` bei offenem M0
  → FATAL; Positivfall: DONE nur mit vorhandenen Phasen-Commits
  und Tags (Assertion auf `git tag` + Commit-Zahl).

### R4 — PREFLIGHT & Prompt-Rendern (B-03, B-18, B-15, L2-B-03)
- PREFLIGHT prüft die Vertragspfade (prompts/10–70,
  handoff/SCHEMA.md, contracts/PROTOCOLS.md, gates.d/, state/,
  reference/anchors/, status.sh, verifier.sh).
- `render_prompt` mit Fehlerprüfung (`|| fatal`); sed-Delimiter auf
  ein in IDs unzulässiges Zeichen; `criteriaRef` im Manifest auf
  `^[A-Za-z0-9._-]+$` beschränkt.
- Leere `*_SAFE_MODE_PATTERN` oder `*_REQUIRED_FLAGS` → FATAL in
  PREFLIGHT (bewusstes Abschalten nur über neues, explizites
  `ROLE_GUARDS=off`, das laut in orchestrate.log und summary.json
  erscheint).
- Verbotsliste gegen den EXPANDIERTEN Befehl prüfen: vor dem Grep
  einmal kontrolliert expandieren; `$`-Referenzen in
  Rollenkommandos außer `$PROMPT_FILE` lehnt PREFLIGHT ab.
- Tests: fehlender Prompt → FATAL statt DONE; `|` in criteriaRef →
  Manifestfehler; `$EXTRA_FLAGS`-Umgehung aus L2-B-03 → FATAL;
  leeres Pattern → FATAL; Fixtures t2/t3 auf gültige, gefüllte
  Guards umgestellt.

### R5 — Gate-Semantik (B-05, B-24, B-16)
- E1 umsetzen (error-Pfad: keine Runde, kein Rebuild, begrenzte
  Wiederholung, dann Park „Infrastruktur").
- `gates.d/_lib.sh`: rc-Zuordnung ändern — 127/126 → error, jeder
  andere rc>0 → fail; je Gate optional `GATE_ERROR_CODES`
  überschreibbar.
- `82-territory.sh.example`: Marker gegen Runde/Basis-SHA der
  aktuellen Phase prüfen statt bloßer Existenz.
- Tests: Dauer-error-Gate mit PASS-Verdict → Park nach 2
  Wiederholungen, Runde bleibt r1, kein Rebuild; rc=5-Gate → fail.

### R6 — QA & Autonomiestufe 0 (B-04, B-11/L2-B-05, B-23)
- `qa_required` auf Manifest-Indexvergleich; `QA_REQUIRED_FROM`
  wird in PREFLIGHT als existierende Manifest-ID validiert
  (sonst FATAL). Funktioniert damit für IDs wie `setup`,
  `kapitel-eins`.
- E2 umsetzen (Phasenmarker je Runde, Stufe 0 schreitet je Aufruf
  genau eine Phase voran).
- Neuer Test T-6: aktive Fake-QA (45-qa läuft, schreibt
  tests/e2e-Befund + QA.md) UND Park-Szenario `QA_ENABLED=0` mit
  `QA_REQUIRED_FROM=<erste ID>` → parkt vor Rundenverbrauch;
  zusätzlich Stufe-0-Test: 8 Aufrufe erreichen 8 verschiedene
  Phasen; ziffernlose IDs end-to-end.

### R7 — Presets & Generalisierung (B-09, B-21)
- `REVIEWER_EXTRA_PATHS_REGEX` und `QA_EXTRA_PATHS_REGEX` analog
  zum Builder-Hook; in config.env.example dokumentiert; die
  Presets text/daten tragen die passenden Muster (stilbibel,
  figurenbibel, weltbibel, schemas/**) als fertige Zeilen.
- `.dependency-cruiser.*` aus der festen Reviewer-Liste in einen
  konfigurierbaren Hook überführen.
- E7 umsetzen (Template-Dokumente nach docs/template/).
- Test: Text-Preset-Konfig, Reviewer legt stilbibel.md an → kein
  FATAL, Territorium akzeptiert.

### R8 — Nachweise, T-5 und Kleinteile (B-10, B-12, B-13, B-19,
      B-20, B-22, L2-N-01, L2-N-02)
- E6 umsetzen (T5-SOLL.md aus den Quellen, sechs Verhaltens-Tests
  statt Suchanker für: territory-Erzwingung, Flag-Verbot,
  Sandbox-Guard, Lock/verwaiste Locks, QA-Park, MCP-Allowlist).
- Log-Dateinamen mit Versuchszähler (`-a<try>`), damit Retries
  nichts überschreiben (B-12).
- Synthetische Fixtures für mutgate (pass / ratchet-fail / error,
  wie in Patch-v2 README §4 beschrieben), trace und golden-adr;
  je ein Suitelauf gegen die echten Beispiel-Gates (B-22).
- `beispiel/README.md`: Schemaabweichung des historischen Ankers
  benennen (B-19); `status.sh:85` Klammerung (B-20);
  `70-arbiter.md` erhält die Bezeichnung „Kontextmanifest"
  (L2-N-01); T5-PATCH-15-Anker vervollständigen (L2-N-02).

## Abschluss

1. `bash tests/template/run-all.sh` grün (jetzt inkl. allowlist,
   T-6, Verhaltens-T-5) — Output in die neue docs/template/
   ABNAHME.md, zusammen mit den Outputs aller neuen Negativtests.
2. Tabelle „Befund → Commit → Test" über alle IDs beider Berichte
   (auch die bewusst nicht bearbeiteten: B-14 mit Begründung aus
   Regel 4) nach docs/template/REWORK-1-NACHWEIS.md.
3. Push. Danach prüft eine frische, unbeteiligte Prüfersitzung
   ausschließlich die Repro-Kommandos beider Berichte nach —
   erst deren Urteil schließt den Rework ab.
