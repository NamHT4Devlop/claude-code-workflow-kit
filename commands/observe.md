---
description: Instrument code for observability — structured logs, correlation/trace IDs, metrics, error context
argument-hint: "[area/service to instrument + backend, e.g. 'payments service, splunk']"
---

Use the **cwk-observe** skill to add/improve observability in the target: structured logging,
correlation/trace IDs (propagated across HTTP + SQS), metrics, and rich error context — matching the
project's conventions and the backend's field schema (e.g. Splunk `cai_app`/`cai_enviroment`). Never
log secrets/PII. Follow change-discipline; verify build/tests.

Area / service / observability backend:
$ARGUMENTS
