---
description: SRE health and performance review of an Elastic Beanstalk / EC2 app — CPU, memory, disk, network, latency, 5xx, deploys, logs → code → report with fixes and issue drafts (read-only)
argument-hint: "[--profile P] [--region R] [<eb-application> <eb-environment>] [window, e.g. 24h | 7d]"
---

Use the **cwk-sre** skill to review the health and performance of the Elastic Beanstalk environment
below, read-only through the `aws` CLI: map the environment and its deploys, check what can be
observed (CloudWatch Agent for memory/disk, enhanced health, logs in CloudWatch), pull CPU, memory,
disk, network, load-balancer traffic, 5xx and latency against a 7-day baseline, read the top log
errors (the Logs Insights plan is shown for your OK first), trace what is wrong into this repository
through the Knowledge Base, and write a report with prioritised findings, concrete code or config
fixes, a verification step each and ready-to-paste issue drafts. **Nothing is changed in AWS or in
the repo, and no issue is created.** Fixes are carried out afterwards with `/cwk-perf`,
`/cwk-fix-bug` or `/cwk-observe`.

Profile / region / application / environment / window:
$ARGUMENTS
