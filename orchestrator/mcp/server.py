#!/usr/bin/env python3
"""Gehaerteter MCP-Repo-Connector fuer ein Harness-Projekt.

REPO_PATH, MCP_HOST, PORT und MCP_PATH kommen ausschliesslich aus der
Umgebung. Der Server bietet kontrollierten Analysezugang zu Logs, Zustand,
Handoffs, ADRs und STATUS.md. GENAU EIN Schreibpfad ist erlaubt:
orchestrator/LESSONS.md via lessons_schreiben(). Laeufe startet nur der
Betreiber.

Haertung: exakte read-only Befehls-Allowlist, Pfad-Guards, Ein-Pfad-Regel mit
16-kB-Deckel und Audit-Log fuer jeden Tool-Aufruf. Pfadtokens beginnen
zwingend alphanumerisch und koennen strukturell kein '..', keinen absoluten
Pfad und keinen Options-Schmuggel bilden.

Selbsttest (Guards statisch; dazu EIN echter Mini-Lauf 'git status --short',
falls REPO existiert):
    python3 server.py --selftest
Allowlist-Regeln plus isolierte Temp-Fixture fuer rekursives grep:
    python3 orchestrator/mcp/tests/test_allowlist.py
"""

import datetime
import os
import re
import subprocess
import sys
import time

# ------------------------------------------------------------------ Konstanten

HIER = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.realpath(os.environ.get("REPO_PATH", os.path.join(HIER, "..", "..")))
BASH = "/bin/bash"
GIT = "git"

HOST = os.environ.get("MCP_HOST", "127.0.0.1")
try:
    PORT = int(os.environ.get("PORT", "8765"))
except ValueError:
    raise SystemExit("FEHLER: PORT muss eine Ganzzahl sein.")
if not 1 <= PORT <= 65535:
    raise SystemExit("FEHLER: PORT muss zwischen 1 und 65535 liegen.")
MCP_PATH = os.environ.get("MCP_PATH", "/mcp")
if not re.fullmatch(r"/mcp(?:-[a-f0-9]{16,64})?", MCP_PATH):
    raise SystemExit("FEHLER: MCP_PATH muss /mcp oder /mcp-<16..64 hex> sein.")
SERVER_NAME = os.environ.get("PROJECT_SLUG", os.path.basename(REPO)) + "-repo"
LOGDATEI = os.environ.get("MCP_AUDIT_LOG", os.path.join(HIER, "calls.log"))
MAX_BEFEHL_AUSGABE = 40000
REKURSIVE_GREP_WURZELN = (
    "orchestrator/logs",
    "orchestrator/state",
    "orchestrator/handoff",
    "docs",
)

# Einziger Schreibpfad des Servers (repo-relativ) und Groessendeckel.
LESSONS_REL = "orchestrator/LESSONS.md"
MAX_LESSONS_ZEICHEN = 16000

# Pfad-Token fuer die Allowlist: beginnt mit [A-Za-z0-9_] (kein '/', '-', '.'),
# und die Fortsetzung erlaubt '.' nur einzeln vor einem Nicht-Punkt-Zeichen —
# '..' ist damit STRUKTURELL unbildbar, ebenso absolute Pfade und fuehrende
# Options-Striche. Der '..'-Pre-Filter in pruefe_befehl bleibt als zweiter Gurt.
PFAD = r"[A-Za-z0-9_](?:\.?[A-Za-z0-9_/-])*"
# Suchmuster-Token fuer grep: beginnt alphanumerisch (kein '-e'-Schmuggel),
# keine Shell- oder Glob-Metazeichen in der Klasse.
MUSTER = r"[A-Za-z0-9][A-Za-z0-9_.:-]{1,59}"

# Allowlist: (Regex, Timeout Sekunden). Ausgefuehrt wird NUR ein exakter
# Treffer (re.fullmatch; ^…$ zusaetzlich als Gurt). Regel-Hygiene wie in der
# Regel-Hygiene: Alternationen IMMER klammern. Alles hier ist rein lesend —
# kein rm, kein npm/npx, kein bash start.sh/orchestrate: Laeufe startet der
# Betreiber, nicht der Connector.
ALLOWLIST = [
    (rf"^git status( --short)?$", 60),
    (rf"^git log --oneline( -[0-9]{{1,3}})?$", 60),
    (rf"^git diff( --stat)?( {PFAD})?$", 60),
    (rf"^git show [0-9a-f]{{6,40}}( --stat)?$", 60),
    (rf"^wc -l {PFAD}$", 60),
    (rf"^tail -n [0-9]{{1,4}} {PFAD}$", 60),
    (rf"^grep -(n|rn) {MUSTER} {PFAD}$", 60),
]

