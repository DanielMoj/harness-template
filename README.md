# harness-template — Werkbank für autonome Projekte

Dieses private Template trennt Bauen, Abnehmen und Red Team in drei
Modellrollen. Dateien sind das Gedächtnis, deterministische Gates entscheiden
über grün/rot, und der Betreiber greift nur bei einer belegten Eskalation
ein.

## Schnellstart

```bash
git clone <privates-template-repo> mein-projekt
cd mein-projekt
bash bootstrap.sh
```

Danach:

1. Besprechungs-Destillat gegen
   `projektierung/INTAKE-CHECKLISTE.md` prüfen.
2. `projektierung/PROJEKTIERUNG.md` mit dem passenden Preset ausführen und
   die erzeugten Specs redigieren/freigeben.
3. Gate-Beispiele als aktive `orchestrator/gates.d/NN-name.sh` auswählen.
4. `orchestrator/config.env`, `toolchain.json` und Rollenlogins prüfen.
5. `bash start.sh M0`; erst nach grünem M0 echte Meilensteine starten.

## Maschine

- `AGENTS.md`: Verfassung, Territorien und Integrität.
- `contracts/PROTOCOLS.md`: Phasen-, Handoff-, Gate- und Statusvertrag.
- `orchestrator/orchestrate.sh`: idempotente Phasenschleife mit Lock,
  Transport-Retry, Rebuild, Arbiter und Park-&-Continue.
- `orchestrator/verifier.sh`: reiner Gate-Steckplatz-Runner.
- `STATUS.md` und `orchestrator/state/summary.json`: menschliche und
  maschinelle Sicht desselben Zustands.
- `projektierung/`: Verfahren vom Destillat zu Specs, Meilensteinen, Gates
  und Projektblock.
- `docs/template/`: interne Bau-, Abnahme- und Rework-Nachweise des Templates;
  neu angelegte Zielprojekte dürfen diesen gesamten Ordner löschen.
- `RUNBOOK.md`: Betreiber-Handgriffe.

## MCP und Tunnel

`bootstrap.sh` richtet den gehärteten MCP-Repo-Connector in einer virtuellen
Umgebung außerhalb des Repos ein und startet ihn in `tmux`. Quick Tunnel ist
der Nullkonfigurationsweg. Ein benannter Cloudflare-Tunnel wird empfohlen:
stabile Hostadresse plus zufälliger, nicht erratbarer MCP-Pfad.

Tunnel-Token und API-Keys liegen ausschließlich in der unversionierten Datei
`orchestrator/secrets.env` (Modus 600). Modellphasen sehen nur
`PROMPT_FILE`, `PATH`, `HOME`, `LANG` und explizit je Rolle freigegebene,
nicht geheime Variablen.

Der Connector ist lesend (`lies`, `liste`, strikte Befehls-Allowlist). Der
einzige Schreibpfad ist die gedeckelte, kuratierte
`orchestrator/LESSONS.md`.

## Exit-Codes

- 0: Lauf regulär fertig oder Autonomiestufe hat planmäßig gehalten.
- 2: FATAL/PREFLIGHT-/Infrastrukturabbruch.
- 3: Lauf beendet, mindestens ein Meilenstein ist geparkt.

Die normative Bau- und Abnahmebeschreibung des Templates steht in
`docs/template/BAUPLAN.md`.
