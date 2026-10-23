# Handoff-Schemata — bindend

## PLAN.md / PLAN-UPDATE.md (Builder)

Abschnitte: Ziel · Dateien · Schnittstellen · Reihenfolge · Risiken ·
Testplan. PLAN-UPDATE beantwortet jede Einwand-ID mit
`akzeptiert: <Änderung>` oder
`abgelehnt: <wörtliches Spec-Zitat mit Fundstelle>`.

## PLAN-REVIEW.md / REVIEW.md (Reviewer)

Je Einwand:

`- [E<nr>] (blocking|minor) <ref> — Befund — Vorschlag`

Gate-Ursachen außerhalb des Builder-Territoriums heißen `[INFRA]`; verlangte
Artefakte im QA-Territorium heißen `[QA-PENDING]`. Beide sind für den Builder
nonblocking und wandern nötigenfalls nach `BACKLOG.md`.

## verdict-plan.json / verdict-code.json (Reviewer)

```json
{"milestone":"M0","phase":"plan","round":1,"verdict":"PASS","blocking":[],"nonblocking":[]}
```

`verdict` ist `PASS|REWORK|ESCALATE`. PASS erfordert leeres `blocking`.
`round` ist die Runde aus dem Prompt. Der Orchestrator nimmt nur ein Verdict
der laufenden Runde an; fehlt es oder stammt es aus einer anderen Runde, endet
der Lauf mit FATAL, statt ein liegengebliebenes Verdict zu verwenden.
Jeder blocking-Eintrag hat
`{"id":"E1","ref":"Gate, Kriterium oder Spec-Fundstelle","note":"..."}`.
Ohne nichtleere `ref` ist der Befund definitionsgemäß nonblocking.

## ARBITER-REQUEST.md / ARBITER.md

Der Orchestrator erzeugt den Request. ARBITER.md gibt je strittigem Punkt
eine bindende Direktive mit wörtlichem Spec-Zitat und Fundstelle. Zu
entschiedenen Punkten sind keine neuen Einwände derselben Sache zulässig.

## verdict-arbiter.json

```json
{"milestone":"M0","phase":"code","round":8,"verdict":"RESOLVE","directive":"Kurzfassung"}
```

`verdict` ist `RESOLVE|HUMAN`. HUMAN ist ausschließlich bei einem echten
Widerspruch bindender Spec-Stellen zulässig; ARBITER.md enthält dann die
konkrete Betreiberfrage.

## MUT-EQUIV.json / MUT-EQUIV-APPROVED.json

Builder-Claim:

```json
{"claims":[{"file":"src/core.ts","mutator":"ConditionalExpression","line":42,"reason":"..."}]}
```

Reviewer-Approval:

```json
{"approved":[{"file":"src/core.ts","mutator":"ConditionalExpression","line":42}]}
```

Nur einzeln vom Reviewer approvte, nachweislich verhaltensgleiche Mutanten
verlassen den Nenner. Der Builder approvt nie selbst.

## REBUILD-BRIEF.md

Vom Orchestrator erzeugtes Destillat der blocking-Befunde, letzten Review-
Fakten und Gates vor dem Neuaufbau ab `plan/<MS>`.