VERBOTENE_ZEICHEN = ";|&<>`$\n\r"

# Grosse Verzeichnisse, in die liste() nicht hinabsteigt (Eintrag selbst
# bleibt sichtbar; ein expliziter liste()-Aufruf darauf geht weiterhin).
KEINE_REKURSION = {"node_modules", "dist", "coverage", ".venv", "__pycache__",
                   ".stryker-tmp", "playwright-report", "test-results"}


# ------------------------------------------------------------------- Audit-Log

def logge(tool, status, argtext):
    """Haengt jeden Tool-Aufruf (auch abgelehnte) an calls.log an."""
    stempel = datetime.datetime.now().isoformat(timespec="seconds")
    kurz = " ".join(str(argtext).split())[:250]
    try:
        with open(LOGDATEI, "a", encoding="utf-8") as f:
            f.write(f"{stempel}\t{tool}\t{status}\t{kurz}\n")
    except OSError:
        pass  # Logausfall darf den Server nicht stoppen


# ---------------------------------------------------------------------- Guards

def pruefe_pfad(pfad):
    """Prueft einen Lese-Pfad. Rueckgabe (voller_pfad, None) oder (None, grund)."""
    p = str(pfad).strip().replace("\\", "/")
    if not p:
        return None, "abgelehnt: leerer Pfad"
    if ".." in p:
        return None, "abgelehnt: '..' im Pfad"
    if ".env" in p:
        return None, "abgelehnt: '.env' im Pfad"
    if ".git/" in p or p == ".git" or p.endswith("/.git"):
        return None, "abgelehnt: '.git' im Pfad"

    if p.startswith("/"):
        kandidaten = [p]
    else:
        kandidaten = [os.path.join(REPO, p)]

    wurzel = os.path.realpath(REPO)
    treffer = None
    for kandidat in kandidaten:
        real = os.path.realpath(kandidat)
        if ".env" in real or "/.git/" in real or real.endswith("/.git"):
            continue
        if real == wurzel or real.startswith(wurzel + os.sep):
            if os.path.exists(real):
                return real, None
            if treffer is None:
                treffer = real
    if treffer is not None:
        return treffer, None
    return None, "abgelehnt: Pfad ausserhalb des konfigurierten Repos"


def pruefe_befehl(cmd):
    """Prueft einen Befehl gegen Pre-Filter und Allowlist.
    Rueckgabe (True, timeout_sekunden) oder (False, grund)."""
    c = str(cmd).strip()
    for z in VERBOTENE_ZEICHEN:
        if z in c:
            name = "Zeilenumbruch" if z in "\n\r" else z
            return False, f"abgelehnt: verbotenes Zeichen '{name}'"
    if ".." in c:
        return False, "abgelehnt: '..' im Befehl"
    if ".env" in c:
        return False, "abgelehnt: '.env' im Befehl"
    for muster, timeout in ALLOWLIST:
        if re.fullmatch(muster, c):
            return True, timeout
    return False, "abgelehnt: kein Allowlist-Treffer"


def grep_argv(cmd):
    """Validiert den grep-Pfad semantisch und liefert ein argv ohne Shell.

    Rekursive Suchen bleiben auf vier analysebezogene Verzeichniswurzeln
    begrenzt. ``--exclude=*.env`` wird unabhängig vom Aufrufer erzwungen.
    """
    treffer = re.fullmatch(rf"^grep -(n|rn) ({MUSTER}) ({PFAD})$", cmd)
    if not treffer:
        return None, None
    flags, muster, pfad = treffer.groups()
    voll, grund = pruefe_pfad(pfad)
    if voll is None:
        return None, grund
    if flags == "rn":
        normalisiert = pfad.strip("/")
        erlaubt = any(
            normalisiert == wurzel or normalisiert.startswith(wurzel + "/")
            for wurzel in REKURSIVE_GREP_WURZELN
        )
        if not erlaubt or not os.path.isdir(voll):
            return None, "abgelehnt: rekursiver grep-Pfad nicht in der Verzeichnis-Allowlist"
    return ["grep", f"-{flags}", "--exclude=*.env", "--", muster, pfad], None


