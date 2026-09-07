# namht Kit UI — VS Code extension (for PM / SM)

A **point-and-click** panel over the `namht-*` skills, so non-technical roles
(Product Managers, Scrum Masters) can use them **without typing slash commands or opening a terminal**.
It runs the **Claude Code CLI** under the hood — no API key of its own.

**Two ways to view it:**
- **Sidebar** — click the **namht Kit** icon in the Activity Bar (compact, single column).
- **App window** — click the **⧉ Open namht Kit App** button in the sidebar's title bar (or run
  *"Open namht Kit App"* from the Command Palette). It opens a wide, app-like layout in the editor
  area: a **left nav rail** (Home + categories + recent/running + status) beside a roomy content
  area with a hero and skill cards. Both stay in sync — a run started in one shows in the other.

## What it exposes (all 30 skills, categorized)
- **General:** **ask anything** — a plain question on any topic, not tied to the repo (runs Claude with no skill)
- **Understand:** scan · rescan · ask · map · system-map · document
- **Plan:** discover · plan · plan-review · **user-story** (requirement or a Slack thread → INVEST stories) · **issues** (stories → GitHub/Jira tickets)
- **Build & Fix:** build · fix-bug · migrate · simplify · perf · observe · **rails-to-spring** (contract-first stack port)
- **Review & QA:** review · qa · qa-integration · security-audit · design-review · pr · **drift** (docs vs reality audit — optional checkbox refreshes the stale docs)
- **Ops & Docs:** splunk-report · retro · pdf · skillify · **runbook** (on-call operational guide)

Search to filter, click a card, fill the form, **Run** (or just press **Enter** — Shift+Enter makes a
new line; Enter never fires mid-word while typing with an IME). Output renders as styled Markdown (headings,
tables, code); a **"📄 Report"** button opens the skill's saved HTML (with Mermaid drawn).

> Skills that **change code** (build, fix-bug, migrate, simplify, perf, observe, rails-to-spring) are marked
> **"edits code"**. Two ways to run them:
> - **▶ Run** — headless auto-approve. The run view shows a **Step timeline** and a **Files changed**
>   panel: click a file to open it, or expand **diff** to see the exact old→new lines it wrote.
>   Review the final diff in Source Control too; the git-guard hook still blocks dangerous git.
> - **⚡ Interactive (approve each edit)** — opens a terminal running `claude` interactively, so a
>   developer **reviews each diff and approves / rejects / redoes** it (the official-panel experience),
>   nothing written without an OK. Runs outside the panel (no cost chip there).

## Prerequisites
1. **Claude Code CLI** installed and signed in (`claude --version` works). The extension shells out to it.
2. The **`namht-*` skills installed** on the machine (`scripts/personal-install.sh` from this repo →
   symlinked into `~/.claude`). The CLI picks them up automatically.
3. **Open the target project folder** in VS Code — skills read *that* project's `knowledge-base/`.

## Run it (development)
Uses **Yarn** (see `packageManager` in `package.json`).
```bash
cd vscode-extension
yarn install
yarn compile
```
Then open this `vscode-extension/` folder in VS Code and press **F5** (Run → Start Debugging). A second
VS Code window opens with the extension loaded — click the **namht Kit** icon in the Activity Bar.

## Package + install (share with PM/SM)
```bash
yarn compile
npx @vscode/vsce package        # produces namht-spec-ui-<version>.vsix (vsce auto-detects yarn.lock)
```
Send the `.vsix`; each person installs via **Extensions ▸ … ▸ Install from VSIX**. (They still need the
Claude Code CLI + the skills installed on their machine.)

## How it works
```
webview (cards + form)  --run{command,args}-->  extension host
                                                   └─ spawn: claude -p "/<command> <args>"  (cwd = project)
                                                   └─ stream stdout back to the webview
                                                   └─ detect the saved namht-sessions report → "Open report"
```
- **Only whitelisted commands run** — the host rejects anything not in `ALLOWED` (see `src/extension.ts`).
- The **git-guard hook** still applies (PreToolUse runs before the permission check). Note that the
  default `bypassPermissions` mode skips Claude Code's own approval prompts - see `namhtSpecUi.extraArgs`.

## Cost & tokens
Each run shows a **cost chip** — the tokens used (`input→output`, plus **`… cached`** = KB context
re-read from cache, which is the usual reason the number looks big) and the **API-equivalent cost in
USD** for that run (summed across follow-ups), read straight from Claude's `result` event (`usage` +
`total_cost_usd`). It also shows an approx **₫** figure by default (rate `namhtSpecUi.usdToVnd`,
default 26000 — adjust to your rate, or set 0 to hide VND). Note: on a **Team/Enterprise seat you are
not billed per token** — the number reflects usage value, not a charge.

