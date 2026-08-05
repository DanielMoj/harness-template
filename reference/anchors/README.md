# Referenzanker

Jeder normative Erwartungswert liegt als eigene JSON-Datei vor:

```json
{
  "id": "ANK-01",
  "value": 1,
  "unit": "count",
  "tolerance": 0,
  "source_url": "https://example.invalid/primary-source",
  "quote": "Wörtliches, kurzes Beleg-Zitat aus der Quelle.",
  "retrieved": "YYYY-MM-DD"
}
```

Besitz: Reviewer. Der Builder liest Anker, ändert oder ergänzt sie nie.
Wertänderungen brauchen ein ADR. Unverifizierbares wird als Einwand
festgehalten, nie geschätzt.
