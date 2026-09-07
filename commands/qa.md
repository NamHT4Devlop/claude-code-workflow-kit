---
description: QA — turn a user story into test cases covering the NEW flow + regression for OLD business flows (Gherkin + manual table + traceability)
argument-hint: <user story + acceptance criteria (paste), or a story ID>
---

Use the **cwk-qa** skill to turn the user story below into a complete QA test plan: map the new
flow AND the existing (old) business flows it touches (via the KB), then design test cases
covering happy/alternate/error/edge/negative/permission/state for the NEW behavior **plus
[REGRESSION] cases asserting the OLD flows still work** — with a traceability matrix (every AC and
every touched flow covered), Gherkin + a manual test-case table. Save + render HTML. It designs
tests (doesn't code them); offer `/cwk-build` to automate if asked.

User story / acceptance criteria (or story ID):
$ARGUMENTS

If acceptance criteria are missing or vague, draft them and flag the assumptions before designing cases.