## Pick a model per run (cost lever)
Every form has a **Model** dropdown (pre-set to `namhtSpecUi.model`) — choose **Haiku** for a cheap
lookup, **Sonnet** for balanced Q&A/planning, **Opus** for the hardest code. Each run view shows a
**⚙ model chip**, and the **follow-up box has its own model dropdown**: you can switch model mid-session
(e.g. plan on Sonnet, then a cheap Haiku follow-up) and **the session keeps its full context** — the
extension resumes the same Claude session (`--resume`), so the new model still knows what it was doing.

## Running total (what has this cost me?)
Besides the per-run cost chip, the panel shows a **running total** — `this session · today (n runs) ·
7d` — kept per day on this machine for 60 days (`namhtSpecUi.usdToVnd` adds the ₫ figure). It counts
only runs started from this panel. On a **Team/Enterprise seat you are not billed per token**, so
read it as usage value rather than a bill.

## Vietnamese UI
Set `namhtSpecUi.language` to `vi` and the panel's own labels, cards and buttons are in Vietnamese.
It does **not** change the language Claude answers in — that comes from the skill and from how the
request is written. A string with no translation falls back to English, and `tests/i18n.test.cjs`
fails the build if a card is reworded and leaves its translation stranded.

## Settings
- `namhtSpecUi.claudePath` — path to the `claude` CLI (default `claude`). **Machine-scoped**: a repo's
  `.vscode/settings.json` cannot change which binary this extension launches.
- `namhtSpecUi.extraArgs` — extra args for `claude -p` (**machine-scoped**, same reason). Default
  `--permission-mode bypassPermissions` so skills can run the tools they need headlessly (`node` for
  the map/PDF, `npm`/`npx`/`jest` for build & tests, `gh`, `curl`) — otherwise those commands surface
  as **"error"**, because a headless run can't answer an approval prompt.
  **Know the trade-off:** that mode also permits *any* Bash command, writes outside the workspace,
  reading files such as `.env`, and network calls — Anthropic recommends it only in an isolated
  environment. The git-guard hook still blocks dangerous/remote git in this mode (PreToolUse runs
  before the permission check — verified by `tests/git-guard.test.sh`), but it is **defense-in-depth,
  not a sandbox**. Prefer approval prompts? Set `--permission-mode acceptEdits` — then map/build/test
  commands fail with "error" here; use **⚡ Interactive** (a real terminal) for those.
- `namhtSpecUi.mode` — `full` (default) or `readonly`. In **readonly** the host refuses **every path
  that could reach an edit**, not just the cards: the seven code-editing skills, the free-chat
  "Ask anything" card (a raw prompt can ask for anything), and **follow-ups** (a follow-up resumes
  the same session with the same permissions, so "now edit src/foo.ts" typed after an innocent run
  used to land). Hiding the cards is a convenience; the host check is the control. Package a separate
  `.vsix` with this default flipped and hand that one out.
- `namhtSpecUi.usdToVnd` — VND rate to show next to the USD cost (0 = off; e.g. `25400`).
- `namhtSpecUi.language` — `en` (default) or `vi` for the panel's own labels. Does not affect Claude's answers.
- `namhtSpecUi.model` — model for the UI's runs (default **`sonnet`** — ~5x cheaper than Opus for
  read-only Q&A/planning; use `opus` for the hardest code tasks, `haiku` for cheap lookups, empty to inherit).

## Keeping cost down
Output tokens dominate cost (Opus output ≈ $75/1M). Tips: keep the default **`sonnet`** model for
Q&A/planning; ask **specific** questions (shorter answers); keep the KB lean; use `haiku` for simple lookups.

## Extend it
Add an action in `media/main.js` (`ACTIONS`) **and** add its command to `ALLOWED` in `src/extension.ts`.

## Localization
Set `namhtSpecUi.language` to `vi` — the translations live in `media/i18n.js`, keyed by the English
string, so anything untranslated falls back to English rather than breaking. Adding a card means
adding its strings there too; `tests/i18n.test.cjs` fails the build if you forget.

## Optional: `provenlens`

The skills this panel runs use a [`provenlens`](https://github.com/NamHT4Devlop/provenlens) index when the
repository has one — resolved callers and blast radius instead of grep, for Java, Ruby, TypeScript and
JavaScript. Nothing here requires it, and a skill that falls back says so in its own output
(`grep-depth only`), so a report never overstates how it knows something. Setup is in the toolkit's
`docs/provenlens.md`.
