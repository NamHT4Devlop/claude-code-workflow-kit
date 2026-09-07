---
name: cwk-migrate
description: >-
  Change a shared contract without breaking anyone — an API field/endpoint, a DB
  schema (Flyway/ActiveRecord), an SQS/event message shape, or a library version.
  Uses the parallel-change (expand → migrate → contract) pattern with a rollback
  per step and a deprecation window, and finds every consumer across services
  first. Use when the user says "/migrate", "deprecate X", "schema change",
  "breaking change", "version bump", "upgrade <lib>". Edits code — change-discipline applies.
---

# cwk-migrate — change a shared contract safely, with nobody paged

The dangerous moment in a microservice system is changing something **other services depend on**. The
whole skill is one idea: **never flip a breaking change in one step** — run old and new in parallel,
move consumers, then remove the old only once nothing uses it.

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
- `provenlens impact <symbol|handler>` — every transitive consumer, including the ones grep cannot
  reach through an interface or a mixin. This is the consumer list the expand→migrate→contract plan
  is built from; a missed consumer is a broken contract.
- **Across services:** index each repo (`provenlens init .`), then query from the workspace root — a
  shared queue name or endpoint URI links a producer in one repo to a consumer in another, across
  languages. Those are precisely the consumers a contract change breaks and the ones prose misses.
- A consumer you cannot find in the graph is not proof of absence: say which repos were indexed.

## Step 1 — find who depends on it (before touching anything)
A change is only "safe" once every consumer is known.
- **Cross-service** consumers: the **Event/Contract Catalog** (`17-async-events.md`) + `system-map/`
  give you who publishes/consumes each queue/topic and which services call each endpoint.
- **In-repo** consumers: grep callers of the symbol/endpoint/column.
- Classify each: compatible (additive) vs **breaking** (removed/renamed/retyped/semantics changed).

## Step 2 — pick the safe strategy (parallel change)
Default: **expand → migrate → contract**, shipped as separate, independently deployable steps.
- **DB (Flyway / ActiveRecord / Prisma):** additive first — add a **nullable** column / new table
  (`V<n>__add_x`), **backfill** in a batched job, **dual-write** old+new, switch reads, then **drop
  the old in a LATER migration** once nothing reads it. Never rename/drop in the same release as the switch.
- **API:** add fields as optional; for breaking shape changes use a **versioned** path (`/v2`) or
  content negotiation; keep `/v1` until consumers move.
- **SQS / events:** add a `schemaVersion` and make producers emit and consumers **tolerantly read**
  both old and new (a "tolerant reader"). Route unknown/older versions to a **DLQ** rather than crashing.
  Assume **version skew** — during rollout, producers and consumers run different versions.
- **Library upgrade:** read the changelog for breaking changes; upgrade behind tests; isolate risky
  APIs behind a thin adapter so the blast radius is one file.

## Step 3 — deprecation path for the old thing
Mark deprecated (annotation/comment/doc) → emit a **warning + a metric/log** when the old path is used
(so you can watch usage drop to zero via `/cwk-observe` + `/cwk-splunk-report`) → give a grace
window → remove only when usage is zero.

## Method
1. **Impact map** (Step 1) — the full consumer list, breaking vs compatible.
2. **Staged plan** — ordered steps, what ships per step, the **rollback for each**, backfill/data plan,
   and the deprecation window. Show it, get an OK.
3. **Execute step by step** with change-discipline (minimal diff, verify build/tests each step,
   rollback if red). Write real migration scripts — additive first.
4. **Prove old consumers still work** before contracting — hand the regression set to `/cwk-qa`.

## Output (dual-audience; save + report)
Chat summary + `cwk-sessions/migrate/<change>-<date>.md`: impacted consumers, the staged plan
with per-step rollback, migration scripts, and the deprecation timeline.

## Rules
- **Backward-compatible first** — never break a consumer without a deprecation window and a migration path.
- **Every step is reversible** — destructive/irreversible steps (drop column, delete data) need
  **explicit confirmation** plus a backup/backfill first.
- **DB migrations are additive-then-cleanup**, never destructive-in-one-step; confirm before running any migration.
- Design for **version skew** — assume mixed versions in flight during every rollout.
- **Executable gate before the contract step.** Proving old consumers still work must be a test run,
  not a document: write regression tests asserting the OLD shape still works (old column readable,
  `/v1` response unchanged, a tolerant reader accepting the previous `schemaVersion`), **run them
  green, and record the run**. `/cwk-qa` only *designs* cases — it does not execute them; run them
  here, or via `/cwk-qa-integration` against a running app. **Never contract on a design document.**
- **Safety net — before the first edit.** `git status --porcelain` (ask the user to commit/stash first)
  and save `git diff HEAD > <session>/00-pre-change.patch`. To undo use ONLY `git stash push -u` or
  `git apply -R <your diff>` — the git-guard denies `git restore`, `git checkout .`/`--`,
  `git reset --hard`, `git clean -f`. (Note this is separate from a **DB** rollback: every migration
  step still needs its own reversible down-migration.)
- Change-discipline: scope-lock, minimal diff, verify + rollback, never touch secrets, confirm outward/destructive actions.

## Common rationalizations

| What you'll tell yourself | What's actually true |
|---|---|
| "The consumers will just update" | Name them. If you cannot list them, you have not finished searching — and cross-service consumers do not read your commit. |
| "Expand → migrate → contract is overkill here" | Then say **which step you are skipping** and what breaks for a consumer that lags a release. If you can't answer that, don't skip it. |
| "We can contract in the same deploy" | Only if no consumer can still be running the old shape at that instant. That is a claim about deploy order — verify it, don't assume it. |
| "It's backward compatible, I'm sure" | Adding a required field, narrowing a type, or removing an enum value is not. Check against the real contract, not memory. |

## Red flags

- The contract step is scheduled in the **same deploy** as expand.
- A step has no stated rollback.
- The deprecation window is "soon" rather than a date or a release.
- You found consumers by grep in **one** repo, in a system that has several.

## Verification

- [ ] Every consumer found and listed, across services — with how you found them.
- [ ] Each step has a rollback that was actually thought through.
- [ ] An **executable gate** exists before the contract step (a test that fails while a consumer still needs the old shape).
- [ ] Deprecation window stated as a date/release, and communicated.
- [ ] Old and new shapes both work for the whole window.
