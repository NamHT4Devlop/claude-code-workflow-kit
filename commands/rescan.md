---
description: Update the existing Knowledge Base incrementally from recent code changes (git-diff aware)
argument-hint: "[optional: base ref, e.g. main or a commit]"
---

Use the **cwk-rescan** skill to incrementally update the existing `knowledge-base/`:
find changed source files (via git), map them to the affected KB docs, and refresh only
those — preserving unrelated content. If there is no existing KB, fall back to `/cwk-scan`.

State which branch you are reading and what you are diffing against before you start.

**Business-rule and core-flow ids are append-only.** An amended rule keeps its id, a new rule takes
the next free one, and a rule whose code is gone is marked `[REMOVED <date>]` rather than deleted —
test names, evidence reports and journals cite those ids and this rescan cannot see them.
Renumbering is the one edit that silently invalidates work outside the KB.

Refresh `_meta.yml` (at minimum `commit`, `branch`, `generated`) so a stale KB stops passing as
current, and update the Mermaid architecture diagram itself if the topology changed — not just the
prose around it.

Base ref to diff against (optional): $ARGUMENTS
