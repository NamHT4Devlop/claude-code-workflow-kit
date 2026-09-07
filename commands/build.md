---
description: Build a feature end-to-end — size → plan → safety net → code → independent review → tests (incl. regression) → verify vs baseline → evidence → KB → handoff
argument-hint: <requirement to implement, or a path to a story/plan under cwk-sessions/>
---

Use the **cwk-build** skill to implement the following requirement, following its pipeline exactly.
If a user story / plan is given (path, session folder, story id, link or pasted text), **read it and
treat its acceptance criteria as already approved — build from it without re-asking**. Answer open
questions from the story, the `knowledge-base/` and the code before asking the user anything; ask only
what the evidence genuinely can't decide, all at once, with your recommended defaults. Size the change
(S/M/L) so the apparatus fits the risk, capture the **safety net** (baseline gates + snapshot) before the first edit,
review through independent sub-agents that didn't write the code, and verify against that baseline —
reverting via the safety net rather than leaving the tree broken. Ground everything in the repo's
`knowledge-base/` and do NOT break the documented architecture.

Requirement:
$ARGUMENTS

If the requirement is empty or vague, ask 2–4 targeted clarifying questions before building. Stop and
ask — even if the request said "go" — for a DB migration, a new dependency, a published API/event
contract change, or any deletion.
