# codelens — the call graph the kit reads when it is there

`codelens` is a separate tool ([NamHT4Devlop/codelens](https://github.com/NamHT4Devlop/codelens)):
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

| The question a skill asks | What grep returns | What codelens returns |
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

Framework string-bindings it does resolve: **MyBatis** (`@Mapper` ↔ `<select id>`), **Camel**
(`from()` ↔ `.to()`), **SQS** (producer ↔ `@SqsListener` / `@SqsMessageHandler` / Shoryuken,
across languages), **Flyway** (migration ↔ entity).

Every edge carries a `confidence` (1.0 `direct` … 0.4 `method-missing`) and a `via` note. When a
finding rests on a low-confidence edge, say which one.

---

## Setup (once per machine, once per repo)

```bash
git clone git@github.com:NamHT4Devlop/codelens.git ~/AI-TOOL/codelens && cd ~/AI-TOOL/codelens && yarn install
```

```bash
ln -sf ~/AI-TOOL/codelens/bin/codelens.js ~/.local/bin/codelens
```

Register the MCP server so Claude Code can call it directly (writes `~/.claude.json`, keeps a
`.bak`, and prints the change first):

```bash
codelens install claude-user
```

Index a repository (the index is a cache in `.codelens/` — never commit it):

```bash
cd /path/to/repo && codelens init .
```

`scripts/onboard-project.sh` adds `.codelens/` to the project's `.gitignore` and reports index
status, alongside the `namht-sessions/` and `knowledge-base/` hygiene it already does.

## Two ways a skill reaches it

| | How | What it gets |
|---|---|---|
| **MCP** | `codelens install claude-user` → tools `mcp__codelens__codelens_{explore,impact,affected,status}` | The four questions that come up most. Read-only, so a read-only sub-agent can be granted them without gaining shell access. |
| **CLI via Bash** | `codelens <cmd>` | Everything, including the five with no MCP tool: `dead`, `cycles`, `hotspots`, `path`, `export`. |

Sub-agents in `agents/` are granted the **MCP tools only**. Handing them `Bash` to reach
`codelens dead` would trade a read-only guarantee for one command; instead the parent skill (which
has `Bash`) runs those and passes the result into the sub-agent's prompt.

If the MCP server is not registered, the tool names in an agent's `tools:` list simply do not
resolve and the agent falls back to `Read/Grep/Glob`. That is the intended degradation.

## The commands, by the question they answer

| Question | Command | MCP |
|---|---|---|
| What is this, and what does it touch? | `codelens explore "<name>"` | ✅ |
| What breaks if I change this? | `codelens impact <symbol>` | ✅ |
| I changed these files — what do I re-test? | `git diff --name-only \| codelens affected` | ✅ |
| Is the index good enough to trust? | `codelens status`, `codelens doctor` | `status` ✅ |
| Who calls / what does it call? | `codelens callers` · `codelens callees` | — |
| How does A end up reaching B? | `codelens path <from> <to>` | — |
| What is safe to delete? | `codelens dead` | — |
| What depends on itself? | `codelens cycles` | — |
| What would hurt most to change? | `codelens hotspots` | — |
| Give me the graph | `codelens export --format json\|mermaid` | — |

`affected --fail-if-untested` exits **2** when the change touches production code that no test
reaches. That is a CI-grade gate, and the kit treats it as a blocker, not a note.

## Multi-repo

`codelens serve` and the MCP server both accept a folder of checkouts: point either at a workspace
root and every indexed repo underneath answers. Cross-repo chains are walked through the binding
layer — a producer in one repo and a consumer in another are joined on the shared queue name or
endpoint URI. This is what `namht-system-map` uses to mark an edge **confirmed** rather than
inferred.

---

## The contract every skill follows

Each integrated skill carries a `### codelens (optional)` block. The wording of its first
paragraph is identical everywhere on purpose — `tests/consistency.test.sh` checks for it, so the
fallback sentence cannot be quietly dropped from one skill:

1. **Prefer it when present.** `.codelens/` exists → use it for anything about who-calls-what.
2. **Verify before trusting.** `codelens status` once. A stale or thin index is worse than none
   because it looks authoritative.
3. **Degrade loudly.** No index, no command, or an uncovered language → Grep/Glob, and write
   `⚠️ grep-depth only (no codelens index)` in the output.
4. **Never launder a guess.** A grep hit is not a resolved call and must never be reported as one.
5. **Cite the confidence** when a conclusion rests on an edge below `direct`.

## Which skills use it

**Integrated (25):** `ask` `build` `design-review` `document` `drift` `fix-bug` `map` `migrate`
`observe` `perf` `plan` `plan-review` `pr` `qa` `rails-to-spring` `rescan` `retro` `review`
`runbook` `scan` `security-audit` `simplify` `skillify` `system-map` `user-story`

**Deliberately not (5)** — they never reason about a call graph, and a block there would be noise:

| Skill | Why not |
|---|---|
| `namht-discover` | Runs before any code exists. |
| `namht-issues` | Turns an approved plan into tickets; touches a tracker, not a repo. |
| `namht-pdf` | Renders a Markdown/HTML file to PDF. |
| `namht-qa-integration` | Drives a live browser against a running app; its evidence is the DOM, not the source. |
| `namht-splunk-report` | Queries Splunk and posts to Slack. |

That list is encoded in `tests/consistency.test.sh` — adding a skill without a block, or without
an entry there, fails the suite.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `no .codelens/ found here or in any parent` | repo never indexed | `codelens init .` |
| Coverage looks low in `status` | dependencies not installed, not a resolver bug | `codelens doctor` says which |
| Agent ignores codelens | MCP server not registered | `codelens install claude-user`, then restart Claude Code |
| Answers are stale | index not synced | `codelens sync` (or `sync --watch`); the MCP server syncs on first touch and watches after |
