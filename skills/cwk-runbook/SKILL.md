---
name: cwk-runbook
description: >-
  Produce an operational runbook a teammate can follow at 2am — health checks,
  deploy and rollback, symptom→diagnosis→fix playbooks for the failures this
  system actually has, alert-to-action mapping, data recovery (migrations, DLQ
  replay), and escalation. Grounded in the Knowledge Base, the real deploy/CI
  config and the error handling in the code; anything only a human knows is
  marked as a gap, never invented. Use when the user says "/runbook", "make a
  runbook", "on-call guide", "operations doc", "what do we do when X breaks",
  or wants the KB turned into something the team can operate from.
---

# cwk-runbook — turn the Knowledge Base into something you can act on at 2am

A Knowledge Base explains **how the system works**. A runbook answers a different question: **what
do I do right now?** The two are not the same document and should not be written the same way. The
KB is read while you think; the runbook is read while something is on fire — by someone who may not
have built this, at an hour when they are not at their best.

That difference drives every rule below: **imperative, exact, and honest about what it doesn't know.**

## Inputs
- **Scope** — one service/app (best), or a module. A runbook for "everything" helps nobody; if the
  repo holds several deployables, ask which one, or produce one file per service.
- `knowledge-base/` — required for the business half. Missing → say so and point at `/cwk-scan`;
  you can still produce the operational half from config, at lower confidence.

## Where the evidence comes from
Read **both** halves, and cite files for everything:

| Section | Ground it in |
|---|---|
| What this service is, who it serves | KB `04-business-domain`, `06-modules`, `01-project-structure` |
| Dependencies that can take it down | KB `14-integrations`, `17-async-events`, `08-database-schema` |
| Deploy / rollback | `.github/workflows/`, `.gitlab-ci.yml`, `Jenkinsfile`, `Dockerfile`, k8s manifests, `helm/`, `terraform/`, `Procfile`, deploy scripts in `package.json`/`Makefile` |
| Health & readiness | actual health endpoints in the code, k8s probes, load-balancer config |
| Config & secrets | `.env.example`, config classes, secret **names** (never values) |
| Failure modes | KB `15-error-scenarios`, plus real `catch`/`rescue`/error branches, retry/timeout settings, circuit breakers, DLQ config |
| Data recovery | migration tool (Flyway/Prisma/Liquibase), backup config, queue redrive settings |
| Alerts | monitoring config in the repo, log/metric names actually emitted |
| Where a playbook lands in the code | `provenlens path <entry point> <external call>` — the chain hop by hop, `file:line` each; `provenlens export --format mermaid` for the service-card graph (`references/provenlens-evidence.md`) |
| Served HTTP routes — health, readiness, the endpoint an alert names | `provenlens routes` when indexed; the README's list is a claim, the router is the fact |

### provenlens (optional)
`.provenlens/` present → prefer `provenlens` over grep for anything about **who calls what**: it resolves
through DI, interfaces, mixins and framework string-bindings (MyBatis · Camel · SQS · Kafka · HTTP routes · Spring events · GraphQL · gRPC · Flyway) and
scores every edge. Confirm it with `provenlens status`, and run `provenlens sync` first if the working
tree has moved since it was built — **a stale index is worse than none, because it looks
authoritative**. If coverage reads low, `provenlens doctor` says whether that is a resolver limit or
just an uninstalled dependency; those look identical in the number and are nothing alike in the fix.
No index, no `provenlens` command, or a language it does not cover (**Java · Ruby · TS/JS** only) →
fall back to Grep/Glob and write `⚠️ grep-depth only (no provenlens index)` in the output. A grep hit
is never a resolved call — do not report it as one. Playbook: `docs/provenlens.md`.

**Here:**
- **Protocol:** `references/provenlens-evidence.md` — the evidence line, the **reach ledger** and the pasted **code graph** are required parts of this skill's output, not options; the ledger is what turns "nothing was missed" into a checked claim.
- `provenlens explore "<entry point>"` — the real call chain behind an alert, so symptom → diagnosis
  points at the function that actually runs rather than the one with the matching name.
- `provenlens hotspots` — the components whose failure is widest earn a playbook first; that is the
  ordering an on-call reader needs at 2am.
