---
description: Query Splunk for per-app errors over a window (default today), aggregate into a table, and post to Slack
argument-hint: "[index=A cai_enviroment=B cai_app=C + window | empty = the skill asks]"
---

Use the **cwk-splunk-report** skill to query Splunk for errors/exceptions, aggregate them into a
single table (app · total · top error · severity), and post it to Slack. The query filter is
`index={A} cai_enviroment={B} cai_app={C}` — the skill **asks for A/B/C** and **skips any variable
you don't pass**. **Time window** defaults to the **last 1 day**; pass a custom one (`4h`, `30m`,
`7d`, a range). **Error criteria**: give a free-form string — the skill parses it into a correct SPL fragment
(quotes phrases, ORs lists, keeps `field=value`) and shows the SPL for you to confirm (broad default if none).
For **Slack**, the skill **asks you for the webhook URL** and posts there. Read-only on Splunk;
prefer a connected Splunk MCP; confirm before posting.

index (A) / cai_enviroment (B) / cai_app (C) / window (e.g. 4h) / error criteria / Slack webhook URL:
$ARGUMENTS
