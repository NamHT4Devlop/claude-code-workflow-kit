---
description: Ask a question about the codebase — answered from the Knowledge Base (plain language + diagram + technical detail)
argument-hint: <your question>
---

Use the **cwk-ask** skill to answer the question below, grounded ONLY in the repo's
`knowledge-base/` (and `modules/`). Structure the answer as: **In plain language** → a
fitting **Mermaid diagram** → **Technical detail** with real file/field/endpoint citations.
Never invent files or behavior; if the KB lacks the answer, say so.

Question:
$ARGUMENTS

If the current folder is a **KB hub** (`projects/<name>/knowledge-base/`) rather than a single
repo, answer **across projects**: attribute every claim to a project, lead with any contrast between
them, and state once that a hub has no source to verify against and each KB is a snapshot at the
commit/date in its `_meta.yml`.
