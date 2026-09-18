# How a runbook should read

A runbook is read by an engineer who did not build the system, often during an incident. Write it
the way a senior engineer on the team would brief a new colleague: plainly, specifically, and
without performing. Readers stop trusting a document the moment it sounds generated, so tone is
not decoration here. It decides whether the page gets used.

## The business half comes first

Most incidents only make sense if you know what normal looks like. Before any playbook, the
runbook explains how the business works **as the code implements it**, in enough detail that
someone could answer a support ticket from it.

Cover whichever of these the system has, each with the real values and a `file:line`:

- **The main objects and their lifecycle.** Every status, with its stored value, what moves it
  there, and what has already happened by then. Say which states exist in the schema but are
  never written.
- **The core flow, step by step.** Numbered, in the order the code runs, with the checks it makes
  and the exact error text a user sees (and a translation if it is not in English). Say what is
  inside one transaction and what survives a rollback.
- **The numbers that govern behaviour.** Timeouts, limits, rates, thresholds, retention, taken from
  config or seed data, with where each is read. "Unpaid orders are cancelled after
  `normal_order_overtime` minutes, 120 in the shipped data" beats "orders time out".
- **Money, stock, quotas or anything else that must balance.** How each value changes at each step,
  and a query an operator can run to check it.
- **What happens when the user walks away**: timeouts, cancellations, expiry, what is given back
  and what is not.
- **What the admin side offers but the code ignores.** Settings, flags and screens with no effect.
  These generate support tickets that look like outages.
- **Business defects an on-call engineer will run into**, as a table: defect · what you will see ·
  where. Only things verified in the source.

Everything in this half must come from the KB or the code, and anything new you state must be
checked in the source before it is written. If the KB says it and the code disagrees, the code
wins and the KB gets corrected.

## Tone

Write like a person, not a report generator.

- **Plain declarative sentences.** Say what the system does. "Payment is Alipay only." Not
  "It is worth noting that payment appears to be limited to Alipay."
- **No commentary on your own text.** Never write "this matters more than the rest", "read this
  first", "which is itself a finding", "this is the central decision", "the key insight". If
  something matters, its content will show it.
- **No drumroll sentences.** Avoid short dramatic closers such as "That is the whole health
  signal." or "Nothing else." Fold the point into the sentence before it.
- **Emphasis is rare.** Bold only the step name in a numbered procedure, or one genuinely
  dangerous instruction per section. No ⚠ on every paragraph. If everything is highlighted,
  nothing is.
- **No framing labels.** Not "In plain words", "TL;DR", "Key takeaways", "The bottom line". Use
  headings that name the subject: "What this service is", "How the shop works".
- **Talk about the system, not the tooling.** One sentence at the top says the chains come from
  the provenlens index and at what resolution. After that, cite `file:line` and move on. Do not
  keep saying "verified", "resolved call graph", "the tool cannot know".
- **No "not X, but Y" reflexes, no groups of three for rhythm, few em dashes.** Commas and full
  stops do the job.
- **Concrete over abstract.** Real table names, real status values, real error strings, real
  numbers. "stock − lock_stock ≥ quantity" rather than "sufficient availability".
- **Say what you do not know once, where it matters,** as `❓` with who could answer. Do not
  repeat the caveat in every section.
- **Contractions and ordinary words are fine.** "doesn't", "stays", "gives back".

## Before and after

> Rollback — What rollback does NOT undo, and this line matters more than the rest of the
> section: ...

> A rollback does not undo: ...

> ⚠ This endpoint is reachable by **any logged-in member**, which is itself a finding.

> Any customer token works, which is a problem in itself, but it does make this usable in an
> emergency.

> ## In plain words
> `mall-portal` is the shop customers actually use. When it is down, **nobody can buy anything.**

> ## What this service is
> mall-portal is the customer side of the shop: catalogue, cart, checkout, payment, coupons, order
> history and return requests. If it is down, nobody can buy anything.

## Markdown

Wrap prose at about 100 columns; the renderer joins wrapped lines into one paragraph. Indent code
blocks and continuation lines under a numbered step by three spaces so the step keeps its number.
Tables for lookups (status values, defects, settings), prose for explanations, numbered lists for
procedures.
