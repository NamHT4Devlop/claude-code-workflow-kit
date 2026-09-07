---
name: namht-plan
description: >-
  Act as a Product Owner / Business Analyst — turn an Epic (title + description)
  into Features → per-feature Impact Analysis (old flow ↔ new flow) → a
  stakeholder Confirmation Checklist → User Stories with Given/When/Then
  acceptance criteria and story points → a Sprint Plan, grounded in the
  Knowledge Base, with a plain-language executive summary so non-technical stakeholders
  and the dev team both follow it. Use when the user asks to "/plan", "plan user stories",
  "break down this epic", or wants PO/BA artifacts.
---

# Spec Plan — Epic → user stories (PO/BA)

A native port of Auto Spec extension's `/plan`. You are a senior BA + Product Owner. Understand
INTENT before solution. Ground everything in the repo's `knowledge-base/`; discover HIDDEN
requirements (implicit rules, side effects) from it.

**Dual audience:** the plan is read by BOTH non-technical stakeholders (founder / sponsor / ops)
and the dev team. Every feature and the epic get a **plain-language "what & why"** a non-tech
reader fully understands (no jargon, or define it), AND the technical depth devs need (technical
notes, API endpoints, dependencies). Lead each section plain → precise.

## Input
Ask for (or accept) the **Epic Title** and **Epic Description** (problem, goals, constraints).
That's all you need — derive the features yourself.

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
- `provenlens explore "<feature area>"` before sizing. Story points derived from the real number of
  touched symbols beat points derived from how the requirement is worded.
- `provenlens impact` on the entity or service a feature changes → the Impact Analysis section's
  "old flow ↔ new flow" gets a consumer list instead of an assumption.

## 8-step pipeline
1. **KB Deep Investigation** — from the KB, gather: related entities (existing + new),
   applicable business rules (validation, authorization, state-machine, calculation,
   time-based, invariants), affected flows, integrations, and affected modules. Cite KB sources.
2. **Auto Feature Discovery** — split the Epic into **3–8 features**, ordered by dependency;
   include cross-cutting features (auth, audit, migration) when needed. For each: id, title,
   a one-line **plain "what & why" (non-tech, no jargon)**, description, scope (in/out),
   affected entities, affected flows, complexity (Low/Med/High).
3. **Impact Analysis per feature** — for each feature: EXISTING flow (before) → NEW flow
   (after, step by step) → DELTA / breaking changes (data model, API, state machines,
   permissions, integrations) → migration / backward compatibility → dependencies. With an index,
   each feature's DELTA carries a **reach ledger** and a pasted **code graph**
   (`references/provenlens-evidence.md`) in `impact-analysis-<epic>-<date>.md`; a consumer the graph
   reaches that no story covers is a 🔴 item in step 4, not a silence.
4. **Confirmation Checklist** — categorize open questions: 🔴 MUST CONFIRM BEFORE DEV
   (blocking), 🟡 SHOULD CLARIFY EARLY, 🔵 ASSUMPTIONS MADE (validate later), ⚪ OUT OF SCOPE.
   Each item: clear question/assumption, context, who to ask (PO/Tech Lead/Designer/Security),
   related feature.
5. **User Story Generation** — per feature, ≥3 stories. Each story: id (`US-F1-001`), title,
   role, action, benefit, priority (P1/P2/P3), story points (1/2/3/5/8/13), sprint, ≥3
   acceptance criteria in **Given/When/Then** (happy + error + edge), definition of done,
   impactNotes (BEFORE vs AFTER flow), technical notes, API endpoints, dependencies. Include
   an auth story if the feature is access-restricted, and error-handling for critical flows.
6. **Sprint Planning** — assign sprints respecting dependencies; ~35 points/sprint capacity;
   P1 stories in early sprints; Sprint 1 must deliver MVP value. Note total points and
   estimated sprints (points ÷ 35).
7. **Output** — write artifacts under `namht-sessions/plans/`:
   - `user-stories-<epic>-<date>.md` (and/or JSON) — the full backlog with a sprint board.
   - `impact-analysis-<epic>-<date>.md`
   - `confirmation-<epic>-<date>.md`
   The backlog doc MUST open with an **Executive summary (for non-tech stakeholders)**: 3–6
   bullet points in plain language — what we're building, the business value, rough size
   (sprints), and the top risks / things to confirm — before any technical story detail.
   Then summarize: total stories, total points, estimated sprints, and the count of 🔴 must-confirm items.
8. **Show in chat + render HTML.** Present the executive summary + backlog highlights in chat,
   then render the backlog Markdown to a self-contained HTML (styled, Mermaid drawn) and open it.
   Resolve this skill's `references/` dir first (call it `$SKILL_DIR`): `${CLAUDE_PLUGIN_ROOT}/skills/namht-plan/references`
   if `CLAUDE_PLUGIN_ROOT` is set, else the `references/` folder next to this SKILL.md, else `$HOME/.claude/skills/namht-plan/references`.
   ```bash
   node "$SKILL_DIR/render-html.cjs" \
     "<repo>/namht-sessions/plans/user-stories-<epic>-<date>.md" \
     "<repo>/namht-sessions/plans/user-stories-<epic>-<date>.html" "<epic title>"
   # then: open / xdg-open / start  the printed path
   ```
   Requires Node — if absent, keep chat + `.md` and note HTML was skipped. Give the user the path.

Acceptance criteria must be specific and measurable (not vague). Every story should be
independent, valuable, testable, and fit one sprint.

Scope: this plans a whole Epic through sprints. For a SINGLE requirement needing maximally
granular ACs (or a Slack-thread source), use `/namht-user-story` instead.

**Next steps:** `/namht-plan-review <plan path>` to critique the plan before anyone codes, then
`/namht-build <story id or path>` per story (its ACs are already confirmed — build must not re-ask),
and `/namht-qa <story>` for the test plan.
