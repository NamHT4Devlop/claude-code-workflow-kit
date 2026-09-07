---
name: cwk-ask
description: >-
  Answer natural-language questions about a codebase grounded in the Knowledge
  Base (business meaning) and real source (technical detail) — never invented —
  for a mixed business+technical audience: a plain-language explanation, a
  fitting Mermaid diagram, and the precise technical detail with real
  file/field/endpoint citations. Use when the
  user asks "/ask", "how does X work", "which module handles Y", "where is Z
  implemented", or any Q&A about the project.
---

# Spec Ask — grounded codebase Q&A

A native port of Auto Spec extension's `/ask`. Answer grounded in the Knowledge Base (business meaning)
and real source (technical detail) — never invent files, APIs, fields, or behavior.

> **Legacy folder.** Session artifacts used to live in `spec-kit-sessions/` (renamed to avoid
> confusion with GitHub's unrelated `spec-kit` project). If a repo still has `spec-kit-sessions/` and no
> `cwk-sessions/`, **read** the old folder so past work isn't lost, keep **writing** to
> `cwk-sessions/`, and mention `scripts/migrate-sessions.sh <repo>` once to merge them.

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
- `provenlens explore "<symbol|Type#method|phrase>"` — verbatim source, callers, callees and blast
  radius in one call. This *is* the answer to "how does X work" and "where is Y implemented"; reach
  for it before opening files.
- `provenlens path <from> <to>` — when the question is "how does A end up calling B", answer with the
  real chain hop by hop instead of a plausible narrative.
- Cite the file:line provenlens returns, never a path you reconstructed from memory.
- `provenlens node <symbol>` when the question is about **one** named thing and `explore`'s three
  matches would be noise: it returns that symbol in full with its caller/callee trail, nothing else.

## Procedure
0. **Check the Q&A journal first (cross-session memory).** If
   `cwk-sessions/answers/_journal.md` exists, read it — it is a one-line-per-question index of
   every past answer in this repo. Use it to: (a) answer *"what did I ask before / what did we
   conclude about X?"* directly from the journal; (b) when today's question was already answered,
   **say so**, link the saved answer file, reuse its conclusion, and only re-derive what changed
   since. It's a small index — reading it costs little and makes new sessions remember old ones.
   **Check the conclusion isn't stale before reusing it:** the files it cited may have moved on —
   `git log --since=<that date> -- <those files>`. If they changed, re-derive rather than repeat an
   answer that was true last month; say which it was.
0.5 **Are you in a single repo, or a KB hub?** If the current folder has `projects/*/knowledge-base/`
   (a hub produced by `scripts/kb-export.sh`) instead of its own `knowledge-base/`, you are being
   asked **across projects**. Then:
   - Search every project's KB, and **name the project in every claim** — "in `billing`, …". An
     unattributed fact is useless here, because the reader cannot tell which system it applies to.
   - When several projects answer the same question **differently**, that contrast is usually the
     real answer (e.g. "three services validate this, `gateway` does not"). Lead with it.
   - **There is no source code in a hub.** You cannot verify anything against real files, and each
     KB is a snapshot at the commit in its `_meta.yml`. Say so once, and give the dates — a
     confident answer from a KB exported four months ago is the failure mode here.
   - If the question is really about one project, say which, and suggest asking again inside that
     repo where the answer can be grounded in code.

1. **Ground code answers in real source.** When the question is about *how code works / where
   something is*, use Grep/Glob/Read to ground the **Technical detail** section in real files; the
   KB supplies business meaning.
1b. **Operational questions go through the runbook.** "What do we do when X fails", "Y is down",
   "how do we roll back" → if `cwk-sessions/runbook/*.md` exists, read the matching playbook first,
   then re-run `provenlens path` / `impact` against the **current** index so the chain you answer with
   is live, not the snapshot in the document. Cite the playbook and the commit its graphs were taken
   at; if the code moved since, say what changed.
2. **Select relevant KB context.** Map the question to topics and load just those
   `knowledge-base/` docs (don't dump the whole KB). If the question names a module/feature,
   load the matching `knowledge-base/modules/<module>.md` first — those deep docs are the
   richest context. Fall back to reading the actual source only if the KB lacks the answer
   (and say so).
3. **Detect vagueness.** If the question is broad/under-specified, first state your
   interpretation + assumptions, answer the most likely intent, then ask 2–3 clarifying
   questions.

## Answer structure (always, in this order) — dual audience
Write so a **non-technical reader (founder / PM / ops) AND an engineer both get full value from
the same answer.** Layer it plain → precise: never assume tech background in the top sections,
never lose precision at the bottom, and define every unavoidable term.
```
## TL;DR (one line — for everyone)
One jargon-free sentence that answers the question. Add a short analogy if it helps.

## In plain language (business / non-tech)
What it is, why it matters, how it behaves — everyday business terms. NO unexplained jargon:
the first time a technical word is unavoidable, define it inline in parentheses. A non-technical
reader must fully understand this section on its own.

## Diagram
A Mermaid diagram that fits the question — flowchart for a flow, erDiagram for data/fields,
sequenceDiagram for an interaction. Use a valid ```mermaid block, short plain labels. If a
diagram truly doesn't apply, write "(no diagram needed)".

## Code graph (provenlens)
The `provenlens export --format mermaid` block for the symbol the answer centres on, pasted
verbatim (truncation stated), plus the `provenlens path` chain when the question is "how does A
reach B". Under it, the **reach ledger** for that symbol — symbol · direct callers · transitive
reach · covered in this answer? — so a consumer the graph knows and the answer skipped is listed,
not lost. Without an index: `⚠️ grep-depth only (no provenlens index)` and a diagram labelled
"inferred from imports and names".

## Technical detail (engineers)
The precise answer, citing concrete names from the KB: files, modules, endpoints,
entities, fields, functions. Full accuracy here — don't dumb it down.

## In plain words (glossary)
Any technical term used above → a one-line everyday definition. Omit the section if there were none.
```

## Rules
- **Never copy secrets or personal data into the saved answer or the journal.** Name the field and
  where it lives, use synthetic example values, and mask any real credential/token/customer record —
  these files persist on disk and get exported to HTML/PDF and shared.
- **Same facts, two depths.** The plain sections and the technical section must not contradict —
  one is a simpler view of the other, not a different answer.
- Ground every claim in the KB. If it doesn't contain the answer, say so explicitly.
- When mapping business ↔ code, name the exact field / file / function.
- If `knowledge-base/` is missing entirely, tell the user to run `/cwk-scan` first;
  you can still answer from direct code reading but flag the lower confidence.

## Output — answer in chat, THEN save an HTML file
1. **Answer in chat first** using the full dual-audience structure above (this is the primary output).
2. **Save the same content** to `cwk-sessions/answers/<slug>-<date>.md` (slug from the question).
3. **Render a self-contained HTML** (styled, with the Mermaid diagram drawn) using the bundled renderer.
   Resolve this skill's `references/` dir first (call it `$SKILL_DIR`): `${CLAUDE_PLUGIN_ROOT}/skills/cwk-ask/references`
   if `CLAUDE_PLUGIN_ROOT` is set, else the `references/` folder next to this SKILL.md, else `$HOME/.claude/skills/cwk-ask/references`.
   ```bash
   node "$SKILL_DIR/render-html.cjs" \
     "<repo>/cwk-sessions/answers/<slug>-<date>.md" \
     "<repo>/cwk-sessions/answers/<slug>-<date>.html" "<question>"
   ```
   (It prints the HTML path. Requires Node — if absent, keep the chat + `.md` and say HTML was skipped.)
4. **Open it**: macOS `open "<path>"` · Linux `xdg-open` · Windows `start "" "<path>"`. Give the user the path.
5. **Append ONE line to the Q&A journal** `cwk-sessions/answers/_journal.md` (create it with the
   header below if missing). This is the cross-session memory step — never skip it:
   ```markdown
   # Q&A Journal — one line per answered question (newest last)
   | Date | Question | Conclusion (one line) | Detail file |
   |---|---|---|---|
   | 2026-07-05 | how does the KPI flow work | 2 endpoints, no cache; levelOf() duplicated in 3 places | kpi-flow-2026-07-05.md |
   ```
   Keep the conclusion to ONE plain sentence (the TL;DR, compressed); `Detail file` is the `.md` you
   just saved (filename only). If the journal grows past ~200 rows, note that consolidation is due —
   don't delete rows silently.

Output lands under `cwk-sessions/` (gitignored) — no footprint in the repo.
