---
description: Audit the whole repo for drift between the docs/KB and the real code — stale entries, undocumented behavior, unshipped ACs, broken invariants
argument-hint: "[scope — blank = whole repo] [--fix-docs to also refresh the stale KB entries]"
---

Use the **cwk-drift** skill to audit this repository for **drift** between what the documents
claim and what the code actually does. Read-only — change nothing.

Cover the four kinds: stale Knowledge Base entries (D1), real behavior no document describes (D2),
acceptance criteria from past stories/plans in `cwk-sessions/` that were never implemented (D3),
and violations of the "Architecture Invariants — DO NOT BREAK" list (D4). Verify every candidate
against the source yourself — cite `file:line` on one side and the document line on the other, and
say explicitly which side is wrong. Rank by consequence, give a verdict
(CONVERGED / DRIFTING / STALE), then hand each finding to its fix route: `/cwk-rescan` for docs,
`/cwk-build` for unshipped ACs, `/cwk-review` for invariant breaks. Save the report under
`cwk-sessions/drift/` and append a row to its journal.

If the arguments contain **`--fix-docs`**, run the skill's opt-in mode after the audit: offer to
close only the findings Step 3 concluded were **the document's** fault (D1/D2), show exactly which
`knowledge-base/` files would change, take ONE explicit yes, back those files up under
`cwk-sessions/drift/<date>-kb-backup/`, then delegate the write to `/cwk-rescan` and re-verify.
Never edit source code, never auto-resolve D3/D4, and never relax a documented invariant to match
the code.

Scope (blank = whole repo) and flags:
$ARGUMENTS
