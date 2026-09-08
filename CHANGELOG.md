# Changelog

All notable changes to this kit. The format follows [Keep a Changelog](https://keepachangelog.com/),
and versions follow [Semantic Versioning](https://semver.org/) — for a toolkit that means:

- **MAJOR** — you have to do something after updating (a renamed folder, a removed command, a
  changed artifact layout).
- **MINOR** — new skills or capabilities; `git pull` and carry on.
- **PATCH** — fixes and doc corrections only.

Two things are versioned separately: the **plugin** (`.claude-plugin/plugin.json`, the skills and
commands) and the **VS Code extension** (`vscode-extension/package.json`). The extension version is
noted per release when it changed.

---

## [3.2.1] — 2026-09-08

### Fixed

- **`kb-pipeline.sh` ran the scan and produced nothing.** It invoked `claude -p` with no
  `--permission-mode`, and a headless run cannot answer an approval prompt: the first write is
  refused, so the pipeline reported success over an empty `knowledge-base/`. Verified directly —
  a bare `claude -p` asked to write a file came back refusing. It now passes
  `--permission-mode acceptEdits` by default, validates the value against what the CLI accepts, and
  prints the mode in the plan you confirm. `bypassPermissions` is documented as what makes every
  step run, with its trade-off, and left opt-in: the safe mode is the default and the hammer is
  named. Four more cases pin the pass-through and the rejection of an invented mode.

---

## [3.2.0] — 2026-09-08

### Added — one command for the whole chain, and the code graph reachable from the page

The kit could produce a Knowledge Base, a runbook and a code graph, and a reader had to know all
three existed and where each landed. Two gaps closed:

- **`scripts/kb-pipeline.sh`** runs the chain over any number of checkouts: `provenlens init` →
  `/cwk-scan` → `/cwk-runbook` → `/cwk-map`, then `kb-export` + `kb-site`. It **never clones** — a
  URL is rejected as a path, so it can only touch repos you already have — prints the full plan with
  a per-repo step list and a cost warning before spending a token, and skips any step whose output
  exists unless `--force`. A scan is the most expensive thing in this kit, so the plan comes first
  and the prompt comes before the first one. 15 fixture cases behind stubbed `claude`/`provenlens`.
- **The code graph is one click from the KB page.** `kb-export.sh` carries the newest
  `cwk-sessions/maps/*.html` into the hub as `code-graph.html`; `kb-site.cjs` renders a **⛓ Code
  graph** link per project, with the href computed relative to the page it writes. Linked rather
  than inlined: a few hundred KB of Cytoscape per project would turn the searchable page into the
  page nobody opens. Four cases pin the carry and both href placements — a dead link that looks
  fine is the failure worth testing for.

### Note on picking repos by benchmark score

Ranking provenlens's 10,000-repo sweep by its resolution figure does **not** select repos worth
documenting. The figure is `linked / (linked + missed)`, so a repository whose calls are almost all
into libraries has a denominator of a few dozen and scores 100% on nothing: of the 4,144 repos at
100%, **74% have fewer than 50 in-repo calls**. Ranking by graph density instead surfaces JDK source
dumps and asset repositories. That corpus is a random sweep built to measure a resolver against hard
cases, not a shortlist of well-engineered applications — see README's hub section for what to point
the pipeline at instead.

---

## [3.1.0] — 2026-09-08

### Added — runbooks are in the searchable page, not just the KB

The one-page KB site (`scripts/kb-site.cjs`) rendered `knowledge-base/` and nothing else. The
runbook — the document someone actually searches under pressure, because "what do we do when X
fails" is a question asked at 2am and not at leisure — was left in `cwk-sessions/runbook/`, a
gitignored folder, reachable only by whoever generated it. The page built to make documents
findable was excluding the most time-critical one.

- `kb-site.cjs` now collects a project's runbooks alongside its KB, from
  `<repo>/cwk-sessions/runbook/` in the single-repo shape and `<hub>/projects/<name>/runbook/` in a
  hub. Each arrives with the id `runbook/<file>`, so it renders as **`runbook / <name>`** and a
  search hit is recognisable as a runbook rather than a KB page. The console line counts them.
- `kb-export.sh` carries `cwk-sessions/runbook/` into the hub beside `knowledge-base/`, which is
  what makes a runbook readable by a teammate at all: it is generated into a gitignored folder, so
  before this the hub was not merely missing it — nothing could reach it.
- Five cases in `tests/kb-hub.test.sh` pin it: carried into the hub, present in the page, titled as
  a runbook, its prose searchable, and found in the single-repo shape.

### Changed

- README's hub section, the two script headers and the SECURITY.md row for `kb-export.sh` all say
  what the export now carries. A document that travels further than the reader expects is a
  disclosure question, so it belongs in the security notes, not only in the feature list.

---

## [3.0.0] — 2026-09-08

### Changed — the kit is `cwk`; the personal prefix is gone

The repository became `claude-code-workflow-kit` in 2.9; the commands, skills, agents, hook, artifact
folder and extension were still called `namht-*`. Now everything carries the repo's own
abbreviation, **`cwk`**, and the display name is **Workflow Kit**:

| Was | Is |
|---|---|
| `/namht:build` (plugin) · `/namht-build` (personal) | `/cwk:build` · `/cwk-build` |
| `skills/namht-<x>` · `agents/namht-<x>` | `skills/cwk-<x>` · `agents/cwk-<x>` |
| plugin `namht`, marketplace `namht-marketplace` | plugin `cwk`, marketplace `cwk-marketplace` |
| `namht-sessions/` (every artifact the kit writes) | `cwk-sessions/` |
| `~/.claude/hooks/namht-git-guard.sh` | `~/.claude/hooks/cwk-git-guard.sh` |
| cron marker `# namht-kit` | `# cwk-kit` |
| extension `namht-spec-ui`, settings `namhtSpecUi.*`, view `namhtSpec` | `cwk-ui`, `cwkUi.*`, `cwk` |

This is a MAJOR release because a user has to do things after updating, and each one is covered:

- **`scripts/migrate-sessions.sh` knows the second legacy name.** It renames `spec-kit-sessions/`
  *or* `namht-sessions/` to `cwk-sessions/`, merges without overwriting when more than one exists,
  and leaves anything it could not merge in place. Two new fixture cases pin it.
- **`scripts/schedule.sh` still owns its 2.x cron lines.** `list` shows entries with either marker,
  `add` replaces a `# namht-kit` entry instead of duplicating it, `remove` finds one. A job only the
  old name could reach would have been a job nobody can delete.
- **The 2.x hook alias is kept alive.** `personal-install.sh` links `hooks/cwk-git-guard.sh`; if a
  `namht-git-guard.sh` link exists it is refreshed rather than removed, because settings.json still
  names it and a hook whose file is gone stops running with no visible sign — the guard would be off
  silently. Point settings.json at the new name, then uninstall/install once to drop the alias.
- The VS Code extension reads its settings under new keys; values under `namhtSpecUi.*` are not
  migrated (six keys, all with defaults). The report-path detector recognises `cwk-`, `namht-` and
  `spec-kit-sessions` paths so old run logs still open their reports.
- Earlier changelog entries keep the old names; they describe the versions they describe.

### Fixed

- **`migrate-sessions.sh` could delete a file it had refused to merge.** When both folders existed it
  skipped a same-named file on the legacy side (correct — never overwrite), then removed the legacy
  tree because its "everything is on the new side" check only asked whether a file with that *name*
  existed. The skipped file's content went with the tree. The check now compares content (`cmp`);
  a legacy folder holding an unmerged file stays in place, exit 1, and the test that used to assert
  the deletion now asserts the survival.

### After updating

```
/plugin uninstall namht                        # plugin install (Option A)
/plugin marketplace remove namht-marketplace
/plugin marketplace add <PLUGIN_DIR>  →  /plugin install cwk@cwk-marketplace
```
```bash
scripts/personal-install.sh                    # personal install (Option C): relinks as cwk-*
scripts/migrate-sessions.sh /path/to/each/repo # namht-sessions/ → cwk-sessions/
echo 'cwk-sessions/' >> ~/.gitignore_global
```
Then change `namht-git-guard.sh` to `cwk-git-guard.sh` in `~/.claude/settings.json` and reload.

---

## [2.10.0] — 2026-09-08

### Added — the evidence protocol: a reach ledger and a pasted code graph, where someone will act on the output

2.7–2.9 made the call graph *available* to 27 skills. Available is not the same as used: a skill
could run `provenlens impact`, read the list, and still write a document that mentioned half of
it — and nobody notices an absence. Two failures were left open: being **wrong** (a reach claim
that rests on a name match) and being **incomplete** (a consumer the graph knows and the document
never names).

- **`resources/provenlens-evidence.md`** — a shared, bundled protocol in five steps: a preflight and
  an **evidence line** at the top of the output (resolution %, languages, sync date — or
  `⚠️ grep-depth only`); anchor symbols resolved with `explore`/`node` and cited `file:line` from
  that output; a **reach ledger** with one row per anchor *and per consumer `impact` returns*, each
  either covered in the document or listed under Gaps as "reached, not covered"; a **code graph**
  pasted verbatim from `provenlens export --format mermaid` (truncation stated) and `provenlens
  path` wherever the question is "how does A reach B"; and the exact wording for degrading without
  an index. It ends with a verification checklist.
- **Nine skills carry it** — the ones whose output someone acts on without re-reading the code:
  `ask`, `document`, `user-story`, `plan`, `runbook`, `fix-bug`, `build`, `review`, `qa`. Each
  bundles the file (`map_evidence` in `scripts/sync-bundles.sh`), points at it from `**Here:**`,
  and gains the required output sections: `ask` a **Code graph (provenlens)** section after the
  diagram; `document` §3b and reached-not-covered rows in §6; `user-story` and `plan` the ledger
  and graph in Investigation Notes / the impact-analysis doc, with an uncovered consumer becoming a
  🔴 must-confirm item; `build` a **Reach ledger vs tests** table in EVIDENCE.md and a verification
  box; `fix-bug` the `path` chain in step 3, the ledger in step 6, both in the hotfix report;
  `review` a **REACH LEDGER** block in the output format; `qa` the ledger row as the traceability
  evidence column.
- **Runbook, specifically.** Every playbook carries a **Where in code** line — the `provenlens path`
  chain from the entry point to the external call, `file:line` each hop, or `❓ not reachable in
  the graph`. The service card carries the pasted graph centred on the entry points and a reach
  ledger of the hotspots (what falls over with each). Health and readiness routes are cited from
  `provenlens routes`, not a README. A new **Ask this runbook** section says the graphs are a
  snapshot at a commit, and `/namht-ask` learned to answer operational questions ("what do we do
  when X fails") from the runbook while re-running `path`/`impact` against the current index, so
  the answer is live and cites the playbook it started from.
- **Enforced.** `tests/consistency.test.sh` checks that each of the nine bundles the file, points at
  it, and has a reach ledger in its output; `sync-bundles --check` catches a copy that is not
  mapped. `docs/skill-anatomy.md` gains the row; `docs/provenlens.md` the contract points 6–8.

The output shapes the protocol pastes — `export --format mermaid`, `explore`, `path`, `impact`,
`callers --json`, `routes`, `why` — were captured from a real provenlens run before being written
down, not recalled.

---

## [2.9.0] — 2026-09-08

### Changed — the call-graph dependency is `provenlens`, and the kit now says so

The tool the kit reads for who-calls-what was renamed upstream from `codelens` to
[`provenlens`](https://github.com/NamHT4Devlop/provenlens): the binary, the MCP server name, the index
folder and the repository all moved. The kit did not follow, and the failure was silent by design —
every skill treats a missing index as "fall back to grep and say so", so on a machine with
`provenlens` installed the seven sub-agents asked for `mcp__codelens__*` tools that no longer
resolved, the skills ran `codelens status` against a binary that no longer existed, and every
blast radius quietly came from grep. The `⚠️ grep-depth only` label was correct and nobody was
reading it.

- **Every reference moves together** — `mcp__provenlens__provenlens_{explore,impact,affected,status}`
  in the 7 agents, the `### provenlens (optional)` block in 27 skills, the two shared resources and
  their bundled copies, `scripts/onboard-project.sh` (ignores `.provenlens/`), the map builder
  (`skills/namht-map/references/provenlens-graph.cjs`, `PROVENLENS=0` to force the regex scan),
  `tests/consistency.test.sh`, README, SECURITY.md, the setup guides and the catalog.
  `docs/codelens.md` is now `docs/provenlens.md`.
- **The playbook is corrected against the tool, not renamed from memory.** provenlens exposes five
  MCP tools (`why` is new: how much of what the graph says rests on a declaration rather than a
  call), resolves string-bindings in nine plugins (MyBatis · Camel · SQS · Kafka · HTTP routes ·
  Spring events · GraphQL · gRPC · Flyway — the shared paragraph in the 27 skills said four), and
  has a `routes` command. The export JSON shape the map builder parses was checked against a real
  `provenlens export` before the rename was trusted.
- Nothing in this release changes what a skill does when there is no index. Earlier changelog
  entries keep the old name; they describe the versions they describe.

### After updating

An index built by the old tool lives in `.codelens/` and is not read. Run `provenlens init .` in
each repo (the old folder can be deleted), and re-register the MCP server once with
`provenlens install claude-user` if `~/.claude.json` still names `codelens`.

---

## [2.8.1] — 2026-09-02

### Security

- **Vendored `mermaid` 10.9.1 → 10.9.8.** 10.9.1 carries GHSA-m4gq-x24j-jpmf (high — prototype
  pollution in the DOMPurify it bundles) plus a moderate. Every generated report embeds this
  library and renders diagrams built from scanned-repo and ticket text, which is exactly the
  untrusted input the advisory is about. `securityLevel: 'strict'` was already set and does not
  cover it. 10.9.8 audits clean; the bundle was taken from cdnjs and the hash confirmed
  byte-identical against the npm tarball (`8d607d7e…6675d`). The pin moves in `SHA256SUMS`,
  `vendor/README.md`, `scripts/fetch-vendor.sh` and the CDN fallback URL in `html-builder.js`
  together, which is the signal a reviewer looks for.
- **`git-guard` now fails closed without `jq`.** It reads the command as JSON through `jq`; with
  `jq` absent the parse came back empty, an empty command meant "not git", and the hook exited 0.
  A machine that merely lacked `jq` had **no guard at all**, silently, for every push. Confirmed
  with a PATH hiding only `jq`: a push to a non-whitelisted remote was allowed. It now denies
  every command with a message naming the fix. The test suite gained the case — and the first
  version of that test was itself wrong, because `bash` is also looked up on the shimmed PATH and
  "bash: not found" produces the same empty stdout as a fail-open guard. It names bash absolutely.

### Changed

- `jq` is listed as a prerequisite in README, with the fail-closed behaviour stated; SECURITY.md
  documents the fail mode.

---

## [2.8.0] — 2026-08-25

### Added — codelens reaches the places 2.7.0 missed

2.7.0 put the block in 25 skills and stopped there. An audit of the whole surface — every
codelens command against every file that could reference it — found the integration was
shallower than it looked in three ways.

**The shared files knew nothing about it.** Two resources are bundled into many skills at once,
and both had zero mentions, so the methodology said one thing and the checklist another:

- **`resources/review-skills-universal.md`** (495 lines, bundled into 6 skills) now opens with
  **§0 — EVIDENCE**: a table of which command settles which claim, the staleness rule, and the
  instruction to mark a degraded finding `grep-depth`. Every later section that makes a reach
  claim points back at it — layering in §1, N+1 in §4, "untested" in §6, dead code in §9. A
  review is only worth the evidence under it, and most of that checklist is claims about reach.
- **`resources/kb-steps.md`** (bundled into `scan` and `rescan`) gains golden rule **8**:
  structural claims come from the graph where one exists, and **the graph is an input, never the
  output** — a fan-in number is not a business meaning, and the meaning is what a KB is for.
  `_meta.yml` now records the resolution figure, so a reader can tell a KB built on a resolved
  graph from one built on grep. §06 orders its deep-dive by real hubs; §16 prefers invariants that
  a command can actually check.

**Two skills were excluded that should not have been.** `discover` already asks *"which existing
flow does this touch?"* and `qa-integration` has to choose its own regression set when no plan
exists. Both are reach questions, and answering either from intuition is the thing the block
exists to stop. **27 of 30** now, and the opt-out list in `tests/consistency.test.sh` records why
the remaining three are genuinely out rather than merely unvisited.

**Staleness was missing from the contract.** The shared paragraph said to confirm with `codelens
status` but never said to `sync`. An index built before the last three commits answers confidently
and wrongly, which is the worst failure mode this integration has. All 27 blocks now carry it,
along with `codelens doctor` — low coverage from an uninstalled dependency and low coverage from a
resolver limit look identical in the number and are nothing alike in the fix.

### Added — the commands nothing was using

`node`, `callees` and `query` were referenced nowhere. They are now where they earn their place:
`node` in `/namht-ask` for a question about one named thing, `callees` in `/namht-document` for
mapping a business step to the functions a flow really calls, `query` in `/namht-simplify` because
duplication hides under different names. Every codelens command is now referenced by something
except `mcp`, which is the server's own stdio entry point and is invoked by the client config, not
by a skill.

### Added — the docs a new user actually reads

Both setup guides gained a codelens section (what changes with an index, the four-command install,
the offline and gitignore notes). `docs/skills-catalog.html` says 27 of the 30 use it and what the
fallback label means. `/namht-help` reports whether the current repo has an index — and is told
**not** to run `codelens init` itself, since that walks the whole tree and is the user's decision.
The VS Code panel's README says the same.

### Fixed

- README claimed 25 skills; it is 27.

---

## [2.7.0] — 2026-08-25

### Added — codelens, as an optional call-graph dependency

The kit could describe what a system *means* (the Knowledge Base) but had to **grep** for what it
*does*. Grep finds a string; an impact analysis needs a call. Every skill that reasoned about
who-calls-what was therefore working one level below its own claims — and never said so.

[`codelens`](https://github.com/NamHT4Devlop/codelens) is now wired in as an **optional** dependency.
Nothing requires it and nothing breaks without it:

- **`docs/codelens.md`** — the playbook: what it covers (Java · Ruby · TS/JS **only**), the two ways
  a skill reaches it (read-only MCP tools vs the CLI), the commands by the question they answer, and
  the five-point contract every integrated skill follows.
- **25 of the 30 skills** carry a `### codelens (optional)` block: the same paragraph verbatim, then
  the specific commands that skill uses. The shared paragraph includes the fallback sentence, so a
  skill that degrades to grep now writes `⚠️ grep-depth only (no codelens index)` in its output
  instead of presenting a grep hit as a resolved call.
- **The five that opt out** — `discover`, `issues`, `pdf`, `qa-integration`, `splunk-report` — never
  reason about a call graph. They are listed in `tests/consistency.test.sh` with a reason, not
  silently skipped.
- **`/namht-build`'s approval gate is now counted from the graph.** The **>3 callers** trigger
  reads `codelens callers --json`; a grep hit count and a caller count are different numbers and
  only one of them is the blast radius. Step 3.5's safety net gained
  `affected --fail-if-untested`, whose exit code 2 (production code changed, no test reaches it) is
  treated as a blocker.
- **`/namht-map` is hybrid, not replaced** — and the choice is made in code, not left to the
  model. New `skills/namht-map/references/codelens-graph.cjs` turns `codelens export` into the
  viewer's own node/edge shape; `build-map.cjs` tries it first and falls back to the regex analyzer,
  printing why. The viewer's meta bar now reads `codelens (resolved call graph)` or
  `static import/inheritance scan`, because those edges are not worth the same. On the bindings
  fixture the resolved graph carries **27 edges against the regex scan's 8**, including the
  cross-language SQS hop. Languages codelens cannot cover (Python, Go, C#, PHP, Rust, Kotlin,
  Scala, Swift, C/C++) are detected on disk and named, so a dropped service is admitted rather than
  silently missing. `CODELENS=0` forces the regex path for a side-by-side.
- **`/namht-system-map` cross-service edges can be *confirmed*.** A producer and a consumer sharing
  a queue name or an endpoint URI are joined across repos and languages, so an edge no longer rests
  on KB prose alone.
- **The seven sub-agents can reach it** — `tools:` now lists the read-only
  `mcp__codelens__codelens_*` tools. Deliberately **not** `Bash`: handing a review specialist a
  shell to reach `codelens dead` would trade a read-only guarantee for one command. The parent skill
  runs the CLI-only commands and passes the result into the prompt instead.

### Changed

- `scripts/onboard-project.sh` adds **`.codelens/`** to the target project's `.gitignore` (a
  rebuildable index describing the whole codebase — it must never reach a team repo) and reports
  whether the repo is indexed. It never indexes on its own; that walks the tree and is the user's call.
- `/namht-drift` referenced `.codegraph/` and `codegraph_explore`, which no longer exist under those
  names. Renamed to `.codelens/` and `codelens explore`.
- `docs/skill-anatomy.md` gained the block as part of the written standard, plus an
  **Honest about depth** rule. `/namht-skillify` now scaffolds it, and requires a new skill to be in
  the block list or the opt-out list — there is no third option.

### Tests

- `tests/smoke.test.sh` covers the new adapter: a graph must name its source, `buildFromCodelens`
  must report *why* it declined rather than throw, and a language it cannot cover must be named.
- `tests/consistency.test.sh` gained a guard: every skill is in exactly one of the two lists, the
  block keeps its fallback sentence and its skill-specific commands, `docs/codelens.md` exists, the
  three fan-out agents can actually reach codelens, and **no** agent grants `Bash`. A skill in
  neither list fails the suite — which is what stops the standard from ending at the last one written.

---

## [2.6.1] — 2026-08-13

### Documentation

Propagated the 2.6.0 Knowledge-Base changes into everything that describes them — the skills were
updated but the docs still described the old behaviour:

- **README gained a Knowledge Base section**, which it never had: the full file tree, which two
  documents carry most of the value, the depth table, and a subsection for business-heavy repos
  covering stable rule ids, the enforced/tested columns, the removed flow cap and the business-layer
  sampling exemption. Plus the two checks worth doing right after a first scan — how many rules show
  `NONE` in the test column, and what `_coverage-report.md` says was deferred.
- `/namht-scan` and `/namht-rescan` command stubs now state the id convention and the depth advice
  rather than only naming the flag.
- The personal and company setup guides get a `deep` row aimed at business-heavy services; the skills
  catalog's scan/rescan descriptions no longer understate what they now guarantee.

### Fixed

- **`17-async-events.md` was produced by `/namht-scan` and referenced by `rescan`, `system-map`,
  `qa` and `build` — but never defined in `kb-steps.md`,** the file that is supposed to specify
  every KB section. It is documented now, including the instruction to record channel field names
  verbatim (a producer sending `order_id` to a consumer reading `orderId` is invisible until the two
  catalogs sit side by side). `consistency.test.sh` now fails if a section the skills reference is
  missing from the spec.

---

## [2.6.0] — 2026-08-13

### Fixed — the KB was not deep enough for a business-heavy repo

Three defects found by reading `kb-steps.md` against the skills that consume it:

- **Rule ids were cited but never created.** `/namht-build`, `/namht-qa` and `/namht-review` all cite
  business rules by id (`BR-V2`, `core-flow #3`) to tie a regression test or a review finding to the
  rule it protects — but `kb-steps.md` never told `/namht-scan` to assign ids at all. That
  traceability rested on a convention nothing produced. Section 13 now mandates `BR-<AREA><n>`
  (Validation · State · Calculation · Access · Time · Invariant) and core flows get `CF-01`…, with an
  **append-only** rule: never renumber, never reuse a retired id, mark a dead rule `[REMOVED <date>]`
  instead of deleting it. Ids are cited from test names, evidence reports and journals that a rescan
  cannot see, so renumbering silently repoints all of them. `/namht-rescan` carries the same rule.
- **Core flows were capped at seven.** `10-core-flows.md` said "min 3, max 7" — a hard ceiling on
  exactly the repos that need the document most, which drops real flows with no trace. The cap is
  gone: document every flow a stakeholder would name; past ~8, keep the cross-cutting ones in
  `10-core-flows.md` and push module-local ones into `modules/<m>.md` with an index line. Splitting is
  fine, dropping is not — anything deferred for cost is **listed by name** in `_coverage-report.md`.
- **`standard` depth sampled the business layer.** Sampling kicked in for any layer over ~40 files,
  including domain/service/use-case code, state machines, validators and calculation logic — the exact
  content the rest of the kit is built to protect. The business layer is now **never sampled at any
  depth**; controllers and DTOs are sampled instead, where the loss is cosmetic.

### Changed

- Per-module docs (`modules/<m>.md`) are written whenever a repo has more than ~3 modules, and always
  for a business-heavy one — previously "for larger projects", which left it to feel.
- Each business rule is now one row carrying **where it is enforced** (`file:line`) and **how it is
  tested** (test name, or `NONE`). A `NONE` is a finding, not a blank: those roll up into the
  Under-Enforced section, which is the highest-value output the document has.
- `tests/consistency.test.sh` fails if `kb-steps.md` stops mandating the ids that other skills cite —
  the citations would otherwise become dangling with nothing noticing.

---

## [2.5.1] — 2026-08-13

### Documentation

The docs were describing the kit as it was two releases ago. Corrected against the code, not from
memory:

- **`SECURITY.md` described guard behaviour that was, in fact, the bug.** It claimed a push target
  was resolved from "a leading `cd`" — the v2.4.0 audit found it was scraped from the *whole*
  command, which is what let a trailing `cd` launder a push to a team remote. The section now states
  the real resolution order, lists the five closed bypasses in a table, records the accepted
  quoting limitation, and cites the current **97** guard cases.
- **`SECURITY.md` never mentioned six scripts that write outside the repo** — `personal-install.sh`
  (deletes symlinks under `~/.claude`), `onboard-project.sh` (writes into other repos),
  `schedule.sh` (your crontab), `kb-export.sh` / `kb-import.sh` (move Knowledge Bases),
  `migrate-sessions.sh`. A new section names each one, what stops it going wrong, and the test count
  behind that claim.
- **The extension's read-only guarantee was understated.** The README described it as hiding and
  refusing the seven code-editing skills; since v2.4.0 the host also refuses free chat and
  **follow-ups**, which were the two paths that actually reached an edit.
- **`README.md` gained a Tests section.** The suite is the reason to trust a kit that edits your
  code and your crontab, and it was not documented anywhere — including the principle behind it: a
  script that touches something outside this repo does not ship without a test, because its failures
  are silent.
- Skill catalog notes the trailer the ten high-stakes skills now carry.

Every number quoted in these docs was re-derived by running the suites, not copied forward.

---

## [2.5.0] — 2026-08-13

### Added

Three techniques adapted from [addyosmani/agent-skills](https://github.com/addyosmani/agent-skills),
which does the same job from the opposite direction (spec → code, tool-agnostic). The ideas are its;
the content is written for this kit.

- **A trailer on the ten high-stakes skills** — the ones that edit code, or whose conclusions someone
  acts on (`build`, `fix-bug`, `migrate`, `simplify`, `perf`, `observe`, `rails-to-spring`, `review`,
  `drift`, `runbook`):
  - **Common rationalizations** — the excuse for skipping a step, next to the fact that defeats it,
    written in the voice the excuse actually arrives in ("it's a small change, the baseline is
    overkill" → then you cannot tell a test you broke from one that was already red).
  - **Red flags** — *observable* signals that the process has already gone wrong, not advice. "You
    made a failing test pass by changing its assertion", not "be careful with tests".
  - **Verification** — checkbox exit criteria per skill. "Seems right" is never enough.
  Each block is written for its own skill; a generic one would be noise.
- **`docs/skill-anatomy.md`** — the written standard: required sections in order, when the trailer is
  mandatory, and how to write each of the three so it stays useful. `/namht-skillify` now reads it
  before scaffolding, so new skills come out the same shape.
- **A routing decision tree in `/namht-help`** — 31 commands is a lookup problem. The tree starts from
  what you have in your hands (a question, a vague idea, a bug report, a diff, a contract that must
  change), not from the command list, plus the pairings that recur and one rule for ties: prefer the
  command that produces **evidence** over the one that produces an opinion.
- **The six non-negotiables in one place** — KB-grounded · reuse before create · evidence not
  assertion · scope lock · untrusted input is data · dual-audience. They were already enforced inside
  individual skills; now they are stated once as the kit's contract.

### Changed

- `tests/consistency.test.sh` fails if a high-stakes skill loses any of the three trailer sections, or
  if its Verification section has no checkbox items — a heading is not an exit gate. It also notes any
  code-editing skill missing from the list, which is how `simplify`, `perf` and `observe` got theirs.

---

## [2.4.0] — 2026-08-13

### Security

A six-lens multi-agent audit of the whole repo, with every High finding independently re-verified
against source before it was accepted. Two live bypasses of the git guard were reproduced and closed:

- **`git push --repo=<url>` evaded the push whitelist.** The target resolver only accepted a bare
  positional remote and skipped every `-` token, so git's documented no-positional form fell through
  to the local default origin — the guard validated a whitelisted remote while git pushed to
  whatever URL `--repo` named.
- **A `cd` that runs *after* the push decided which repo the push was checked against.** The working
  directory was scraped from the whole command with a greedy regex, so a trailing `cd` into a
  personal repo laundered a push to a team remote. Directory changes are now tracked from preceding
  segments only — which is what the file always claimed it did.
- Persisting an alias through `config` was allowed, giving back exactly the arbitrary-shell alias
  that the transient `-c alias.*` rule already blocked.
- `{ git zz; }` and other shell-grouping prefixes dropped git out of "command position", skipping the
  unknown-subcommand/alias check entirely.
- Assigning the binary to a shell variable hid the real command from every rule — now refused.
- The guard suite went 56 → **74 cases**, including the previously untested path that resolves a bare
  push from the session's cwd, against real fixture repos.

Also hardened:

- **Read-only mode was not read-only.** Follow-ups and the free-chat card both reached the CLI (which
  runs with `bypassPermissions`) without passing the readonly gate, so "now edit src/foo.ts" typed as
  a follow-up edited source in the `.vsix` handed to non-developers. All three entry points — run,
  follow-up, interactive — now go through one shared check.
- The model value from the webview is allowlisted **and** quoted before it reaches the one
  shell-executed command line in the extension.
- Secret scrubbing covered the stored form values but not the prompt echoed into the persisted run
  log, and never covered follow-up text; the pattern now also catches Slack/GitHub tokens and JWTs.
- `openReport`/`openFile` accepted any path from the webview; they are confined to the workspace.
- `cancel()` posted its own terminal event and dropped the busy-guard before the child exited,
  allowing a duplicate `done` and a follow-up racing the dying process.
- Mermaid fenced blocks were "sanitised" with a regex tag-stripper that misses unterminated tags;
  they are HTML-escaped now. `esc()` also escapes the single quote, and two unescaped graph-panel
  interpolations were closed.
- `fetch-vendor.sh` installed a downloaded library with **no** verification when it had no pinned
  hash — contradicting its own documented promise — and swallowed the final verification error.

### Fixed

- **`/namht-pdf` was broken on Linux.** `mktemp -d -t namht-pdf` is BSD-only; GNU coreutils rejects a
  `-t` template without X's, so under `set -e` the script died before trying any PDF engine. Only
  testing on macOS hid it.
- **`schedule.sh` could silently delete another repo's cron job.** Its marker tag was matched as an
  unanchored substring, so `/x/api` also matched the line for `/x/api-v2`. Percent signs are escaped
  now too — cron reads a bare `%` as a newline and truncates the command.
- **`kb-export.sh` silently overwrote a snapshot from a different repo** with the same folder name
  (`clientA/api` vs `clientB/api`); it now refuses and names both paths.
- Four skills (`pr`, `plan-review`, `retro`, `issues`) shipped the HTML renderer but never invoked
  it, so the panel's **📄 Report** button had nothing to open.
- Docs drift: skillify's checklist omitted `i18n.js` (its own verify step then failed), the extension
  README still described localisation as a manual edit, `--create` was undocumented in the issues
  skill and help table, `namht-runbook` never defined `$SKILL_DIR`, and the changelog was missing its
  `[2.2.0]` entry and the extension versions.

### Added

- **Tests for the three scripts that touch things outside the repo**: `schedule.sh` (20 cases, via a
  PATH-stubbed `crontab` — the real one is never touched), `personal-install.sh` (10 cases; `DEST` is
  now overridable with `NAMHT_CLAUDE_DIR`, so the one script that *deletes* from `~/.claude` is
  finally testable, including that a foreign symlink survives an uninstall), and kb-site's
  single-repo, refusal and hostile-`_meta.yml` paths.
- `tests/run.sh` and CI now `node --check` the webview scripts — `tsc` only ever parsed `src/`, so a
  syntax error in `media/main.js` shipped a blank panel with a green build.

---

## [2.3.0] — 2026-08-13

### Added

- **`scripts/kb-site.cjs` — the hub as one browsable page.** A hub was a folder of Markdown that
  nobody opens; twelve projects times twenty documents is 240 files. This renders all of them into a
  single self-contained `index.html`: project rail with freshness badges, a tab per document, Mermaid
  drawn, and search across every document in every project. Zero network calls, opens with a
  double-click, works on a single repo's `knowledge-base/` too. `kb-export.sh` builds it
  automatically at the end of an export.
- Diagrams in that page are framed panels with an **⤢ Expand** overlay, and the Mermaid palette is
  pinned to the page (its own dark theme assumes a mid-grey background and turns clusters flat grey
  and nodes near-black on `#0f1420`).
- **The hub is readable, not just a distribution point.** `/namht-system-map` and `/namht-ask`
  detect the `projects/*/knowledge-base/` layout and work straight from a hub — the cross-service map
  and cross-project questions without cloning any repo. Both must state the limits: no source to
  verify against, and every project is a snapshot at the commit in its `_meta.yml`.

### Changed

- The folder name stays `knowledge-base/` on purpose — renaming it per project would break existing
  KBs, the machine-wide ignore and every skill's lookup path at once. Identity lives *inside* the
  KB, and the namespace is applied at collection time.

---

## [2.2.0] — 2026-08-13

### Added

- **`/namht-runbook`** — the KB explains how a system works; this writes the other document, the one
  read while something is on fire. Health checks, deploy and rollback (including **what a rollback
  does not undo** — migrations, consumed messages, sent mail), one playbook per failure the system
  can genuinely have (Symptom → Confirm → Contain → Diagnose → Fix → Verify → Escalate), alerts →
  action, and data recovery. Grounded in the KB **and** the repo's real CI/deploy config and error
  handling, with file citations. Anything only a human knows — owners, on-call, SLAs — is left as an
  explicit `❓` rather than invented, because a fabricated escalation path is worse than none. It
  writes the document and never operates anything.
- **KB identity (`knowledge-base/_meta.yml`)** — every scan/rescan now stamps the KB with project,
  repo, branch, **commit**, date, depth and modules. The folder is called `knowledge-base/` in every
  repo, which is fine inside one repo and useless once several sit side by side; `rescan` refreshes
  the commit so a stale KB stops passing as current.
- **`scripts/kb-export.sh` / `scripts/kb-import.sh`** — collect the KBs of many repos into one hub
  repo under `projects/<project>/`, with an index table, then drop one into a teammate's checkout.
  Snapshots, not mirrors. Export refuses to write into a repo it can see is **public** (a KB is a
  readable distillation of your source) and never commits or pushes; import refuses to overwrite an
  existing KB without `--force`, keeps a timestamped backup when it does, and warns when the
  snapshot's commit is not in that checkout.
- VS Code extension **v0.16.0**.

---

## [2.1.0] — 2026-08-13

### Added

- **`/namht-issues`** — the last manual step in the chain: a plan or set of user stories becomes
  real tracker issues (GitHub via `gh`, Jira/Linear via a connected MCP). One issue per story with
  its acceptance criteria as a checklist, parents linked to children, and the story ids kept
  verbatim so a **second run updates instead of duplicating**. Preview-by-default — it writes a file
  and shows every issue before anything exists; creating requires an explicit yes, and it never
  closes or deletes an issue.
- **Running spend total in the extension** — the per-run cost chip never added up to a number you
  could act on. The panel now shows `this session · today (n runs) · 7d`, kept per day on the
  machine for 60 days. On a Team/Enterprise seat this is usage value, not a charge.
- **Vietnamese UI** — `namhtSpecUi.language: en | vi` translates the panel's own labels, cards and
  buttons (not what Claude writes back). Untranslated strings fall through to English rather than
  breaking, and `tests/i18n.test.cjs` fails if a card is reworded and leaves its translation
  stranded, or if a new card ships untranslated.
- **`scripts/schedule.sh`** — cron helper for the two genuinely periodic skills plus drift:
  `add rescan|drift|splunk <cron> <repo>`, `list`, `remove`. It only ever touches its own tagged
  lines, always shows the change and asks before writing, and **refuses to schedule a skill that
  edits code** — unattended source edits should not be settable by accident.

### Changed

- The extension's form fields support a checkbox type (used by `--fix-docs` and by `--create`).
- `/namht-skillify`'s registration checklist now names all eight places a skill must appear,
  matching what the consistency test enforces.
- VS Code extension **v0.15.0**.

---

## [2.0.0] — 2026-08-12

### ⚠️ Breaking

- **`spec-kit-sessions/` is now `namht-sessions/`.** The old name collided with GitHub's unrelated
  [`github/spec-kit`](https://github.com/github/spec-kit), which is confusing now that this repo is
  public. The product name dropped "Spec Kit" too — it is **namht Kit**.
  **What you have to do:** nothing urgent. Every skill that reads past work (`ask`, `build`,
  `fix-bug`, `retro`, `rails-to-spring`) falls back to a legacy `spec-kit-sessions/` folder, and the
  extension's report detector matches both names. When convenient, merge the old folder in:
  ```bash
  scripts/migrate-sessions.sh --dry-run <repo>   # look first
  scripts/migrate-sessions.sh <repo>             # then do it
  ```
  Add the new name to your machine-wide ignore (keep the old one while legacy folders exist):
  ```bash
  printf '%s\n' 'namht-sessions/' 'spec-kit-sessions/' >> ~/.gitignore_global
  ```

### Added

- **`/namht-drift`** — the missing whole-picture check. Every other command works one change at a
  time; nothing verified that the documents still describe the software. It audits the repo and
  reports four kinds of drift: stale KB entries (D1), undocumented behavior (D2), acceptance
  criteria promised in `namht-sessions/` but never shipped (D3), and broken architecture invariants
  (D4). Each finding cites `file:line` on one side and the document line on the other and states
  which side is wrong. Ends with a verdict (`CONVERGED` / `DRIFTING` / `STALE`) and a journal row so
  successive runs show the trend.
- **`/namht-drift --fix-docs`** — opt-in mode that closes the documentation half only: D1/D2
  findings where the audit concluded the *document* was wrong, after showing you the exact
  `knowledge-base/` files and taking one explicit yes, with a backup to
  `namht-sessions/drift/<date>-kb-backup/` first (that folder is gitignored, so git is not an undo
  here). Never edits source, never writes an unbuilt AC into the docs as if shipped, never relaxes
  an invariant to match the code.
- `scripts/migrate-sessions.sh` — safe rename/merge for the folder change above. Never overwrites,
  supports `--dry-run`, and leaves anything it could not merge in place.
- VS Code extension **v0.14.0**: a `drift` card, and form fields now support a checkbox type (used
  for the `--fix-docs` toggle).

### Fixed

- `scripts/onboard-project.sh` wrote a stale `/spec-kit:*` command namespace into the project
  CLAUDE.md — the correct namespace is `/namht:*`.

---

## [1.4.0] — 2026-08-10

### Added

- **Resumable ports** — `namht-rails-to-spring` keeps `namht-sessions/port/_progress.md` and
  continues from it; a port spanning weeks no longer restarts each session.
- **Journals as cross-session memory** — `build` and `fix-bug` now write `builds/_journal.md` and
  `fixes/_journal.md` alongside the existing `answers/_journal.md`, and `retro` reads all three.
- **`/namht-scan` depth knob** — `quick` / `standard` / `deep`; proposes `quick` above ~1500 files.
- **Read-only mode for the extension** (`namhtSpecUi.mode: readonly`) — the seven code-editing
  skills are hidden *and refused by the host*, so a PM/SM build cannot change source even if the
  command is sent by hand.
- `scripts/fetch-vendor.sh` — fetch the render libraries on demand (npm first, so a corporate
  registry is respected; cdnjs fallback) and verify them against `vendor/SHA256SUMS`, instead of
  copying 3.6 MB between machines.

### Changed

- **PDF export is dark by default** (`#0f1420`) end to end, with `PDF_KEEP_COLORS=1` to preserve a
  source document's own colours and `PDF_LIGHT=1` for a light page.

### Fixed

- Diagram labels, links and images were unreadable in dark exports — Mermaid bakes colours into the
  SVG at render time, so the theme now matches from the start instead of being inverted at print.
- Light panels from source HTML no longer leave white patches on the dark page.
- Off-screen images no longer fail to render during headless print (`loading="lazy"` removed), and
  relative image paths resolve from a `<base href>` injected into the temp copy.

---

## [1.3.0] — 2026-08-09

### Security

Reproduced and closed real bugs, each with a regression test:

- **git-guard alias RCE** — `git -c alias.zz='!echo PWNED' zz` ran arbitrary shell and bypassed the
  guard entirely. `-c` / `--config-env` values naming `alias.*` are now denied, alongside a
  subcommand allowlist, `--git-dir`/`--work-tree` redirection, `GIT_*=` env prefixes, and credential
  redaction in reported URLs. The suite grew from 26 to **56 cases**.
- **XSS in the dependency-map viewer** — a `</script>` sequence inside a scanned repo's comment
  broke out of the embedded JSON block and injected HTML at `file://`. Graph data is now escaped and
  the viewer ships a CSP.
- **Untrusted input is data, not instructions** — `build`, `user-story`, `fix-bug`, `splunk-report`,
  `pr`, `review`, `qa-integration`, `design-review` and `scan` now treat Slack threads, tickets,
  logs and page content as data. Acceptance criteria that originated outside the user need one
  explicit yes before they reach code.
- **PII redaction** in `splunk-report` — the one skill that touches real customer data now reports
  error type, signature and count rather than raw payloads.
- Extension config (`claudePath`, `extraArgs`, `mode`) is **machine-scoped**, so a repo's
  `.vscode/settings.json` cannot change which binary runs or how; URL-shaped form values are
  redacted before history is persisted.

### Added

- **`namht-build` safety net** — before the first edit: a clean-tree check, a recorded baseline of
  the gates (including already-failing tests), and a pre-change patch, with an explicit revert route
  that the git-guard permits.
- Objective plan-approval triggers (migration · dependency · published contract · >3 callers ·
  >5 files · Medium/Complex · auth/money) replacing "trivial by feel", and a rule that a blanket
  "go" authorizes reversible work only.
- **Reuse before you create** is now a hard rule across `build`, `fix-bug` and `rails-to-spring`,
  extended to the things that get duplicated most: constants, enums, config keys, error codes,
  messages, i18n keys, style tokens and test fixtures.
- Step 5 review lenses run as **fresh sub-agents that did not write the code**.

---

## [1.2.0] — 2026-07-20

### Added

- **`/namht-user-story`** — deep investigation of a requirement, or comprehension of a Slack thread,
  into INVEST stories with maximally granular Given/When/Then acceptance criteria.
- **`/namht-rails-to-spring`** (renamed from `namht-port`) — contract-first, parity-verified stack
  port with a bundled shadow-test harness and an independent parity reviewer.
- **Q&A journal** — `/namht-ask` writes one line per answered question, so a new session remembers
  what was asked before, with a staleness check before reusing an old conclusion.
- Branch confirmation in `scan` / `rescan` — it now says which git branch it is reading.
- VS Code extension **v0.13.0**: app-window layout, chat bubbles, per-run model picker that survives
  switching models mid-session (`--resume` keeps the context), free "Ask anything" chat, step
  timeline and per-file diffs, squirrel icon, Yarn, `UNLICENSED`.

---

## [1.1.0] — 2026-07-08

### Added

- `docs/skills-catalog.html` — the skill catalog as a table (name · intended user · description)
  with an edits-code vs read-only badge per skill.
- Setup guides for a personal machine, a company machine, and a no-clone manual install.

---

## [1.0.0] — 2026-06-27

Initial release: a native Claude Code port of the author's private Auto Spec VS Code extension
(which ran on GitHub Copilot). Knowledge Base generation, the spec-driven build pipeline, two-phase
review, grounded Q&A, planning, dependency maps, business↔code docs — plus the read/sync-in-only
git guard hook.
