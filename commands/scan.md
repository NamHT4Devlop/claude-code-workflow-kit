---
description: Scan the project and generate a deep, business-aware Knowledge Base (16 docs + review-skills + per-module docs)
argument-hint: "[scope] [quick|standard|deep]"
---

Use the **cwk-scan** skill to generate a `knowledge-base/` for this repository
(16 section docs, `review-skills.md` with a project-specific Section 14, and per-module docs).
Detect the stack first and tailor the analysis. Cite real file paths; no generic filler.

Scope (optional): $ARGUMENTS

**Depth** — `quick`, `standard` (default) or `deep`, the cost dial. On a large repo the skill
proposes `quick` first rather than silently spending an hour of tokens. **Use `deep` for a repo with
a lot of business logic**: it skips sampling entirely and writes a module document for every module.
The business layer — domain/service code, state machines, validators, calculations — is **never
sampled at any depth**, because a sampled KB there looks complete while missing the rules everything
else in the kit relies on.

**Give every business rule and core flow a stable id** (`BR-V2`, `CF-03`) and record, per rule, where
it is enforced and which test covers it — `NONE` in that column is a finding, not a blank.
`/cwk-qa`, `/cwk-build` and `/cwk-review` cite those ids to tie a regression test or a review
finding to the rule it protects, so ids are **append-only**: never renumber, never reuse a retired
one.

Say which depth you used, and list anything you deferred **by name** in `_coverage-report.md` — a
flow nobody knows is missing is worse than one that is.

If a `knowledge-base/` already exists, ask whether to do a fresh rebuild or use
`/cwk-rescan` instead.
