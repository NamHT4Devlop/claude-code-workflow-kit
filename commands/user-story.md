---
description: Deep-investigate a requirement (or a Slack thread you provide) → features + INVEST user stories with maximally granular Given/When/Then ACs
argument-hint: <requirement text, and/or a Slack thread/channel URL> (add "quick" for a lighter pass)
---

Use the **cwk-user-story** skill on the input below. By default run in **deep mode**: first
investigate the codebase (KB + the read-only analysis agents — cwk-business-flow-tracer, cwk-codebase-analyzer,
cwk-impact-detector) to ground everything in real entities/flows/rules and the blast radius, then write
**features + INVEST user stories** with **maximally granular acceptance criteria** — one atomic,
testable assertion per AC (each field × rule, each role, each state transition, each error/edge/
concurrency case as its own numbered Given/When/Then with concrete values) plus an AC coverage matrix.

Requirement and/or Slack source:
$ARGUMENTS

If a Slack link/channel is given, don't just read the messages — **comprehend the thread**: read the
whole thread + reactions, note who decided what, reconstruct the decision timeline (latest confirmed
decision wins), follow linked Slack canvases/files, separate decisions from chatter, and list any
external links (Jira/Figma) you can't open so the user can paste them. Emit a short "Thread
Understanding" and, if a material decision is still unresolved, confirm before writing stories. No
Slack MCP available → ask the user to paste the thread. If nothing usable is given, ask for a
requirement or a Slack link — never invent content. (Say "quick" for a lighter, single-pass version.)
