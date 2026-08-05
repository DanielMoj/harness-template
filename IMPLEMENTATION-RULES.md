# IMPLEMENTATION-RULES — verbindliche Bauregeln

Geltung: jede Produktänderung. Besitz: Reviewer. Der Builder befolgt diese
Regeln und schlägt Änderungen ausschließlich im PLAN vor. Bei Konflikt gilt
`AGENTS.md` vor dieser Datei.

## Kern

### Verträge und Schnittstellen

- Public APIs sind explizit, klein und in `contracts/PROTOCOLS.md` oder
  `contracts/api/**` beschrieben. Vertragslücken werden gemeldet, nicht
  geraten.
- Inkompatible Änderungen brauchen ein ADR und eine sichtbare
  Versionsgrenze. Additive Änderungen sind vorzuziehen.
- Architekturgrenzen werden durch ein Gate erzwungen, nicht nur in Prosa
  beschrieben.

### Determinismus und Daten

- Zufall ist injiziert, geseedet und reproduzierbar; Tests protokollieren
  Seeds. Unkontrollierter Zufall in Kernlogik ist verboten.
- Empirische Werte kommen aus `reference/anchors/**`; jeder Anker nennt
  Einheit, Toleranz, Quelle und wörtliches Beleg-Zitat.
- Fehlende Produktionsdaten führen zu einem benannten Fehler, niemals zu
  plausibel wirkenden Ersatzwerten.

### Fehler und Typen

- Der projektspezifisch strengste Compiler-/Validator-Modus bleibt aktiv.
  Unterdrückungen brauchen eine enge Begründung und dürfen keine echte
  Fehlerspur verbergen.
- Kerninvarianten scheitern früh; IO-Kanten liefern typisierte und
  beobachtbare Fehler. Fehler werden nicht stumm geschluckt.
- Hot Paths vermeiden unnötige Allokationen; messbare Budgets werden nur aus
  Ankern gelesen und durch Bench-Gates geprüft.

### Tests

- Abnahmetests tragen ihre Kriteriums-ID. Unit-Tests prüfen Verhalten,
  Grenzfälle und Fehlerpfade; Snapshots ersetzen keine Logikprüfung.
- Existiert ein Original, wird differentiell dagegen getestet. Ohne Orakel
  werden metamorphe Relationen, Property-Tests und Erhaltungssätze verwendet.
- Kritische Logik erhält im Reviewer-Territorium eine unabhängig formulierte
  Mini-Referenzimplementierung.
- Binär- und Dateiformate erhalten eine kleine echte Fixture und einen
  Reader-/Validator-Test.

### Dependencies und Werkzeuge

- Laufzeiten stehen in `toolchain.json`, Pakete in eingefrorenen Manifesten.
  Installationen erfolgen nur im Frozen-/Locked-Modus.
- Laufzeitwechsel sind Betreiber-Sache. Paketänderungen sind normale,
  prüfbare Builder-Commits; keine stillen globalen Installationen.
- Virtuelle Umgebungen, Paket-Caches und Bauartefakte liegen außerhalb des
  Arbeitsbaums oder auf allen relevanten Ignore-Listen.

### Belege und Commits

- Ein Phasen-Commit enthält genau ein Thema und wird vom Orchestrator nach
  Territoriumsprüfung erstellt.
- Jede Fertigmeldung enthält echten Kommando-Output. Gate-Fakten kommen aus
  `gates.json`; Modelle schreiben diese Datei nie.
- Öffentliche Funktionen, Datenformate und ungewöhnliche Algorithmen werden
  dort dokumentiert, wo ein späterer Reviewer sie beim Diff findet.

## Projekt-Amendments

_Leer. Format: `- [ADR-nnn] <Regel>`; nur per Reviewer-Commit._
