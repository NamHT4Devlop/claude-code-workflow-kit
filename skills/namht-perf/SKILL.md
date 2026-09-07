---
name: namht-perf
description: >-
  Make it faster on evidence, not hunches — measure the baseline, fix the single
  biggest bottleneck, re-measure to prove the win. Targets N+1 queries, missing
  indexes and full scans, over-fetching, blocking/sequential calls, chatty
  service hops, and missing caching or pagination. Use when the user says
  "/perf", "optimize performance", "this is slow", "N+1", "reduce latency", or
  "high memory/CPU". Edits code — change-discipline applies.
---

# namht-perf — measure first, optimize the bottleneck, prove it

Blind optimization wastes effort and adds complexity for nothing. The loop is strict: **measure →
find the dominant cost → fix that one thing → measure again.** A change that isn't shown to help by
numbers gets reverted. (Amdahl's law: only the dominant cost matters — shaving a 2% path is noise.)

## Get a number first (don't guess the hotspot)
Ground in the KB (`10-core-flows`, `08-database-schema`) and get real data before changing code:
- **DB:** `EXPLAIN` / `EXPLAIN ANALYZE` (MySQL & Postgres) on the suspect query; row counts; index usage.
- **Java:** async-profiler / JFR flame graphs; Micrometer timers; Hibernate SQL log for N+1.
- **Rails:** `rack-mini-profiler`, the **bullet** gem for N+1, `pg_hero`/`EXPLAIN` for slow SQL.
- **Node:** `clinic.js` / `--prof`; DB driver timing.
- Or pull real latency/slow-query data from `/namht-observe` metrics + `/namht-splunk-report`.

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
- Measure first — this stays true. `provenlens hotspots` ranks **blast radius, not runtime cost**;
  it tells you where a fix pays widest, never that something is slow.
- `provenlens path <controller> <repository>` — the full chain behind a slow endpoint, which is where
  an N+1 usually hides between two layers that each look innocent.
- `provenlens callers <query method>` — is the query reached from inside a loop? That is the N+1 test,
  and it is a graph question, not a grep question.

## The usual dominant costs (and the fix)
- **N+1 queries** (a query per row in a loop) → eager-load: JPA fetch-join / `@EntityGraph`, Rails
  `includes`, a Node dataloader/batch. Usually the single biggest backend win.
- **Missing / wrong index or full scan** (`EXPLAIN` shows a seq scan on a big table) → add a targeted
  or **composite/covering** index matching the query's filter+sort; mind cardinality and write cost.
- **Over-fetching** — `SELECT *`, no projection, unbounded result sets → select only needed columns; **paginate**.
- **Blocking / sequential I/O** that could be **parallel** → `CompletableFuture.allOf` / `Promise.all`
  / concurrent consumers; batch chatty cross-service calls into one.
- **Repeated work** → cache **only** where it's safe and you can invalidate correctly (a stale cache
  is a correctness bug, not a speedup).
- **Async/SQS throughput** → consumer concurrency, batch size, visibility/backpressure tuning.

## Method
1. **Baseline** — the real bottleneck + a number (latency / query count / rows / allocations). Cite it.
2. **Fix the biggest lever first** — propose the change + expected impact; apply with change-discipline.
3. **Re-measure** — before/after numbers. No measurable win → revert (don't keep speculative complexity).
4. Continue only while the next gain justifies the complexity it adds.

## Output (dual-audience; save + report)
Chat + `namht-sessions/perf/<area>-<date>.md`: the bottleneck, the fix, and **before/after numbers**
(the evidence), plus any trade-off (memory vs speed, cache staleness).

## Rules
- **Measure before AND after** — every claimed win needs numbers; no micro-optimizing without data.
- **Correctness is not negotiable for speed** — watch cache invalidation, race conditions, and any
  change to ordering/semantics. Behavior stays correct.
- **Biggest bottleneck first** — one meaningful lever at a time, not a scatter of tiny tweaks.
- Don't add caching/indexes/complexity that the measured gain doesn't pay for; respect the architecture.
- **Baseline correctness, not just speed.** Before optimising, also run the tests covering the target
  module and record any already-failing ones — eager-loading, caching and index changes are exactly
  where behavior drifts silently. Re-run them after: **a faster wrong answer is a regression.**
- **State the measurement conditions with every number** — environment, dataset size/row counts, warm
  vs cold, how many runs. A number without them is not evidence. If you cannot measure the after-state
  under the same conditions, write **`NOT MEASURED (<reason>)`** and mark the change **UNVERIFIED** —
  never claim a win you didn't measure.
- **Safety net — before the first edit.** `git status --porcelain` (ask the user to commit/stash their
  own work first) and save `git diff HEAD > <session>/00-pre-change.patch`. To undo use ONLY
  `git stash push -u` or `git apply -R <your diff>` — the git-guard denies `git restore`,
  `git checkout .`/`--`, `git reset --hard`, `git clean -f`.
- Change-discipline: scope-lock, minimal diff, verify + rollback, never touch secrets, confirm outward actions.

## Common rationalizations

| What you'll tell yourself | What's actually true |
|---|---|
| "I know what's slow here" | You know what *looks* slow. Optimisation without a measurement is a guess that costs real code. Measure, then fix the biggest number. |
| "The change is obviously faster" | Obvious wins routinely make things slower — an index that's never used, a cache that thrashes, a batch that blows memory. Prove it with before/after. |
| "I'll benchmark it later" | Later there is no baseline left to compare against. The baseline is the first artifact, not the last. |
| "It's faster on my machine" | State the conditions: dataset size, warm or cold, which environment. A number without conditions is not a number. |

## Red flags

- Code changed before any measurement exists.
- You optimised something other than the top item you measured.
- The "after" number was taken under different conditions than the "before".
- Correctness tests were not re-run — a faster wrong answer is still wrong.

## Verification

- [ ] Baseline captured **before** any change, with the conditions written down.
- [ ] The bottleneck was measured, not assumed — and it is the one you fixed.
- [ ] After-number taken the **same way** as the before-number.
- [ ] Correctness suite green: the optimisation changed speed, not behaviour.
- [ ] If the win did not materialise, that is reported as **NOT IMPROVED**, and the change reverted or justified.
