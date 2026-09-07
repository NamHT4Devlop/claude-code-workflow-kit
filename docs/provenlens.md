# provenlens — the call graph the kit reads when it is there

`provenlens` is a separate tool ([NamHT4Devlop/provenlens](https://github.com/NamHT4Devlop/provenlens)):
it pre-indexes a repository into a graph of symbols and who-calls-what, stored in SQLite, and
answers questions grep structurally cannot.

This kit treats it as an **optional dependency**. Every skill works without it. Where it is
present, the skill uses it instead of grepping for callers — and where it is absent, the skill
says so in its output rather than passing a grep hit off as a resolved call.

---

## Why a call graph and not grep

Grep finds a **string**. A call graph finds a **call**. The gap is where the kit's worst failures
come from — an impact analysis that missed a caller, a "safe" deletion, a regression suite that
tested the wrong flow:

| The question a skill asks | What grep returns | What provenlens returns |
|---|---|---|
| Who calls `DonationService#record`? | every line containing `record` | the resolved callers, each with a confidence and how it was derived |
| Does this Spring controller reach the repository? | nothing — the hop goes through an interface | the chain, linked `interface->impl` at 0.9 |
| Who consumes the `order-events` queue? | the producer's own file | a Ruby Shoryuken worker in **another repository**, matched on the queue name |
| Is `formatReceipt` dead? | zero hits, so "yes" | **no** — an `.erb` template names it, and `dead` excludes it for that reason |
| What does `donor.name` resolve to? | nothing is declared | `belongs_to :donor` + `attr_reader :name`, both generated |

## What it covers, and what it does not

**Languages: Java, Ruby, TypeScript, JavaScript.** Nothing else. For Python, Go, C#, PHP, Rust or
Kotlin the fallback is the only path, and a skill must say so rather than imply coverage it does
not have.

Framework string-bindings it does resolve, in nine plugins: **MyBatis** (`@Mapper` ↔ `<select id>`),
**Camel** (`from()` ↔ `.to()`), **SQS** (producer ↔ `@SqsListener` / `@SqsMessageHandler` / Shoryuken,
across languages), **Kafka**, **HTTP routes** (a served route ↔ the client that calls it), **Spring
events**, **GraphQL**, **gRPC**, and **Flyway** (migration ↔ entity).

Every edge carries a `confidence` (1.0 `direct` … 0.4 `method-missing`) and a `via` note. When a
finding rests on a low-confidence edge, say which one.

---

## Setup (once per machine, once per repo)

```bash
git clone git@github.com:NamHT4Devlop/provenlens.git ~/AI-TOOL/provenlens && cd ~/AI-TOOL/provenlens && yarn install
```

```bash
ln -sf ~/AI-TOOL/provenlens/bin/provenlens.js ~/.local/bin/provenlens
```

Register the MCP server so Claude Code can call it directly (writes `~/.claude.json`, keeps a
`.bak`, and prints the change first):

```bash
provenlens install claude-user
```

Index a repository (the index is a cache in `.provenlens/` — never commit it):

```bash
cd /path/to/repo && provenlens init .
```

`scripts/onboard-project.sh` adds `.provenlens/` to the project's `.gitignore` and reports index
status, alongside the `cwk-sessions/` and `knowledge-base/` hygiene it already does.

## Two ways a skill reaches it

| | How | What it gets |
|---|---|---|
| **MCP** | `provenlens install claude-user` → tools `mcp__provenlens__provenlens_{explore,impact,affected,status,why}` | The five questions that come up most. Read-only, so a read-only sub-agent can be granted them without gaining shell access. |
| **CLI via Bash** | `provenlens <cmd>` | Everything, including the ones with no MCP tool: `callers`, `callees`, `node`, `query`, `routes`, `dead`, `cycles`, `hotspots`, `path`, `export`. |

Sub-agents in `agents/` are granted the **MCP tools only**. Handing them `Bash` to reach
`provenlens dead` would trade a read-only guarantee for one command; instead the parent skill (which
has `Bash`) runs those and passes the result into the sub-agent's prompt.

If the MCP server is not registered, the tool names in an agent's `tools:` list simply do not
resolve and the agent falls back to `Read/Grep/Glob`. That is the intended degradation.

## The commands, by the question they answer

| Question | Command | MCP |
|---|---|---|
| What is this, and what does it touch? | `provenlens explore "<name>"` | ✅ |
| What breaks if I change this? | `provenlens impact <symbol>` | ✅ |
| I changed these files — what do I re-test? | `git diff --name-only \| provenlens affected` | ✅ |
| Is the index good enough to trust? | `provenlens status`, `provenlens doctor` | `status` ✅ |
| Who calls / what does it call? | `provenlens callers` · `provenlens callees` | — |
| How much of this rests on a declaration, not a call? | `provenlens why <symbol>` | ✅ |
| Which HTTP routes does this serve, and who calls them? | `provenlens routes` | — |
| How does A end up reaching B? | `provenlens path <from> <to>` | — |
| What is safe to delete? | `provenlens dead` | — |
| What depends on itself? | `provenlens cycles` | — |
| What would hurt most to change? | `provenlens hotspots` | — |
| Give me the graph | `provenlens export --format json\|mermaid` | — |

`affected --fail-if-untested` exits **2** when the change touches production code that no test
reaches. That is a CI-grade gate, and the kit treats it as a blocker, not a note.

## Multi-repo

`provenlens serve` and the MCP server both accept a folder of checkouts: point either at a workspace
root and every indexed repo underneath answers. Cross-repo chains are walked through the binding
layer — a producer in one repo and a consumer in another are joined on the shared queue name or
endpoint URI. This is what `cwk-system-map` uses to mark an edge **confirmed** rather than
inferred.

---

## Beyond the skills: the shared resources

Two files are bundled into many skills at once, and both had no idea provenlens existed — which meant
the methodology said one thing and the shared checklist another:

- **`resources/review-skills-universal.md`** (bundled into 6 skills) opens with **§0 Evidence**: the
  table of which command settles which claim, the staleness rule, and the instruction to mark a
  finding `grep-depth` when it degraded. Every later section that makes a reach claim points back
  at it — layering in §1, N+1 in §4, "untested" in §6, dead code in §9.
- **`resources/kb-steps.md`** (bundled into `scan` and `rescan`) gains golden rule **8**: structural
  claims come from the graph where one exists, the graph is an **input and never the output** — a
  fan-in number is not a business meaning — and `_meta.yml` records the resolution figure so a
  reader can tell a KB built on a resolved graph from one built on grep.

Edit them in `resources/` and run `scripts/sync-bundles.sh`; the copies under
`skills/*/references/` are generated, and CI fails if they drift.

## The contract every skill follows

Each integrated skill carries a `### provenlens (optional)` block. The wording of its first
paragraph is identical everywhere on purpose — `tests/consistency.test.sh` checks for it, so the
fallback sentence cannot be quietly dropped from one skill:

1. **Prefer it when present.** `.provenlens/` exists → use it for anything about who-calls-what.
2. **Verify before trusting.** `provenlens status` once, and `provenlens sync` when the working tree has
   moved since the index was built. A stale or thin index is worse than none because it looks
   authoritative. `provenlens doctor` separates a resolver limit from an uninstalled dependency —
   identical in the number, nothing alike in the fix.
3. **Degrade loudly.** No index, no command, or an uncovered language → Grep/Glob, and write
   `⚠️ grep-depth only (no provenlens index)` in the output.
4. **Never launder a guess.** A grep hit is not a resolved call and must never be reported as one.
5. **Cite the confidence** when a conclusion rests on an edge below `direct`.

Nine skills go further — the ones whose output someone acts on without re-reading the code: `ask`,
`document`, `user-story`, `plan`, `runbook`, `fix-bug`, `build`, `review`, `qa`. Each bundles
`references/provenlens-evidence.md` and adds three required pieces to its output:

6. **An evidence line** at the top — `provenlens · <resolution>% · <languages> · synced <date>`, or
   `⚠️ grep-depth only`. The reader knows what the rest rests on before reading it.
7. **A reach ledger** — one row per anchor symbol *and per consumer `impact` returns*: covered in
   this output, or listed under Gaps as "reached, not covered". This is the anti-miss table: a
   consumer the graph knows and the document skipped is named, not lost.
8. **A code graph** — the `provenlens export --format mermaid` block pasted verbatim (truncation
   stated), and the `provenlens path` chain wherever the question is "how does A reach B". In a
   runbook every playbook carries that chain as its **Where in code** line, and the health routes
   come from `provenlens routes`.

## Which skills use it

**Integrated (27):** `ask` `build` `design-review` `discover` `document` `drift` `fix-bug` `map`
`migrate` `observe` `perf` `plan` `plan-review` `pr` `qa` `qa-integration` `rails-to-spring`
`rescan` `retro` `review` `runbook` `scan` `security-audit` `simplify` `skillify` `system-map`
`user-story`

**Deliberately not (3)** — they never reason about a call graph, and a block there would be noise:

| Skill | Why not |
|---|---|
| `cwk-issues` | Turns an **approved** plan into tickets. The blast radius is already in the plan; re-deriving it here is a second opinion nobody asked for. |
| `cwk-pdf` | Renders a Markdown/HTML file to PDF. It never opens the source. |
| `cwk-splunk-report` | Queries Splunk and posts to Slack — it may not even run inside the app's repo. |

`discover` and `qa-integration` were on that list and should not have been. Both turn on a reach
question — *"which existing flow does this touch?"* and *"which regressions do I run?"* — and
answering either from intuition is precisely what the block exists to stop.

That list is encoded in `tests/consistency.test.sh` — adding a skill without a block, or without
an entry there, fails the suite.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `no .provenlens/ found here or in any parent` | repo never indexed | `provenlens init .` |
| Coverage looks low in `status` | dependencies not installed, not a resolver bug | `provenlens doctor` says which |
| Agent ignores provenlens | MCP server not registered | `provenlens install claude-user`, then restart Claude Code |
| Answers are stale | index not synced | `provenlens sync` (or `sync --watch`); the MCP server syncs on first touch and watches after |