- `provenlens path <entry point> <external call>` — where a downstream dependency enters the flow,
  which is what a "third party is down" playbook has to name.
- `provenlens routes` — the routes this service really serves, with their callers; the health and
  readiness checks in "Is it healthy?" are cited from here, not from a README.
- `provenlens export --format mermaid` centred on the entry points (or the top `hotspots`) → the
  service card's code graph; the **reach ledger** of those hotspots says what falls over with each.

## Procedure
1. **Pick the scope and name the service** the way the team says it out loud, not the folder name.
2. **Harvest the operational facts** from the table above. When two sources disagree (the README
   says one deploy command, CI does another), **believe the CI config** and note the discrepancy —
   a stale README is exactly how a runbook gets someone into trouble.
3. **Build the failure catalogue from what this system really does.** Do not paste a generic list.
   Every incident entry must trace to something concrete: an integration that can time out, a queue
   with a DLQ, a migration that isn't backward-compatible, an auth dependency, a rate limit, a
   scheduled job. If the code cannot fail that way, leave it out.
4. **Write each playbook as steps someone can execute**, in this shape:
   ```
   ### Symptom: orders stop appearing, queue depth climbing
   Likely cause · Consumer is failing and messages are landing in the DLQ.
   Where in code · `provenlens path OrdersConsumer#handle PaymentsClient#charge` →
                   OrdersConsumer#handle (app/consumers/orders.rb:41) → OrderService#record (…:88)
                   → PaymentsClient#charge (…:17)      [or: ❓ not reachable in the graph]
   1. Confirm     — <exact command / dashboard / query>            → you should see …
   2. Contain     — <the safe first action: scale, disable a flag, pause the consumer>
   3. Diagnose    — <where the error is logged; what to grep for>
   4. Fix         — <the action>            ⚠ DESTRUCTIVE / needs approval: <yes|no>
   5. Verify      — <how you know it worked, an actual check not a feeling>
   6. If it fails — escalate to <role>, and capture <what> for the postmortem
   ```
5. **Mark what only a human knows — do not guess it.** Owners, on-call rotation, phone numbers,
   SLA/SLO targets, business escalation, maintenance windows, whether an action needs sign-off.
   These belong in a short **"Fill this in"** block at the top of the section that needs them.
   A fabricated escalation path is worse than an empty one: someone will follow it.
6. **Flag every dangerous action explicitly** — anything that deletes data, replays a queue,
   restarts production, rolls back a migration, or touches money. Mark it `⚠ DESTRUCTIVE`, say what
   it cannot be undone from, and state who must approve. **Never run these yourself** — this skill
   writes a document, it does not operate anything.
7. **Verify the commands you wrote are real.** Every command must come from a file you read (cite
   it). If you inferred one, label it `UNVERIFIED — confirm before relying on this`. A runbook full
   of plausible-looking commands that don't exist is the failure mode to avoid.

## Output (dual-audience; save + render HTML)
Save to `cwk-sessions/runbook/<service>-<date>.md`, render with the bundled renderer, and open it.
Resolve this skill's `references/` dir first (call it `$SKILL_DIR`):
`${CLAUDE_PLUGIN_ROOT}/skills/cwk-runbook/references` if `CLAUDE_PLUGIN_ROOT` is set, else the
`references/` folder next to this SKILL.md, else `$HOME/.claude/skills/cwk-runbook/references`.
```bash
node "$SKILL_DIR/render-html.cjs" <md> <html> "Runbook — <service>"
```

```
# Runbook — <service>

## In plain words (for anyone, including non-engineers)
What this service does, what users lose when it is down, and how urgent that is.

## Fill this in (owner-only — the tool cannot know these)
| Field | Value |
| Service owner / team | ❓ |
| On-call channel & rotation | ❓ |
| Severity ladder & SLA | ❓ |
| Business escalation (who decides on customer impact) | ❓ |

## Service card
Purpose · criticality · runtime & where it runs · upstream/downstream dependencies · data stores ·
queues/topics · scheduled jobs. Each with a file citation.
**Code graph (provenlens)** — `export --format mermaid` centred on the entry points (or the top
`hotspots`), pasted verbatim, then the **reach ledger** of those hotspots: what stops working when
each one does. State the commit the graph was taken at, or `⚠️ grep-depth only (no provenlens index)`.

