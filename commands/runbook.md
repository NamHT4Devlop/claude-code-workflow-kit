---
description: Turn the KB + real deploy/CI config into an operational runbook — health checks, deploy/rollback, incident playbooks, alerts→action, escalation
argument-hint: "[service / module — blank = ask which deployable]"
---

Use the **cwk-runbook** skill to produce an operational runbook for the service below — written
for someone reading it at 2am who did not build the system.

Ground the business half in `knowledge-base/` and the operational half in the repo's real deploy/CI
config, health endpoints, error handling, queue/DLQ and migration setup — citing files. Build the
failure catalogue from what this system can actually do, not a generic list. Every playbook follows
Symptom → Confirm → Contain → Diagnose → Fix → Verify → Escalate, with destructive steps marked.
Never invent a command, alert, owner or phone number: cite it, mark it `UNVERIFIED`, or leave it as a
`❓` in the "Fill this in" block. Write the document only — never deploy, restart, replay or migrate
anything. Ask before placing it inside a team repo.

Service / scope:
$ARGUMENTS
