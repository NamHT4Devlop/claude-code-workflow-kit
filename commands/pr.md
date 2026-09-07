---
description: Prepare a PR description from the current branch, or review a GitHub PR (two-phase + blast radius). Read-only on the remote.
argument-hint: "[review <PR#/URL>] | empty = prepare PR from current branch"
---

Use the **cwk-pr** skill.
- **No argument / "prepare":** draft a PR title + description from the current branch's diff +
  commits (summary/what-why, changes, impact & risk via caller/blast-radius analysis, tests done,
  checklist). Save to `cwk-sessions/pr/`.
- **"review <PR number or URL>":** fetch the PR diff (`gh pr diff`) and run a two-phase review
  (quality checklist + business consistency vs KB) with blast radius.

Never push/merge/create/comment on the remote unless I explicitly ask (the git-guard blocks
remote-mutating git regardless).

Argument: $ARGUMENTS