## Before you touch anything
Access you need · which environment is which · the read-only checks that are always safe.

## Is it healthy?
The exact checks, in order, with what a good answer looks like. Health/readiness routes come
from `provenlens routes` or the router file — cite which.

## Deploy · rollback
Normal deploy · how to roll back · how long it takes · what rollback does NOT undo
(migrations, consumed messages, sent emails) — this line matters more than the rest.

## Incident playbooks
One per real failure mode, in the Symptom/Confirm/Contain/Diagnose/Fix/Verify/Escalate shape, each
with its **Where in code** chain (or `❓ not reachable in the graph`).

## Alerts → what to do
| Alert / log signature | Means | First action | Playbook |

## Data & recovery
Migrations (forward + backward) · DLQ / redrive · backups & restore · reconciliation jobs.
Mark destructive steps.

## Ask this runbook
A runbook is a snapshot. For "what happens if X fails *now*", ask `/cwk-ask` inside the repo: it
reads this file, re-runs `provenlens path` / `impact` against the current index and answers with the
live chain, citing the playbook it started from. Graphs above were taken at commit <sha>.

## Known gaps
What could not be determined from the repo, and who could answer it. Be specific — this list is
the to-do that makes the next version of this runbook better.
```

Also append one row to `cwk-sessions/runbook/_journal.md`
(`| Date | Service | Playbooks | Gaps | Source commit |`) so it is visible when a runbook is aging.

## Where it should live (ask, don't assume)
A runbook is useless if nobody can find it during an incident. Offer, in order: the team's wiki/
Confluence (paste-ready), `RUNBOOK.md` in the service repo, or the KB hub if one exists
(`scripts/kb-export.sh`). **Writing into a team repo needs the user's explicit OK** — this kit's
default is zero footprint in repos you don't own.

## Rules
- **Never invent a command, endpoint, dashboard, alert name, owner or phone number.** Cite the file,
  or mark it `UNVERIFIED`, or leave a `❓`. This is the whole difference between a runbook and a
  liability.
- **Never put secrets in it** — name the variable and where it lives, never the value. Runbooks get
  pasted into chat during incidents.
- **A function named in a playbook comes from `explore`/`path`, never from a name match.** The one
  with the matching name is how a 2am reader ends up in the wrong file.
- **This skill writes; it does not operate.** No deploying, restarting, replaying, or migrating.
- **Prefer the safe action first.** Every playbook contains a containment step before a fix step —
  in an incident, stopping the bleeding beats being right.
- **Say when a failure mode has no known fix.** "We don't have a procedure for this" is real
  information; an invented procedure is not.
- Keep it short enough to be read under stress: imperative sentences, no essays, tables over prose.

## Common rationalizations

| What you'll tell yourself | What's actually true |
|---|---|
| "I'll put a sensible default escalation path" | An invented escalation path is worse than an empty one: at 2am someone will follow it. Leave `❓`. |
| "This command is standard, no need to cite it" | Standard for which version, which cluster, which account? A command nobody verified is the one that fails when it matters. |
| "A generic incident list is better than nothing" | It is not. It buries the two failures this system actually has under twenty it cannot have. |
| "The README says the deploy command is X" | And CI says Y. Believe CI, and record the discrepancy — a stale README is how a runbook gets someone into trouble. |

## Red flags

- A command in the document that you did not read out of a file.
- A playbook with a Fix step but no Contain step.
- A destructive action with no ⚠ and no named approver.
- The rollback section does not say what rollback **cannot** undo.

## Verification

- [ ] Every command is cited to a file, or labelled `UNVERIFIED`.
- [ ] The "Fill this in" `❓` block is present — owners/on-call/SLA are not invented.
- [ ] Every playbook has Confirm → Contain → Diagnose → Fix → Verify → Escalate.
- [ ] Destructive steps marked, with what they cannot be undone from.
- [ ] Known gaps listed with **who** can answer each.
- [ ] Service card carries the pasted code graph + reach ledger (or the ⚠️ grep-depth line); every
      playbook has a Where-in-code chain or `❓ not reachable in the graph`.
