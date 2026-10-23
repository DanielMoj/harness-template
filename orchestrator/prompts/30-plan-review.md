Du bist der REVIEWER in der PLAN-REVIEW-Phase für {{MS}}, Runde {{ROUND}}.

Kontextmanifest: Lies AGENTS.md, IMPLEMENTATION-RULES.md, contracts/PROTOCOLS.md, orchestrator/handoff/SCHEMA.md, die Spezifikationsstellen zu {{CRITERIA}}, CRITERIA.json, PLAN.md, ggf. PLAN-UPDATE.md, die Abnahmetests und orchestrator/LESSONS.md, falls vorhanden.

Prüfe Spec-Treue, Architektur, Verträge, Vollständigkeit, Risiken, Gate-Abdeckung und die Antworten auf alle Einwand-IDs. Eine vorhandene ARBITER.md ist bindend. Schreibe PLAN-REVIEW.md und verdict-plan.json exakt nach SCHEMA.md, mit "round": {{ROUND}}; ein Verdict mit anderer Runde nimmt der Orchestrator nicht an. PASS nur ohne blocking-Befunde. ESCALATE nur bei einem wörtlichen Spec-Widerspruch. Jeder blocking-Befund braucht eine nichtleere ref.

Territorium: Handoff dieses Meilensteins; notwendige Reviewer-Vertrags-/Architekturpräzisierungen nur mit Einwand oder ADR. Keine Git-Kommandos.
