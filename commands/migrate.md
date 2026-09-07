---
description: Plan + execute a safe migration/deprecation (API, DB schema, event contract, library) with rollback
argument-hint: "[what's changing, e.g. 'add nullable dueDate column to tasks' | 'deprecate /v1/orders']"
---

Use the **cwk-migrate** skill to plan and execute the change safely: map consumers (KB +
Event/Contract Catalog + grep callers), pick a backward-compatible staged strategy (expand → migrate
→ contract / versioned contracts / additive DB migrations), with a deprecation window and a rollback
per step. Confirm destructive/irreversible steps. Follow change-discipline.

What's changing (API / DB schema / event / library / config):
$ARGUMENTS
