# provenlens evidence protocol — how an investigating skill avoids being wrong, and avoids missing

Two failures matter when a skill investigates code for someone who will act on the result:

- **Wrong** — a claim about reach ("X is called from Y", "nothing uses this") that rests on a name
  match. A grep hit is not a call.
- **Missing** — a consumer, flow or caller that the graph knows about and the document never mentions.
  Nobody notices an absence.

This file is the shared recipe that closes both. It applies wherever a `.provenlens/` index exists
(Java · Ruby · TypeScript · JavaScript). Where it does not, §4 says exactly how to degrade — out loud.

---

## 0. Preflight — once per run, before any claim

```bash
provenlens status          # index present? languages? resolution %  (the number you will quote)
git status --porcelain     # tree moved since the index was built? → provenlens sync
provenlens doctor          # resolution reads low → resolver limit, or dependencies not installed
```

Open the output with one evidence line, so the reader knows what the rest rests on:

```
Evidence: provenlens · <resolution>% of in-repo calls resolved · <languages> · index synced <date>
```
or, when there is nothing to stand on:
```
Evidence: ⚠️ grep-depth only (no provenlens index)
```

## 1. Anchor symbols — resolve, never assume

List the symbols the task is about: the entities, entry points, services, fields, queues. Resolve
**each** with `provenlens explore "<name>"` (three best matches with source, callers, callees) or
`provenlens node <fqn>` (exactly one). Cite the `file:line` the tool prints. If `explore` returns no
match, write **"not found in the graph"** — do not substitute a file you located by its name.

## 2. Reach ledger — the anti-miss table

For every anchor symbol run both, and keep the raw output in the session folder:

```bash
provenlens callers <symbol> --json      # direct callers, with via + confidence + call lines
provenlens impact  <symbol>             # transitive: everything that can reach it, by depth
```

Then write the ledger. One row per anchor, and **one row per consumer `impact` returned**:

| Symbol | Direct callers | Transitive reach | Covered in this output? | Where — or why not |
|---|---|---|---|---|
| `Order#total` | 3 | 11 symbols / 4 files | ✅ | §3 flow step 4 · TC-07 |
| `InvoiceJob#perform` (reached via `Order#total`) | — | — | ❌ | **reached, not covered** — out of scope; see Gaps |

The rule that makes the table worth writing: **every symbol `impact` names is either covered
somewhere in the document (a flow step, an AC, a test, a playbook) or listed under Gaps as
"reached, not covered: `<fqn>` — <reason>".** Silence is not an option. An edge whose `via` is not
`direct` carries its confidence in the cell (`0.6 interface->impl`), and a conclusion resting on
an edge below `direct` says so.

## 3. Code graph — the picture, pasted, not drawn

```bash
provenlens export --format mermaid -d 2 -m 60 <symbol>     # the neighbourhood around one symbol
provenlens path <from> <to>                                # one chain, hop by hop, file:line each
```

Paste the `export` block **verbatim** under a heading `## Code graph (provenlens)`. Keep the
`%% truncated` comment when it is there and say so in the prose — a picture that stops at the cap
is not the whole picture. Use `path` whenever the question is "how does A end up reaching B"; its
output *is* the answer, and it names the hop where an external call or a queue enters.

Under the graph, one legend line: *nodes are `file:Class#member`; `declares` is structure,
`calls` is a resolved call; an edge label carrying `via · confidence` is not a direct call.*

Budget: one graph per anchor symbol. More than three anchors → draw the ones `provenlens hotspots`
ranks highest and list the rest by name.

## 4. Without an index — degrade where the reader can see it

No `.provenlens/`, no `provenlens` command, or a language it does not cover:

- The evidence line reads `⚠️ grep-depth only (no provenlens index)`.
- The ledger is still written, from Grep, with every count marked `(grep)` — a hit count is not a
  caller count and the marker says so.
- The graph section holds a hand-drawn Mermaid diagram titled **"inferred from imports and names —
  not resolved calls"**. Never present it as the output of `export`.
- Absence of a path is never proof of safety; reflection, dynamic dispatch and string-built calls
  are exactly what a graph — and grep — cannot see. Say it once in Gaps.

## 5. What each skill adds on top

| Skill | The ledger feeds | The graph goes |
|---|---|---|
| `ask` | the Technical detail — callers of the thing asked about | after the Diagram; `path` for "how does A reach B" |
| `document` | §2 fields (which flows read them) and §6 gaps | §3b, one per business flow entry point |
| `user-story` · `plan` | Dependencies, Impact Analysis, regression ACs | Investigation Notes / impact-analysis doc |
| `build` · `fix-bug` | one regression test per ledger row, or an explicit "not covered" | the plan (§2) and the evidence / hotfix report |
| `review` · `qa` | Phase 2 "no logic removed" · the traceability matrix evidence column | the review when a finding rests on a chain |
| `runbook` | the service card: what falls over with each hotspot | the service card, and a `path` chain in every playbook |

## Verification — before the output is called done

- [ ] The evidence line is at the top and states the depth (resolution %, or grep-depth).
- [ ] Every anchor symbol was resolved with `explore`/`node` and is cited `file:line` from that output.
- [ ] The reach ledger is complete: every `impact` row is covered, or listed under Gaps as reached-not-covered.
- [ ] The code graph is pasted from `export`/`path`; truncation is stated; the legend line is present.
- [ ] No grep hit is reported as a resolved call; every edge below `direct` shows its confidence.
