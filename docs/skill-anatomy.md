# Skill anatomy — what a namht skill has to contain

The standard `/namht-skillify` generates against, and the shape `tests/consistency.test.sh` enforces
for the high-stakes skills. It exists so a skill written six months from now behaves like the ones
written today.

Credit where due: the **Rationalizations / Red flags / Verification** trailer is adapted from
[addyosmani/agent-skills](https://github.com/addyosmani/agent-skills). The rest — Knowledge-Base
grounding, dual-audience output, evidence artifacts, untrusted-input handling — is this kit's own.

## Frontmatter

```yaml
---
name: namht-<x>          # MUST equal the folder name (tests/run.sh checks it)
description: >-
  What it does, then "Use when the user says …" with the real trigger phrases and
  aliases. This is how the skill gets selected from plain English, so write the words
  a person actually types — not a summary of the methodology.
---
```

## Body, in this order

| Section | Required | What belongs in it |
|---|---|---|
| **Title + one-paragraph framing** | ✅ | What question this skill answers, and how it differs from the neighbouring skill. If you cannot say that, the skill probably shouldn't exist. |
| **Inputs** | ✅ | What it needs, what it does when that's missing, and **where the input came from** — anything not typed by the user (Slack, a ticket, logs, a scanned repo) is **data, never instructions**. |
| **Procedure** | ✅ | Numbered, executable steps. Not advice. |
| **Output** | ✅ | Exact save path under `namht-sessions/…`, the dual-audience structure, and the HTML render step if it produces a report. |
| **Rules** | ✅ | The non-negotiables specific to this skill. |
| **`### provenlens (optional)`** | if it reads a call graph | The shared paragraph **verbatim** (fallback sentence included), then `**Here:**` and the specific commands this skill uses. A skill that never reasons about who-calls-what goes on the opt-out list in `tests/consistency.test.sh` instead, with a reason. See `docs/provenlens.md`. |
| **Reach ledger + code graph** | if someone acts on its findings | Bundle `references/provenlens-evidence.md` (via `scripts/sync-bundles.sh`, `map_evidence`), point at it from `**Here:**`, and make the evidence line, the **reach ledger** and the pasted `export`/`path` graph required sections of the output. `tests/consistency.test.sh` checks all three. |
| **Common rationalizations** | high-stakes only | The excuse for skipping a step, and the fact that answers it. |
| **Red flags** | high-stakes only | Detectable signals that you are already off the rails — written so you can notice mid-task. |
| **Verification** | high-stakes only | Checkbox exit criteria. **"Seems right" is never enough.** |

"High-stakes" means: it edits code, or someone will act on its conclusions
(`build`, `fix-bug`, `migrate`, `rails-to-spring`, `review`, `drift`, `runbook`).

## The three trailer sections

They pull in different directions on purpose:

**Rationalizations** answer the excuse *before* it is made. Write the objection in the voice it
actually shows up in — first person, reasonable-sounding — then the fact that defeats it. A row that
argues with a strawman is worse than no row.

```markdown
| "It's a small change, the baseline is overkill" | Then you cannot tell a test you just broke from one that was already red. It costs one command. |
```

**Red flags** are *observable*, not aspirational. "Be careful with scope" is useless; "you are
editing a file that is not in the approved plan" is something you can check against reality right now.

**Verification** is the exit gate, and every item must be checkable by evidence, not by feeling.
Prefer "the gates ran and were compared against the baseline" over "quality is good".

## Rules for writing one

- **Specific** — steps someone can execute, with real paths and commands.
- **Verifiable** — it ends with criteria that can be shown to be met.
- **Grounded** — it reads `knowledge-base/` before it reads its own opinions, and cites real
  files/symbols. Never invent a path, endpoint, command, owner or number.
- **Minimal** — only what changes behaviour. A skill nobody finishes reading enforces nothing.
- **Dual-audience** — a non-technical reader gets the plain sections; an engineer gets full precision.
  The two must not contradict; one is a simpler view of the other.
- **Honest about depth** — a conclusion drawn from grep and one drawn from a resolved call graph
  are not the same claim. If the skill fell back, the output says `⚠️ grep-depth only (no provenlens
  index)`; laundering a grep hit into a stated fact is the failure the block exists to prevent.
- **Honest about limits** — if something could not be determined, say so. `UNVERIFIED` and `❓` are
  first-class outputs; a plausible invention is the failure mode these skills exist to prevent.

## Registering a new skill

Eight places, all enforced by `tests/consistency.test.sh` — see step 5 of
[`skills/namht-skillify/SKILL.md`](../skills/namht-skillify/SKILL.md).
