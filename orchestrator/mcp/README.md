# MCP-Repo-Connector

Der Connector wird von `bootstrap.sh` in einer externen virtuellen Umgebung
installiert und über `orchestrator/mcp/start.sh` in tmux betrieben.

Umgebung:

- `REPO_PATH`: erlaubte Repo-Wurzel,
- `MCP_HOST`: lokale Bind-Adresse (Default `127.0.0.1`),
- `PORT`: lokaler Port,
- `MCP_PATH`: `/mcp` oder zufälliges `/mcp-<hex>` beim Named Tunnel,
- `PROJECT_SLUG`: Servername,
- `MCP_AUDIT_LOG`: optionaler Audit-Logpfad.

Tools:

- `lies`: UTF-8-Datei innerhalb des Repos,
- `liste`: begrenzte Verzeichnisansicht,
- `befehl`: ausschließlich exakt erlaubte read-only Git/wc/tail/grep-Befehle,
- `lessons_schreiben`: einziger Schreibpfad, Vollersatz von
  `orchestrator/LESSONS.md`, maximal 16.000 Zeichen.

Prüfungen:

```bash
python orchestrator/mcp/server.py --selftest
python orchestrator/mcp/tests/test_allowlist.py
```

Der Tunnel ist keine Authentisierung. Connector-URL beziehungsweise der
zufällige Named-Tunnel-Pfad werden wie Geheimnisse behandelt und nicht
committet.
