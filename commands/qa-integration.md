---
description: Run integration/E2E QA against a RUNNING app via a real browser — execute new + regression test cases, assert from DOM/screenshots, pass/fail report
argument-hint: <app URL> (+ optionally a /cwk-qa plan path or story)
---

Use the **cwk-qa-integration** skill to execute QA against the running app below: drive the
browser via the Claude-in-Chrome MCP (navigate, log in with a test account if needed, fill, click),
assert each test case from the DOM + a screenshot, run BOTH the new-flow and regression cases
(from a /cwk-qa plan if available, else derive the key set via the KB), and produce a
pass/fail report with evidence. Read/observe only; never run destructive actions on a shared env;
ask for a test login rather than inventing creds. Found a bug → offer /cwk-fix-bug.

App URL (+ optional test-plan path / story):
$ARGUMENTS
