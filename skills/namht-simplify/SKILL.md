---
name: namht-simplify
description: >-
  Make existing code easier to read and change WITHOUT changing what it does —
  guarded by tests, one small refactor at a time. Removes dead code, flattens
  nesting, extracts and renames for intent, kills duplication, and deletes
  needless abstraction. Use when the user says "/simplify", "refactor for
  clarity", "reduce complexity", "clean up this code", or "this is too complex".
  Edits code — change-discipline applies. Behavior must not change.
---

# namht-simplify — behavior-preserving simplification

The goal is the code a new teammate could read in one pass. The constraint is absolute: **same
inputs → same outputs and side-effects.** This is refactoring, not a feature or bug change — if you
spot a bug, you stop and report it, you do not "fix" it here.

## Two rules that make this safe
1. **A test net comes first.** Refactoring without tests is just editing and hoping. Confirm the
   target behavior is covered; if not, write **characterization tests** (assert what the code does
   *today*, bug-for-bug) before changing anything — those tests are the definition of "unchanged".
2. **One transformation at a time → run tests → next.** Never batch several risky moves. Green after
   each step is the proof behavior held; red means revert that step.

### codelens (optional)
`.codelens/` present → prefer `codelens` over grep for anything about **who calls what**: it resolves
through DI, interfaces, mixins and framework string-bindings (MyBatis · Camel · SQS · Flyway) and
scores every edge. Confirm it with `codelens status`, and run `codelens sync` first if the working
tree has moved since it was built — **a stale index is worse than none, because it looks
authoritative**. If coverage reads low, `codelens doctor` says whether that is a resolver limit or
just an uninstalled dependency; those look identical in the number and are nothing alike in the fix.
No index, no `codelens` command, or a language it does not cover (**Java · Ruby · TS/JS** only) →
fall back to Grep/Glob and write `⚠️ grep-depth only (no codelens index)` in the output. A grep hit
is never a resolved call — do not report it as one. Playbook: `docs/codelens.md`.

**Here:**
- `codelens dead` — the delete list, already filtered against names appearing in templates and
  config (`.erb`, `.vue`, `.html`, `.yml`, …), so a getter a page renders is not on it. Nothing else
  in this kit makes deletion this safe.
- `codelens impact <symbol>` **before** any rename or extraction: behaviour must not change, and
  this is the set that "unchanged" is measured against.
- `codelens cycles` — the import cycles worth breaking, ranked, instead of the one you happened to
  notice.
- Still guarded by tests. A green `dead` listing is a candidate, never a licence to delete.
- `codelens query "<capability word>"` before extracting a shared helper — duplication hides under
  different names, and searching by declaration finds the twin that grepping the name misses.

## What to hunt (and the fix)
- **Dead code** — unused vars, functions, branches, feature flags that are always one value → delete.
- **Deep nesting / arrow code** → guard clauses and early returns.
- **Long functions doing many jobs** → extract intention-revealing helpers (one job each).
- **Duplication** → one source of truth — but don't force-DRY *incidental* repetition that will diverge.
- **Mystery names / magic numbers** → names that state intent; named constants.
- **Needless indirection / over-abstraction** → inline it. A tiny wrapper used once hurts more than a
  little repetition. Clarity beats cleverness.
- **Tangled conditionals** → simplify boolean logic; replace flag arguments with clear call sites.

## Stack smells (common in this fleet)
- **Java:** speculative interfaces/factories with one impl, getters/setters hiding logic, deep
  inheritance → prefer composition, inline the single-impl indirection.
- **Rails:** fat models, callback chains, `method_missing` cleverness → extract POROs/service objects,
  make the flow explicit.
- **Node:** callback pyramids / long `.then` chains → `async/await`; scattered config → one module.

## Method
1. **Establish the net** — confirm/add tests around the target behavior.
2. **Simplify in small green steps** — apply one refactor, run tests, keep it only if green.
3. **Stop at "clear enough."** Don't restructure beyond the ask or gold-plate.

## Output
Chat summary: what got simpler and why (nesting/length/duplication reduced), tests green, diff kept
reviewable. Optionally save `namht-sessions/simplify/<area>-<date>.md`.

## Rules
- **Behavior-preserving — NON-NEGOTIABLE.** No functional change. Found a bug? Stop, flag it, hand to `/namht-fix-bug`.
- **Minimal diff, one refactor at a time**; tests green after each or revert.
- **Don't over-abstract** — readable-and-slightly-repetitive beats clever-and-opaque.
- Respect conventions and the architecture invariants; no library swaps or structure churn.
- **Never weaken a test to reach green.** If a refactor turns a test red, **the refactor is wrong —
  revert that step.** Do not delete, skip, relax an assertion, or "update the expected value": the test
  IS the definition of unchanged behavior, so editing it deletes the only guarantee this skill offers.
  The sole exception is a test already failing in your baseline; any test you touch must be listed in
  the output with the reason.
- **Safety net — before the first edit.** Run `git status --porcelain` (ask the user to commit or stash
  their own work first); run the relevant gates once and record **which tests were already failing**;
  save `git diff HEAD > <session>/00-pre-change.patch`. To undo later use ONLY `git stash push -u` or
  `git apply -R <your diff>` — the git-guard denies `git restore`, `git checkout .`/`--`,
  `git reset --hard`, `git clean -f`. A test that was red before you started is not your regression.
- Change-discipline: scope-lock, verify + rollback, never touch secrets, confirm before destructive actions.

## Common rationalizations

| What you'll tell yourself | What's actually true |
|---|---|
| "While I'm in here I'll fix this too" | That is how a behaviour-preserving refactor becomes an unreviewed change. One refactor at a time; the other thing goes on a list. |
| "The test is asserting the wrong thing anyway" | Then that is a **separate** conversation, with evidence. Changing a test during a refactor destroys the only proof that behaviour was preserved. |
| "It's obviously equivalent" | Obvious equivalence is where the null handling, the short-circuit and the ordering guarantee quietly change. Let the tests say it. |
| "This abstraction will be useful later" | Simplify means removing needless abstraction, not adding speculative ones. Delete beats generalise. |

## Red flags

- The test suite was **not run between** two refactors.
- A test changed in the same diff as the refactor.
- The diff contains a behaviour change you would struggle to describe in one sentence.
- You are renaming things across files that the task never mentioned.

## Verification

- [ ] Tests were green **before**, and are green **after** — with no test modified.
- [ ] Each refactor is separable: you could revert one without unpicking the others.
- [ ] Public behaviour is identical — same inputs, same outputs, same errors, same order.
- [ ] Anything you chose not to simplify, and why, is stated.
