---
name: cwk-qa
description: >-
  Turn a user story (role/action/benefit + acceptance criteria) into a complete
  QA test plan: derive test cases for the NEW flow (happy/alternate/error/edge/
  negative/permission/state) AND regression cases for the EXISTING (old) business
  flows the change touches — grounded in the Knowledge Base — with a
  traceability matrix (AC ↔ case ↔ flow), Gherkin + a manual test-case table.
  Use when QA receives a story and needs test cases, or the user says "/qa",
  "write test cases", "test plan", "QA for this story", "cover old and new flow".
---

# cwk-qa — user story → test cases covering OLD + NEW business flows

For QA: take a user story and produce a **test plan a tester can execute**, that deliberately
covers BOTH the new behavior AND the existing flows it could break (regression). Grounds the
"old flow" in the repo's Knowledge Base (`10-core-flows`, `13-business-rules`, `modules/<m>`) and
the code (real endpoints/handlers). This is **test design** — it does NOT write or run code
(hand to `/cwk-build` for automation if needed).

## Inputs
- The **user story** (role / action / benefit) + its **acceptance criteria**. Accept it pasted,
  by ID, or from a `/cwk-plan` output under `cwk-sessions/`. If ACs are missing or vague,
  derive a draft set and flag assumptions (don't silently guess).
- A **`/cwk-build` session folder** (`cwk-sessions/builds/<…>/`), if one exists — read
  `01-plan/plan.md` §2 (blast radius, cross-service consumers, risk matrix) and
  `07-evidence/EVIDENCE.md` (the AC → named-test map) and **reuse them instead of re-deriving**: the
  build already traced the callers. Your job is then the **delta** — manual/UI cases automated tests
  can't cover, regression targets the build's tests did NOT cover, and any AC the evidence marked ❌ or
  untested. Say which targets came from the build plan vs your own analysis.
- The **feature/module** it touches (infer from the story; confirm via the KB/code).
- If the repo has no `knowledge-base/`, say so — old-flow/regression coverage will be weaker;
  suggest `/cwk-scan`. Read the relevant controllers/handlers to find the exact
  endpoints/handlers/state machines involved.

### provenlens (optional)
`.provenlens/` present → prefer `provenlens` over grep for anything about **who calls what**: it resolves
through DI, interfaces, mixins and framework string-bindings (MyBatis · Camel · SQS · Kafka · HTTP routes · Spring events · GraphQL · gRPC · Flyway) and
scores every edge. Confirm it with `provenlens status`, and run `provenlens sync` first if the working
tree has moved since it was built — **a stale index is worse than none, because it looks
authoritative**. If coverage reads low, `provenlens doctor` says whether that is a resolver limit or
just an uninstalled dependency; those look identical in the number and are nothing alike in the fix.
No index, no `provenlens` command, or a language it does not cover (**Java · Ruby · TS/JS** only) →
fall back to Grep/Glob and write `⚠️ grep-depth only (no provenlens index)` in the output. A grep hit
is never a resolved call — do not report it as one. Playbook: `docs/provenlens.md`.

**Here:**
- **Protocol:** `references/provenlens-evidence.md` — the evidence line, the **reach ledger** and the pasted **code graph** are required parts of this skill's output, not options; the ledger is what turns "nothing was missed" into a checked claim.
- `git diff --name-only | provenlens affected` — its `tests:` list names the existing tests that
  already cover the change (your regression set), and its **absence** is proof of the gap rather
  than a worry about one.
- `provenlens impact <changed symbol>` — the old flows that need regression cases. Each becomes a row
  in the traceability matrix, with the resolved caller as the evidence column.
- A regression case you cannot tie to a real consumer is a guess: label it, or drop it.

## Procedure
1. **Understand the story.** Restate role/action/benefit + each AC. List the entities, endpoints,
   states, roles and rules involved.
2. **Map the blast radius — THIS drives regression coverage.** Identify the symbols/endpoints the
   story will change, then use BOTH tools (they answer different halves):
   - **WHERE the impact is — grep for callers.** Grep/Read the changed symbols and their
     **callers/consumers**. Every caller is a **regression target** — including the **non-obvious**
     ones QA would never guess from the story alone (a shared helper/service used by other features).
     Note any changed symbol with **no covering tests** = highest-risk regression case.
   - **KB = WHAT business flow each impacted point belongs to.** Map those impacted
     symbols/endpoints to documented flows & rules (`10-core-flows`, `13-business-rules`,
     `modules/`) → the user-facing behavior each regression target protects.
   - **Cross-service (events/queues) — what a single-repo search can't see.** If the change touches a
     **published message / SQS topic / REST contract**, open the **Event/Contract Catalog**
     (`17-async-events.md` or the workspace `system-map/`): every **consumer service** of that channel is a
     **regression target in another repo**. Add async cases: duplicate delivery (idempotency), out-of-order,
     DLQ/poison handling, old-schema consumers (version skew). Name the downstream services explicitly.
   - **Result:** the **NEW flow** (from the story) + a concrete **regression set** =
     the caller set (grep) × KB flows/rules. With no KB, say the impact analysis is weaker
     (likely misses non-obvious consumers).
3. **Design NEW-flow cases** — for the new behavior, cover every angle:
   happy path · alternate/secondary paths · error & exception · **boundary/edge** (min/max,
   empty, null, very large) · **negative/invalid input** · **permission/role** (allowed vs
   forbidden) · **state-machine transitions** (valid + invalid) · data variations ·
   concurrency/duplicate/idempotency where relevant.
4. **Design REGRESSION cases (old flow)** — one per regression target in step 2's blast radius
   (each impacted caller/consumer/flow, **including the non-obvious shared helpers/services**).
   Write cases asserting the OLD behavior still holds after the change. Label `[REGRESSION]`, cite
   the KB rule/flow they protect (e.g. BR-V2, core-flow #3), and bump priority for targets
   flagged as having **no covering tests**.
5. **Non-functional (only if relevant)** — security (authz/IDOR, injection), input validation,
   rate/limits/performance, audit/logging.
6. **Traceability** — every AC maps to ≥1 case; every touched old flow has ≥1 regression case.
   Flag any AC with no case and any touched flow with no regression as a **coverage gap**.

## Output (dual-audience; save + render HTML)
Save to `cwk-sessions/qa/<story-slug>-<date>.md`, then render to HTML and open it.
Resolve this skill's `references/` dir first (call it `$SKILL_DIR`): `${CLAUDE_PLUGIN_ROOT}/skills/cwk-qa/references`
if `CLAUDE_PLUGIN_ROOT` is set, else the `references/` folder next to this SKILL.md, else `$HOME/.claude/skills/cwk-qa/references`.
Then: `node "$SKILL_DIR/render-html.cjs" <md> <html> "<story>"`.
Structure:
```
# QA Test Plan — <story title>

## In plain words (for non-tech: what's covered, why it's enough)
2–4 sentences: what the feature tests, which old flows are protected, total case count + risk level.

## Story & scope
role/action/benefit · acceptance criteria · modules/endpoints touched · old flows at risk.

## Traceability matrix
(the evidence column is the reach-ledger row — `references/provenlens-evidence.md` §2 — a resolved
caller with its confidence, or `(grep)`; a regression row with no ledger row is a guess, labelled)
| AC / Flow | Test case IDs | Type (new/regression) | Covered? |

## Test cases (Gherkin)
### TC-01 — <title>   [NEW · happy · P1]
Given … When … Then …
### TC-07 — <title>   [REGRESSION · protects BR-V2 / core-flow #3 · P1]
Given (existing precondition) … When … Then (old behavior unchanged) …

## Test cases (manual table)
| ID | Title | Type | Priority | Preconditions | Steps | Expected | Test data |

## Test data & environment
fixtures/users/roles needed; env notes.

## Coverage gaps & risks
ACs without a case, old flows without regression, ambiguities to confirm with PO/dev.
```

## Rules
- **Test data must be synthetic.** Make it concrete and executable, but never copy real customer
  records, production credentials, tokens or PII into the plan — invent representative values
  (`coach.test@example.com`, `+84900000001`). The plan is saved to disk, rendered to HTML/PDF and
  shared with testers.
- **Always include regression for the old flow** — this is the point; never produce only
  new-flow cases. If the change touches an existing flow and you wrote no regression case, that's
  a gap to call out.
- Cases must be **concrete and executable** (real fields/endpoints/values from the KB/code),
  not vague ("test the API"). Each case has a clear expected result.
- Prioritize (P1/P2/P3) and tag type ([NEW]/[REGRESSION]/[NEGATIVE]/[EDGE]/[SECURITY]).
- It's a plan for testers — don't edit app code. Offer to scaffold automated tests via
  `/cwk-build` if the user wants them coded.