def pruefe_lessons(inhalt):
    """Prueft den Inhalt fuer lessons_schreiben().
    Rueckgabe (text, None) oder (None, grund)."""
    t = str(inhalt)
    if len(t.strip()) < 20:
        return None, "abgelehnt: Inhalt zu kurz (mindestens 20 Zeichen — keine Leer-Ueberschreibung)"
    if len(t) > MAX_LESSONS_ZEICHEN:
        return None, (f"abgelehnt: Inhalt zu lang ({len(t)} Zeichen, Deckel "
                      f"{MAX_LESSONS_ZEICHEN}) — LESSONS.md ist ein Destillat, kein Archiv")
    if not t.endswith("\n"):
        t += "\n"
    return t, None


# ----------------------------------------------------------------------- Tools

def lies(pfad: str, max_zeichen: int = 50000) -> str:
    """Liest eine Datei aus dem konfigurierten Repo (utf-8).

    pfad ist repo-relativ, z.B. 'STATUS.md', 'AGENTS.md',
    'orchestrator/handoff/M1/REVIEW.md', 'orchestrator/state/M3/gates.json',
    'orchestrator/logs/<datei>.log'. Bei Ueberlaenge kommen Kopf und Schwanz,
    Kuerzung markiert; fuer das praezise Ende grosser Logs: befehl('tail -n ...').
    """
    voll, grund = pruefe_pfad(pfad)
    if voll is None:
        logge("lies", grund, pfad)
        return grund
    logge("lies", "ok", f"{pfad} max_zeichen={max_zeichen}")
    if not os.path.isfile(voll):
        return f"Fehler: keine Datei: {pfad}"
    try:
        max_zeichen = max(100, min(int(max_zeichen), 500000))
    except (TypeError, ValueError):
        max_zeichen = 50000
    try:
        with open(voll, "r", encoding="utf-8", errors="replace") as f:
            text = f.read()
    except OSError as e:
        return f"Fehler beim Lesen: {e}"
    if len(text) <= max_zeichen:
        return text
    kopf = text[: max_zeichen * 2 // 3]
    schwanz = text[-(max_zeichen // 3):]
    fehlt = len(text) - len(kopf) - len(schwanz)
    return (kopf
            + f"\n\n[... GEKUERZT: {fehlt} Zeichen ausgelassen, Datei gesamt {len(text)} Zeichen ...]\n\n"
            + schwanz)


def liste(pfad: str = ".") -> str:
    """Listet ein Verzeichnis im konfigurierten Repo (Name, Groesse, mtime).

    Maximal 2 Ebenen tief; .git und .env-artiges bleiben ausgeblendet, grosse
    Bau-Verzeichnisse (node_modules, dist, ...) werden nicht rekursiv betreten.
    Startpunkte fuer die Orchestrator-Analyse: 'orchestrator',
    'orchestrator/handoff', 'orchestrator/state', 'orchestrator/logs'.
    """
    voll, grund = pruefe_pfad(pfad)
    if voll is None:
        logge("liste", grund, pfad)
        return grund
    logge("liste", "ok", pfad)
    if not os.path.isdir(voll):
        return f"Fehler: kein Verzeichnis: {pfad}"

    zeilen = []
    MAX_EINTRAEGE = 400

    def eine_ebene(verz, einzug, tiefe):
        try:
            eintraege = sorted(os.scandir(verz),
                               key=lambda e: (not e.is_dir(follow_symlinks=False), e.name.lower()))
        except OSError as e:
            zeilen.append(f"{einzug}[Fehler: {e}]")
            return
        for e in eintraege:
            if len(zeilen) >= MAX_EINTRAEGE:
                return
            if e.name == ".git" or ".env" in e.name:
                continue
            try:
                st = e.stat()
                mtime = datetime.datetime.fromtimestamp(st.st_mtime).strftime("%Y-%m-%d %H:%M")
                groesse = st.st_size
            except OSError:
                mtime, groesse = "?", 0
            if e.is_dir(follow_symlinks=False):
                zeilen.append(f"{einzug}{e.name}/  ({mtime})")
                if tiefe < 2 and e.name not in KEINE_REKURSION:
                    eine_ebene(e.path, einzug + "    ", tiefe + 1)
            else:
                zeilen.append(f"{einzug}{e.name}  {groesse} B  ({mtime})")

    eine_ebene(voll, "", 1)
    if len(zeilen) >= MAX_EINTRAEGE:
        zeilen.append(f"[... gekuerzt bei {MAX_EINTRAEGE} Eintraegen ...]")
    return "\n".join(zeilen) if zeilen else "(leer)"


def befehl(cmd: str) -> str:
    """Fuehrt einen rein lesenden Befehl im konfigurierten Repo aus — nur bei exaktem
    Allowlist-Treffer.

    Erlaubt: git status[ --short], git log --oneline[ -N], git diff[ --stat]
    [pfad], git show <sha>[ --stat], wc -l <pfad>, tail -n N <pfad>,
    grep -n|-rn <muster> <pfad> (Muster: alphanumerisch beginnend, Zeichen
    aus [A-Za-z0-9_.:-]). Rekursives grep ist auf orchestrator/logs,
    orchestrator/state, orchestrator/handoff und docs begrenzt und erzwingt
    den Ausschluss von *.env. Pfade sind repo-relativ ohne fuehrenden Punkt/Slash.
    Alles andere wird abgelehnt — insbesondere startet dieser Kanal keine
    Laeufe (kein bash, npm, rm): Laeufe startet der Betreiber im Terminal.
    """
    c = str(cmd).strip()
    ok, wert = pruefe_befehl(c)
    if not ok:
        logge("befehl", wert, c)
        return wert
    timeout = wert
    pfad_treffer = re.fullmatch(
        rf"^(?:git diff(?: --stat)?|wc -l|tail -n [0-9]{{1,4}}) (?P<pfad>{PFAD})$",
        c,
    )
    if pfad_treffer is not None:
        _voll, pfad_fehler = pruefe_pfad(pfad_treffer.group("pfad"))
        if pfad_fehler is not None:
            logge("befehl", pfad_fehler, c)
            return pfad_fehler
    logge("befehl", f"ok (timeout {timeout}s)", c)
    grep_befehl, grep_fehler = grep_argv(c)
    if grep_fehler is not None:
        logge("befehl", grep_fehler, c)
        return grep_fehler
    try:
        lauf = subprocess.run(
            grep_befehl if grep_befehl is not None else [BASH, "-c", c],
            cwd=REPO,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired as e:
        teil = ""
        if e.output:
            teil = e.output.decode("utf-8", errors="replace")[-4000:]
        return (f"TIMEOUT: Befehl nach {timeout}s abgebrochen: {c}\n"
                f"Letzte Ausgabe:\n{teil}")
    except OSError as e:
        return f"Fehler beim Start des Befehls: {e}"
    aus = lauf.stdout.decode("utf-8", errors="replace") if lauf.stdout else ""
    if len(aus) > MAX_BEFEHL_AUSGABE:
        fehlt = len(aus) - MAX_BEFEHL_AUSGABE
        aus = f"[... Anfang gekuerzt, {fehlt} Zeichen ausgelassen ...]\n" + aus[-MAX_BEFEHL_AUSGABE:]
    return f"Exit-Code: {lauf.returncode}\n{aus}"


def lessons_schreiben(inhalt: str, nachricht: str = "analyst: LESSONS.md aktualisiert",
                      committen: bool = True) -> str:
    """Schreibt orchestrator/LESSONS.md im konfigurierten Repo — der einzige Schreibpfad
    dieses Servers. Vollersatz, kein Append: der Aufrufer kuratiert die ganze
    Datei (destillierte Lehren, gedeckelt; Normen/Schwellen bleiben ADR-exklusiv).

    committen=True versucht danach 'git add + commit' NUR fuer diese Datei, mit
    Wiederholungen falls der Orchestrator gerade den git-Index sperrt; schlaegt
    das fehl, bleibt die Datei geschrieben und der Commit dem Betreiber
    ueberlassen. Deckel: 16000 Zeichen. Review: befehl('git diff orchestrator/LESSONS.md').
    """
    text, grund = pruefe_lessons(inhalt)
    if text is None:
        logge("lessons_schreiben", grund, f"laenge={len(str(inhalt))}")
        return grund

    ziel = os.path.join(REPO, LESSONS_REL)
    try:
        os.makedirs(os.path.dirname(ziel), exist_ok=True)
        with open(ziel, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
    except OSError as e:
        logge("lessons_schreiben", "Fehler: nicht schreibbar", f"laenge={len(text)}")
        return f"Fehler: {LESSONS_REL} nicht schreibbar: {e}"
    logge("lessons_schreiben", "ok (geschrieben)", f"laenge={len(text)} committen={committen}")

    if not committen:
        return f"geschrieben: {LESSONS_REL} ({len(text)} Zeichen), ohne Commit (committen=False)."

    def git_lauf(argumente, eingabe=None):
        return subprocess.run(
            [GIT, *argumente], cwd=REPO, input=eingabe,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120,
        )

    msg = str(nachricht).strip() or "analyst: LESSONS.md aktualisiert"
    try:
        letzte = ""
        for versuch in range(4):
            add = git_lauf(["add", "--", LESSONS_REL])
            if add.returncode != 0:
                letzte = add.stdout.decode("utf-8", errors="replace")
                if "index.lock" in letzte:
                    time.sleep(1.5)
                    continue
                break
            probe = git_lauf(["diff", "--cached", "--quiet", "--", LESSONS_REL])
            if probe.returncode == 0:
                logge("lessons_schreiben", "ok (unveraendert, kein Commit)", LESSONS_REL)
                return (f"geschrieben: {LESSONS_REL} ({len(text)} Zeichen) — inhaltlich "
                        f"unveraendert, kein Commit noetig.")
            c = git_lauf(["commit", "-F", "-", "--", LESSONS_REL],
                         eingabe=msg.encode("utf-8"))
            if c.returncode == 0:
                kopf = git_lauf(["log", "--oneline", "-1"])
                zeile = kopf.stdout.decode("utf-8", errors="replace").strip()
                logge("lessons_schreiben", "ok (committet)", zeile)
                return f"geschrieben und committet: {LESSONS_REL} — {zeile}"
            letzte = c.stdout.decode("utf-8", errors="replace")
            if "index.lock" in letzte:
                time.sleep(1.5)
                continue
            break
    except subprocess.TimeoutExpired:
        letzte = "TIMEOUT: git-Aufruf nach 120s abgebrochen."

    logge("lessons_schreiben", "geschrieben, Commit offen", letzte[:120])
    return (f"geschrieben: {LESSONS_REL} ({len(text)} Zeichen). Commit fehlgeschlagen "
            f"(vermutlich git-Lock des laufenden Orchestrators) — bitte vom Betreiber "
            f"committen. git-Ausgabe:\n{letzte.strip()}")


# ------------------------------------------------------------------ Selbsttest

def selbsttest():
    """Prueft die Guards statisch; dazu EIN echter Mini-Lauf
    befehl('git status --short'), falls REPO existiert. Kein Serverstart.
    Die vollstaendige Allowlist-Abnahme liegt in
    orchestrator/mcp/tests/test_allowlist.py."""
    faelle = []

    def fall(beschreibung, bestanden):
        faelle.append(bestanden)
        print(f"{'OK  ' if bestanden else 'FAIL'}  {beschreibung}")

    ok, _ = pruefe_befehl("rm -rf /")
    fall("befehl abgelehnt: rm -rf /", not ok)

    ok, _ = pruefe_befehl("git status; git log")
    fall("befehl abgelehnt (Semikolon): git status; git log", not ok)

    ok, _ = pruefe_befehl("bash start.sh")
    fall("befehl abgelehnt: bash start.sh (Laeufe startet der Betreiber)", not ok)

    ok, t = pruefe_befehl("git log --oneline -120")
    fall("befehl akzeptiert: git log --oneline -120", ok and t == 60)

    ok, _ = pruefe_befehl("tail -n 200 orchestrator/logs/M3-50-code-review-r3.log")
    fall("befehl akzeptiert: tail auf orchestrator/logs/...", ok)

    ok, _ = pruefe_befehl("tail -n 40 /etc/passwd")
    fall("befehl abgelehnt: tail auf absoluten Pfad", not ok)

    ok, _ = pruefe_befehl("wc -l --files0-from=x")
    fall("befehl abgelehnt: Options-Schmuggel bei wc", not ok)

    ok, _ = pruefe_befehl("grep -rn ESCALATE orchestrator/logs")
    fall("befehl akzeptiert: grep -rn ESCALATE orchestrator/logs", ok)

    ok, _ = pruefe_befehl("grep -rn -e orchestrator/logs")
    fall("befehl abgelehnt: grep-Muster '-e' (Options-Schmuggel)", not ok)

    voll, _ = pruefe_pfad("../.env")
    fall("lies abgelehnt: ../.env", voll is None)

    voll, _ = pruefe_pfad(".env")
    fall("lies abgelehnt: .env", voll is None)

    voll, _ = pruefe_pfad("/etc/passwd")
    fall("lies abgelehnt: /etc/passwd", voll is None)

    voll, _ = pruefe_pfad(".git/config")
    fall("lies abgelehnt: .git/config", voll is None)

    voll, _ = pruefe_pfad("STATUS.md")
    fall("lies akzeptiert: STATUS.md", voll is not None)

    voll, _ = pruefe_pfad("orchestrator/handoff/M1/REVIEW.md")
    fall("lies akzeptiert: orchestrator/handoff/M1/REVIEW.md", voll is not None)

    text, grund = pruefe_lessons("")
    fall("lessons abgelehnt: leerer Inhalt", text is None and "zu kurz" in str(grund))

    text, grund = pruefe_lessons("x" * (MAX_LESSONS_ZEICHEN + 1))
    fall("lessons abgelehnt: ueber Deckel", text is None and "zu lang" in str(grund))

    text, _ = pruefe_lessons("## Lessons\n- Stryker braucht eine gruene Suite als Baseline.")
    fall("lessons akzeptiert: gueltiger Inhalt (Newline ergaenzt)",
         text is not None and text.endswith("\n"))

    fall("Schreibpfad-Konstante unveraendert: orchestrator/LESSONS.md",
         LESSONS_REL == "orchestrator/LESSONS.md")

    if os.path.isdir(REPO):
        print(f"\nMini-Lauf: befehl('git status --short') in {REPO}")
        antwort = befehl("git status --short")
        print(antwort if len(antwort) < 800 else antwort[:800] + " [...]")
        fall("Mini-Lauf: Exit-Code 0", antwort.startswith("Exit-Code: 0"))
    else:
        print(f"\n(Mini-Lauf uebersprungen: REPO {REPO} existiert hier nicht — "
              f"REPO_PATH setzen, um ihn zu fahren.)")

    print(f"\nSelbsttest: {sum(faelle)}/{len(faelle)} OK")
    return 0 if all(faelle) else 1


# ----------------------------------------------------------------------- Start

def starte_server():
    # Spaeter Import, damit --selftest auch ohne installiertes mcp-Paket laeuft.
    from mcp.server.fastmcp import FastMCP
    from mcp.server.transport_security import TransportSecuritySettings

    # Host-Header-Check aus: FastMCP aktiviert fuer 127.0.0.1 sonst automatisch
    # DNS-Rebinding-Schutz (nur localhost erlaubt) und beantwortet Requests mit
    # dem Tunnel-Host mit 421. Bei Quick Tunnels wechselt der Host je Start und
    # kann nicht vorab gepinnt werden; Schutz leisten Allowlist und Pfad-Guards.
    # Stateless vermeidet eine Bindung des entfernten Clients an eine Session.
    server = FastMCP(
        SERVER_NAME, host=HOST, port=PORT, streamable_http_path=MCP_PATH,
        transport_security=TransportSecuritySettings(enable_dns_rebinding_protection=False),
        stateless_http=True,
    )
    server.tool()(lies)
    server.tool()(liste)
    server.tool()(befehl)
    server.tool()(lessons_schreiben)
    print(f"{SERVER_NAME}: MCP-Server auf http://{HOST}:{PORT}{MCP_PATH} (REPO={REPO})", flush=True)
    server.run(transport="streamable-http")


if __name__ == "__main__":
    if "--selftest" in sys.argv[1:]:
        sys.exit(selbsttest())
    if not os.path.isdir(REPO):
        sys.exit(f"FEHLER: Repo nicht gefunden: {REPO} — REPO_PATH setzen.")
    starte_server()
