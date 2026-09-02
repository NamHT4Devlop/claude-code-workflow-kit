---
name: namht-retro
description: >-
  Run an engineering retrospective over a time window from git history (read-only):
  what shipped, recurring themes/pain, what went well vs poorly, risk/quality
  signals, and concrete action items for next period. Use when the user says
  "/retro", "weekly retro", "what did we ship", "retrospective", "sprint review".
---

# namht-retro — engineering retrospective from git history

A periodic look-back grounded in real history.

## Gather (read-only git + artifacts)
- Window: default last 7 days (or what the user names). `git log --since=<window> --stat`,
  `git shortlog -sn --since`, `git diff --stat <since>..HEAD` for churn by area.
- **Read the journals first** — `namht-sessions/answers/_journal.md` (questions asked),
  `builds/_journal.md` (what was built + the key decision) and `fixes/_journal.md` (bugs + root
  causes). They are one-line-per-entry indexes built for exactly this: the cheapest high-signal
  source for *what shipped*, *what people kept having to ask*, and *what keeps breaking*. A root
  cause or an area appearing repeatedly in the fix journal is a retro finding on its own.
- **Legacy folder:** if the repo has `spec-kit-sessions/` (the pre-rename name) and no
  `namht-sessions/`, read the journals from there — that history still counts.
- Optional signals: `namht-sessions/` reports (fixes/reviews/qa) from the window; open TODO/FIXME
  added; test coverage gaps on changed areas (test-debt trend).

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
- `codelens hotspots` crossed with the window's churn — a period that repeatedly touched a hub is
  the concrete signal for **Quality & risk signals**, replacing "this area felt painful".
- `git diff --name-only <since>..HEAD | codelens affected --fail-if-untested` — test debt as a fact
  with a symbol list, which is what makes an action item ownable.

## Produce (dual-audience; chat + save `namht-sessions/retro/<date>.md`)
```
## In plain words            ← the period in 3 bullets (shipped / notable / watch-outs)
## Shipped                   ← features/fixes merged (grouped by area), with size
## What went well            ← concrete wins (cite commits/PRs)
## What hurt                 ← recurring pain: churned files, repeated bug areas, review themes
## Quality & risk signals    ← test-debt (no-covering-tests), hotspots (high churn), regressions seen
## Action items              ← 3–6 concrete, owned, doable next-period actions
```

## Rules
- Ground every claim in git/artifacts (cite commits/files). No vague "team did great".
- Read-only — never mutate git. Keep it honest: surface the pain, not just wins.
- Tie action items to the toolkit where useful (e.g. "run /namht-qa on module X — it has no tests").

**Render it to HTML too.** Resolve this skill's `references/` dir first (call it `$SKILL_DIR`):
`${CLAUDE_PLUGIN_ROOT}/skills/namht-retro/references` if `CLAUDE_PLUGIN_ROOT` is set, else the
`references/` folder next to this SKILL.md, else `$HOME/.claude/skills/namht-retro/references`.
```bash
node "$SKILL_DIR/render-html.cjs" "<the .md just saved>" "<same path>.html" "Retrospective — <window>"
```
Then open it and give the user the path. (This is also what the VS Code panel's **📄 Report** button
looks for — without it the button has nothing to open.)
