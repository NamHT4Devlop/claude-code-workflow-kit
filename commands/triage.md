---
description: Triage an incident from a Slack thread — Splunk logs → KB + code → root cause → the change that introduced it → reply draft (+ Rally defect)
argument-hint: "<slack thread link> [index=A cai_enviroment=B cai_app=C] [--no-names]"
---

Use the **cwk-triage** skill to investigate the incident reported in the given Slack thread: read the
whole thread, pull the matching logs from Splunk (the query plan is shown for you to confirm; any of
`index` / `cai_enviroment` / `cai_app` you don't pass is left out), map them to the code through the
Knowledge Base, classify the problem, find the root cause and the commit / PR that introduced it,
and work out the resolution. It then drafts a reply to the thread — issue · root cause · change ·
how to fix — and optionally a Rally defect. **Read-only on code; nothing is posted to Slack or
created in Rally without your yes.** `--no-names` keeps people's names out of the reply. For a code
defect, the report is the input to `/cwk-fix-bug`.

Slack thread link / Splunk filter / options:
$ARGUMENTS
