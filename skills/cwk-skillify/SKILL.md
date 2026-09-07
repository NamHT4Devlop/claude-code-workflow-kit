---
name: cwk-skillify
description: >-
  Scaffold a NEW cwk-* skill (and its command) from a description, following
  this toolkit's conventions, so the user can self-extend the kit. Use when the
  user says "/skillify", "create a new skill", "add a skill for X", "turn this
  workflow into a skill", "make a command for …".
---

# cwk-skillify — create a new skill the right way

Meta-skill: scaffold a new `cwk-*` skill + command that matches this repo's standard, then wire
and document it. Operate inside the `claude-code-workflow-kit` repo (the toolkit source, e.g. `~/claude-code-workflow-kit`).

## Steps
1. **Clarify** the new skill: name (kebab, will become `cwk-<name>`), one-line purpose, when it
   should trigger, inputs, output, whether it needs the HTML renderer or the review checklist.
2. **Read [`docs/skill-anatomy.md`](../../docs/skill-anatomy.md) first** — it is the standard this
   step generates against: required sections in order, and the extra trailer
   (**Common rationalizations · Red flags · Verification**) that every high-stakes skill carries.
   A skill that edits code, or whose conclusions someone will act on, MUST have that trailer;
   `tests/consistency.test.sh` fails without it.
3. **Create `skills/cwk-<name>/SKILL.md`** with frontmatter:
   - `name: cwk-<name>` (MUST equal the folder name), `description: >-` a 1–3 sentence trigger
     description (when to use + key verbs/aliases). Body = the methodology, grounded in the KB
     where relevant, with a clear Output section and Rules. Reuse the house style: KB-first,
     dual-audience output, change-discipline if it edits code.
4. **Create `commands/<name>.md`** (UNPREFIXED filename) — thin entry: frontmatter `description` +
   `argument-hint`, body "Use the **cwk-<name>** skill to … $ARGUMENTS".
5. **If it needs bundles** (HTML render / review checklist): add `cwk-<name>` to the right list in
   `scripts/sync-bundles.sh` (`map_html` for the renderer, `map_review` for the checklist), then run
   `bash scripts/sync-bundles.sh`.
6. **Register it in EVERY place a skill is listed.** Missing one is how the kit drifts — and
   `tests/consistency.test.sh` fails on each of these, so check them off before running it:
   - `vscode-extension/src/extension.ts` → add the command to the **`ALLOWED`** set (and to
     `EDITS_CODE` if it modifies source).
   - `vscode-extension/media/main.js` → add an `A(...)` **card** in `ACTIONS`: pick the category,
     an icon, a short title/description, the form fields, and the `build(v)` that assembles the
     arguments. Pass `true` as the last argument if it edits code.
   - `vscode-extension/media/i18n.js` → Vietnamese strings for the new card's title, description
     and every field label (or list the term in `I18N_VI_SAME` if it stays English on purpose) —
     `tests/i18n.test.cjs` fails the suite otherwise.
   - `commands/help.md` → one table row.
   - `README.md` → the command table row (and the skill/command counts near the top).
   - `docs/skills-catalog.html` → one `<tr>` with the **Edits code / Read-only** badge, and bump the
     `<b>N</b> skills` fact.
   - `docs/manual-setup-guide.html` → the file counts shown in the copy-paste blocks.
   - `CHANGELOG.md` → an entry under **Added** (MINOR bump; MAJOR only if users must act).
7. **Install:** `bash scripts/personal-install.sh` (symlinks the new skill + command into `~/.claude`).
8. **Verify:** `bash tests/run.sh` — it checks skill-name==folder, bundle sync, `ALLOWED` ↔ `skills/`,
   command ↔ skill, `help.md` coverage, catalog coverage and the documented counts.

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
- A new skill that reasons about **who calls what** MUST carry the `### provenlens (optional)` block:
  the shared paragraph verbatim (fallback sentence included) plus its own `**Here:**` bullets naming
  the specific commands it uses.
- A new skill that genuinely never reads a call graph MUST be added to the opt-out list in
  `tests/consistency.test.sh` with a one-line reason. There is no third option — the test fails on
  a skill that is in neither place, which is what keeps the standard a standard.
- Scaffold the block from any integrated skill and from `docs/provenlens.md`; do not paraphrase the
  shared paragraph.

## Rules
- Follow the established conventions exactly (naming, unprefixed command files, frontmatter shape,
  references via sync) so audit/tests stay green — don't invent a new structure.
- Keep the new skill focused (one job) and the description trigger-friendly.
- Don't duplicate an existing skill — check `commands/` first; extend instead if overlap.
- Commit message must NOT contain the literal phrase a git command would match (e.g. "git push") on
  one line — it trips the git-guard. Commit and push as separate commands.
