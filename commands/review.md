---
description: Two-phase review of a file, branch, or PR — quality checklist + business consistency vs the KB
argument-hint: "[file path | PR #/URL | empty = branch vs default (or working-tree diff)]"
---

Use the **cwk-review** skill to review the target below in two phases: (1) code quality
against the full review checklist (`knowledge-base/review-skills.md` if present, else the
bundled universal checklist), and (2) business consistency against the Knowledge Base.
Every issue must include the exact bad code and complete fixed code.

Resolve the target from the argument (read-only git/`gh` only):
- a **PR** (`#123`, `123`, or a GitHub PR URL) → review that PR's diff (`gh pr diff`) vs its base branch;
- a **file/path** → review those files;
- **empty** → if there are uncommitted changes, review the working-tree diff; otherwise review the
  current branch vs the default branch (`git diff <default>...HEAD`).

Target:
$ARGUMENTS
