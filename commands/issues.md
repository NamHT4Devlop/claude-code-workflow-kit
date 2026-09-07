---
description: Turn a plan or user stories into tracker issues (GitHub via gh, or Jira/Linear via MCP) — previews first, never creates without a yes
argument-hint: "[plan/story file or id] [target, e.g. github owner/repo] [--create to actually create]"
---

Use the **cwk-issues** skill to turn the plan or user stories below into tracker issues — one
issue per story, its acceptance criteria as a checklist, parents linked to children, ids kept
verbatim so the issues map back to the plan.

**Preview by default.** Search the target first and classify every story as create / update / skip
so a second run never duplicates what is already tracked, show the full table plus a sample body,
and only create after an explicit yes — `--create` alone is not that yes. Confirm the target project
explicitly rather than assuming the current repo's remote. Never close or delete existing issues,
and never put secrets or personal data in an issue body. Record the resulting links back into the
source artifact and append a row to `cwk-sessions/issues/_journal.md`.

Source, target and flags:
$ARGUMENTS
