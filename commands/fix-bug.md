---
description: Fix a bug or a QA report — TRIAGE (code vs config/data/spec?), find ROOT CAUSE, failing regression test tied to the AC, minimal fix, verify, loop back to QA
argument-hint: <error / stack trace / QA report: expected-vs-actual + repro + environment + failing test case>
---

Use the **cwk-fix-bug** skill on the bug/QA report below. First **triage whether it's really a code
defect** (vs config / env-var / data / migration / feature-flag / deploy-skew / spec-AC ambiguity) —
for an environment-only bug, pull evidence from logs (`/cwk-splunk-report`), the config/deploy diff,
and data/flag state instead of forcing a local repro. If it IS a code bug: locate the code path (read
first) → reproduce → **root-cause analysis tied to the violated acceptance criterion** → blast radius →
minimal surgical fix with a **failing-then-passing regression test mapped to the failing QA case** →
verify (tests + build, rollback if broken) → hotfix report + KB update, then tell the user to redeploy
and **re-verify on the environment** (`/cwk-qa-integration`). Do NOT deploy/push — the human deploys.

Bug / QA report (expected vs actual, repro steps, environment + build, failing test case/AC, severity):
$ARGUMENTS

If it lacks expected-vs-actual, a repro, the environment, or the failing test case, ask 2–4 targeted
questions before digging in. If triage shows it's a config/data/spec issue, say so and route it — don't
"fix" correct code.
