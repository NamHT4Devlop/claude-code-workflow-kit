---
name: cwk-plan-review
description: >-
  Critique an implementation plan or user-story plan BEFORE building, through
  multiple lenses — Product (right thing? simpler? scope creep), Architecture/Eng
  (fits existing patterns, blast radius, risk), Risk/QA (what breaks, regression,
  edge cases), DevEx (complexity, maintainability) — grounded in the KB,
  ending with a verdict (proceed / revise) + concrete fixes. Use when the user says
  "/plan-review", "review this plan", "is this plan good", or after /cwk-plan.
---

# cwk-plan-review — multi-lens critique of a plan (catch bad plans early)

A plan is the cheapest place
to fix a mistake. Review the plan (from `/cwk-plan`, `/cwk-discover`, or pasted) before code.

## Input
The plan / user stories (pasted, or a file under `cwk-sessions/`). Identify the feature + the
modules/entities it targets. Ground in KB (`13-business-rules`, `16-architecture-patterns`,
`10-core-flows`) and by tracing callers (blast radius of the proposed changes).

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
- The plan's own blast-radius claim is **checkable**: `provenlens impact <symbol>`. If the plan says
  "3 call sites" and impact returns 27, that is a ❌ blocker in the Architecture/Eng lens, not a ⚠️ —
  the plan is sized against a number that is wrong.
- `provenlens dead` on something the plan proposes to build around: if it is already unreachable, the
  plan is extending code nobody runs.

## Lenses (score each: ✅ ok / ⚠️ concern / ❌ blocker)
1. **Product** — is this the *right* thing? Is there a simpler version that delivers most value?
   Scope creep? Does it match the success metric? Anything that should be cut or deferred?
2. **Architecture / Eng** — does it follow the documented pattern & layer rules
   (`16-architecture-patterns`)? Blast radius (who else is affected — grep callers)? Migrations /
   breaking changes handled? Any risky shortcut?
3. **Risk / QA** — what existing flows could break (regression)? Edge cases, error paths,
   concurrency, permissions, data states the plan ignores? Is it testable?
4. **DevEx / Maintainability** — complexity added, duplication, naming, "will the next dev
   understand this?", premature abstraction (YAGNI).
5. **Reuse & Rollout** (when the plan came from `/cwk-build`) — check its **Reuse Report**: for every
   row marked `new`, does the justification name real searches, and can you find an existing candidate
   it missed (helper, service, DTO, constant/enum, config key, error code, message, i18n key, style
   token, test fixture)? Does it add a dependency an installed library already covers? Then check
   **Rollout & Reversibility**: feature flag (default, who flips it, when removed), deploy order
   (migration ↔ code), behavior under version skew, how to undo in production, new config/env vars,
   backfill. **A missing rollback plan is a ❌ blocker, not a ⚠️.**

## Output (dual-audience; chat + offer to save `cwk-sessions/plan-reviews/<slug>-<date>.md`)
```
## In plain words            ← is the plan good to proceed? 2–3 sentences
## Scorecard                 ← | Lens | ✅/⚠️/❌ | one-line reason |
## Findings                  ← per lens, concrete issues with the specific fix/change to the plan
## Missing / risky           ← gaps (edge cases, regression, migration) the plan should add
## Verdict                   ← PROCEED · PROCEED WITH CHANGES · REVISE — with the must-change list
```

## Rules
- Critique the PLAN, don't write code. Output actionable plan edits, not vague advice.
- Ground every "this will break X" in the KB (+ grep) (real flow/consumer), not speculation.
- If the plan is solid, say so plainly — don't invent objections.
- After revisions, hand to **`/cwk-build`** (or `/cwk-qa` for test design).

**Render it to HTML too.** Resolve this skill's `references/` dir first (call it `$SKILL_DIR`):
`${CLAUDE_PLUGIN_ROOT}/skills/cwk-plan-review/references` if `CLAUDE_PLUGIN_ROOT` is set, else the
`references/` folder next to this SKILL.md, else `$HOME/.claude/skills/cwk-plan-review/references`.
```bash
node "$SKILL_DIR/render-html.cjs" "<the .md just saved>" "<same path>.html" "Plan review — <slug>"
```
Then open it and give the user the path. (This is also what the VS Code panel's **📄 Report** button
looks for — without it the button has nothing to open.)
