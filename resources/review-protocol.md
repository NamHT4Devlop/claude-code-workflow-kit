# Review protocol — how a diff becomes findings someone can act on

Shared by `/cwk-review`, `/cwk-pr` and the reviewer agents. The skill says *what* to review and
how to present it; this file says how to get from a diff to findings that are true, located and
worth reading. It adapts the review pipeline of alibaba/open-code-review (Apache-2.0) and the
mistakes this kit's own scans made on real repositories.

The principle behind every step: **precision over recall.** A false finding costs more than a
missed nit, because it teaches the author to skim the review. A missed security or data bug costs
more than either, so precision never excuses skipping the files where those live.

---

## Step 0 — Account for every changed file

List every changed file and give each exactly one status before reviewing anything:

| Status | When |
|---|---|
| `review` | Source, tests, SQL, migrations, config, templates, build files, CI workflows |
| `skip: binary` | Images, archives, compiled output |
| `skip: generated` | Marked generated (a header, a `generated/` or `gen/` path, a generator's output folder such as MyBatis Generator `mbg`) and not hand-edited in this diff |
| `skip: lockfile` | `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`, `Gemfile.lock`, `poetry.lock`, `go.sum` … Review the manifest that changed it instead, and flag a lockfile change with no manifest change |
| `skip: vendored` | Third-party code copied into the repo |

Tests are reviewed. A test that asserts the wrong thing, or a deleted assertion, is a finding.

A file is never skipped for being large. Above roughly 400 changed lines, review it hunk by hunk
and say so. The review ends with every `review` file marked `done`, `partial` (and what was not
covered) or `failed` (and why). "Looks good" is only allowed when nothing is partial or failed.

## Reviewing a past commit or a range

When the target is a commit or range rather than the working tree, the diff is
`git diff <base> <head>` for that range, and every file is read at the reviewed revision
(`git show <head>:<path>`), not from the working tree. A `.provenlens/` index and a
`knowledge-base/` describe the revision they were built at: use them to find callers and rules,
but do not run `provenlens sync` (it would index the working tree, not the reviewed revision), and
check anything you take from them against the code at `<head>`. Feed `provenlens affected` the
range's file list, `git diff --name-only <base> <head>`.

## Step 1 — Group related files

Review files that only make sense together as one group: an interface and its implementation, a
controller and its service, a migration and the model it changes, a producer and its consumer, a
component and its test. Inside a group, look specifically for **broken contracts between the files**:
a signature changed on one side only, a column renamed in the migration but not in the query, a
field added to the event but not read by the consumer.

When the diff is too large to hold at once, list the other changed files by name with their
change size, and read their diffs only when a finding needs them.

## Step 2 — Plan before a large change

For a file with 50 or more changed lines, or a group with 100 or more, write a short plan first:
the risks this change could carry, ranked by severity, and for each the lookup that would confirm
or rule it out (a caller to find, a test to read, a config value to check). Do not invent risks to
fill the plan. The plan directs the first pass; it is not a limit, and anything found outside it
is reported the same way.

## Step 3 — Review, with evidence before claims

Read the diff of each file, then the context the claim needs. For anything that is not visible in
the changed lines — "this is called concurrently", "an attacker controls this", "every caller
passes X", "this breaks Y" — establish it before writing it:

- **Callers and reach:** `provenlens explore` / `callers` / `impact`, or `git diff --name-only |
  provenlens affected`, when an index exists; grep otherwise, labelled grep-depth.
- **The layer the user passes through.** A function that "only checks X" may sit behind a controller,
  page, policy or middleware that checks more, or be reachable by a path that skips them. Name the
  entry point the finding is about.
- **Library behaviour** is a claim: read the library's source for the pinned version if it is on disk,
  otherwise write `(library default, not verified)`.
- **Business rules** come from `knowledge-base/13-business-rules.md` by id when a KB exists.
- **A bound file has callers.** A MyBatis mapper XML, a route annotation, a Camel route, a queue or a
  topic name is resolved by a provenlens binding plugin, so `provenlens affected <the xml file>` names
  the service and controller methods the change reaches — a mapper change is never "just XML", and the
  endpoints it reaches belong in the finding. Read the statement and the Java method together: the
  parameters the SQL interpolates come from the caller.
- **What the index still cannot see:** tests that call by URL or route, templates, SQL built as a
  string in code, and mapper files for frameworks with no plugin. Grep for those after the provenlens
  lookup, and label them grep-depth.

Use the traps in `review-traps.md` for the file's language and framework. Do not report what the
compiler, the type checker, the formatter or the project's linters already report, unless the diff
shows a consequence they would not express.

Each finding has these fields, in this order:

```
[SEVERITY] category — one-sentence claim
Where:     path:line (the line of the quoted code, computed from the quote)
Quote:     the exact changed line(s) the finding is about, copied from the diff
Evidence:  what establishes it — the caller, the test, the rule id, the missing guard; or
           "local: visible in the quote"
Impact:    what goes wrong, for whom, and when
Confidence: confirmed | likely | needs-check (and what would settle it)
Fix:       the corrected code, complete for the lines it replaces
```

The quote anchors the finding: if the quoted text is not in that file's diff, the finding is
wrong or misfiled. Severity follows impact, not the category:

| Severity | Means |
|---|---|
| CRITICAL | Security hole, data loss or corruption, money or stock wrong, auth bypass, crash on a main path. Blocks merge |
| MAJOR | Wrong behaviour a user or operator will hit, a broken contract, a missing test for changed business logic. Blocks unless the author accepts a follow-up |
| MINOR | Real but narrow: an edge case, a misleading name that will cause a bug later, a missing log |
| NIT | Style and taste. Never inline on a PR; goes in the summary |

## Step 4 — Another round, only if the first found something

Run a second pass over the same groups with the first round's findings listed as "already
reported, do not repeat". Stop when a round adds nothing new, or after three rounds. Cap a group at
30 findings; if the cap is reached, say so rather than dropping silently.

## Step 5 — Fact-check, biased towards keeping

Before presenting, check each finding against the diff. The default is to keep it. Remove a finding
only when one of these is shown by a specific line you can point to:

- **A. Not in the diff.** The code it describes is not in the diff of the file it is filed against
  (it is about a sibling file, or code that did not change). Move it to the right file if it belongs
  there; otherwise drop it.
- **B. Contradicted.** A line in the diff plainly says the opposite: the "missing" check is there, the
  "unused" variable is used, the "hardcoded" value is read from config.

Never remove a finding whose subject is **security or authorisation, data integrity (money, stock,
balances, deletion), concurrency, null or bounds safety, or a change in behaviour or contract**
(a response field, status, default or error path the old code had and the new code does not). In
these categories a wrongly dropped finding is the expensive mistake, and confidence that "the
framework handles it" is least reliable. Keep them, with `needs-check` if unsure.

Not grounds for removal: the finding is low-value but true, it reasons about files or runtime you
cannot see, you disagree with the fix, or you cannot confirm it.

Then **re-read in the source yourself every CRITICAL and MAJOR finding** that came from a
sub-agent. A sub-agent's report is a lead.

Merge duplicates across groups and agents into one finding that lists every location.

## Step 6 — Present

1. **Verdict first**: APPROVED, APPROVED WITH FOLLOW-UPS, or NEEDS REVISION, with the one or two
   reasons that decide it, then the evidence line (index or grep-depth, and for which revision).
2. **Findings**, CRITICAL first, each in the Step 3 format.
3. **Coverage**: the Step 0 table with each file's final status, and which checklist areas had
   findings. Areas with none are listed on one line, not as a row each.
4. **Not worth fixing**: what was noticed and deliberately left out, in one list.
5. **Plan** (when Step 2 ran) and the **code graph** the evidence protocol asks for, at the end: they
   explain how the review was done and are read after the findings, not before.

Write the review in the language the user works in (their instructions or `CLAUDE.md` say which);
keep code, identifiers and quoted text as they are.

On a PR (`/cwk-pr`), inline comments are for CRITICAL, MAJOR and MINOR findings only; NITs and the
coverage go in the summary comment.

## Re-reviewing the same PR

When a previous review of this PR exists (`cwk-sessions/pr/review-<n>-*.md` records the head commit
it reviewed), review only the commits since that one, and say which earlier findings the new commits
fixed, left open, or made obsolete. Read the PR's existing review comments first (read-only) and do
not post a finding that repeats one already on the same lines.
