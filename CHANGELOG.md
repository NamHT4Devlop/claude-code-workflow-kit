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
