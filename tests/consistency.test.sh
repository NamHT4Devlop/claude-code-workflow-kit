#!/usr/bin/env bash
# Drift guards: commands/ ↔ skills/ ↔ extension ALLOWED ↔ help.md must stay in sync.
set -uo pipefail
cd "$(dirname "$0")/.."
fail=0

# Intentional exceptions:
#   help — command-only (commands/help.md is documentation; there is no skills/cwk-help/).
CMD_ONLY="help"
# Tokens that match the cwk-* shape but are NOT skills — the artifact folder every skill
# writes to. Keep this list tiny; anything else matching cwk-* must be a real skill/agent.
NON_SKILL="cwk-sessions"

echo "consistency: commands reference existing skills"
bad=0
for f in commands/*.md; do
  base=$(basename "$f" .md)
  refs=$(grep -oE 'cwk-[a-z-]+' "$f" | sort -u | grep -vxF "$NON_SKILL")
  if [ -z "$refs" ]; then echo "  ✗ $f references no cwk-* skill"; bad=1; continue; fi
  for r in $refs; do
    [ -d "skills/$r" ] && continue
    [ -f "agents/$r.md" ] && continue   # sub-agents (cwk-codebase-analyzer, …) are valid references
    short=${r#cwk-}
    # help.md lists commands, so a command-only reference is fine there
    if [ "$base" = "help" ] && [ -f "commands/$short.md" ]; then continue; fi
    echo "  ✗ $f references $r — no skills/$r/ and no agents/$r.md"; bad=1
  done
done
[ "$bad" -eq 0 ] && echo "  ✓ command → skill references OK" || fail=1

echo "consistency: every skill has a matching command"
bad=0
for d in skills/cwk-*/; do
  s=$(basename "$d"); short=${s#cwk-}
  [ -f "commands/$short.md" ] || { echo "  ✗ skills/$s/ has no commands/$short.md"; bad=1; }
done
[ "$bad" -eq 0 ] && echo "  ✓ skill → command mapping OK" || fail=1

echo "consistency: extension ALLOWED == skills/cwk-*/"
allowed=$(sed -n '/const ALLOWED = new Set(\[/,/\]);/p' vscode-extension/src/extension.ts | grep -oE "'cwk-[a-z-]+'" | tr -d "'" | sort -u)
skills_set=$(for d in skills/cwk-*/; do basename "$d"; done | sort -u)
if [ "$allowed" = "$skills_set" ]; then
  echo "  ✓ ALLOWED matches skills/"
else
  echo "  ✗ ALLOWED != skills/cwk-*/ (< only in ALLOWED, > only in skills/):"
  diff <(echo "$allowed") <(echo "$skills_set") | grep '^[<>]' | sed 's/^/    /'
  fail=1
fi

# The panel used to default to bypassPermissions, which let a prompt injection in a scanned repo run
# Bash, write files and reach the network with no prompt. The default is now acceptEdits and readonly
# mode fences the CLI with a read-only tool allowlist; pin both so a "make the map work" edit cannot
# quietly restore the old default.
echo "consistency: the extension never defaults to bypassPermissions"
bad=0
sed -n "/extraArgs: c.get<string\[\]>('extraArgs'/p" vscode-extension/src/extension.ts | grep -q . || { echo "  ✗ extension.ts: the extraArgs default moved — update this check"; bad=1; }
sed -n "/extraArgs: c.get<string\[\]>('extraArgs'/p" vscode-extension/src/extension.ts | grep -q bypassPermissions && { echo "  ✗ extension.ts defaults extraArgs to bypassPermissions"; bad=1; }
sed -n '/"cwkUi.extraArgs"/,/"scope"/p' vscode-extension/package.json | grep -q '"default"' || { echo "  ✗ package.json: cwkUi.extraArgs has no default — update this check"; bad=1; }
# the description may (and does) NAME bypassPermissions to warn about it — only the default array counts
sed -n '/"cwkUi.extraArgs"/,/"description"/p' vscode-extension/package.json | grep -v '"description"' | grep -q bypassPermissions && { echo "  ✗ package.json defaults cwkUi.extraArgs to bypassPermissions"; bad=1; }
grep -q "'--permission-mode', 'acceptEdits'" vscode-extension/src/extension.ts || { echo "  ✗ extension.ts default is not acceptEdits"; bad=1; }
# readonly mode: the read-only allowlist exists, is passed with --permission-mode default, and is what
# spawnClaude actually sends (an allowlist nobody applies is a comment).
grep -q "^const READONLY_TOOLS = \[" vscode-extension/src/extension.ts || { echo "  ✗ extension.ts has no READONLY_TOOLS allowlist"; bad=1; }
for t in Read Grep Glob mcp__provenlens__provenlens_explore mcp__provenlens__provenlens_why; do
  sed -n '/^const READONLY_TOOLS = \[/,/^\];/p' vscode-extension/src/extension.ts | grep -q "'$t'" || { echo "  ✗ READONLY_TOOLS lacks $t"; bad=1; }
done
for t in Bash Edit Write WebFetch WebSearch; do
  sed -n '/^const READONLY_TOOLS = \[/,/^\];/p' vscode-extension/src/extension.ts | grep -q "'$t'" && { echo "  ✗ READONLY_TOOLS grants $t — that is not read-only"; bad=1; }
done
grep -q "'--permission-mode', 'default', '--allowedTools', READONLY_TOOLS.join(',')" vscode-extension/src/extension.ts || { echo "  ✗ readonly mode does not pass --permission-mode default + --allowedTools"; bad=1; }
grep -q "\.\.\.this\.permissionArgs(extraArgs)\]" vscode-extension/src/extension.ts || { echo "  ✗ spawnClaude does not route extraArgs through permissionArgs()"; bad=1; }
{ grep -q "showWarningMessage" vscode-extension/src/extension.ts && grep -q "isBypass(extraArgs)" vscode-extension/src/extension.ts; } || { echo "  ✗ no warning when the user opts into bypassPermissions"; bad=1; }
[ "$bad" -eq 0 ] && echo "  ✓ default is acceptEdits; readonly fences the CLI with a read-only allowlist; bypass is opt-in + warned" || fail=1

echo "consistency: help.md mentions every command"
bad=0
for f in commands/*.md; do
  base=$(basename "$f" .md)
  [ "$base" = "$CMD_ONLY" ] && continue
  grep -qE "/cwk-$base([^a-z-]|\$)" commands/help.md || { echo "  ✗ /cwk-$base missing from commands/help.md"; bad=1; }
done
[ "$bad" -eq 0 ] && echo "  ✓ help.md covers every command" || fail=1

echo "consistency: extension card (media/main.js) per skill"
bad=0
cards=$(grep -oE "^  A\('cwk-[a-z-]+'" vscode-extension/media/main.js | grep -oE "cwk-[a-z-]+" | sort -u)
for s in $skills_set; do
  echo "$cards" | grep -qxF "$s" || { echo "  ✗ $s has no A(...) card in media/main.js"; bad=1; }
done
[ "$bad" -eq 0 ] && echo "  ✓ every skill has a UI card" || fail=1

echo "consistency: docs/skills-catalog.html lists every skill"
bad=0
rows=$(grep -oE 'class="name">cwk-[a-z-]+' docs/skills-catalog.html | sed 's/.*>//' | sort -u)
for s in $skills_set; do
  echo "$rows" | grep -qxF "$s" || { echo "  ✗ $s has no row in docs/skills-catalog.html"; bad=1; }
done
for r in $rows; do
  [ -d "skills/$r" ] || { echo "  ✗ catalog lists $r but skills/$r/ does not exist"; bad=1; }
done
[ "$bad" -eq 0 ] && echo "  ✓ catalog covers every skill" || fail=1

# The counts are written by hand in several docs; drift there is invisible until someone counts.
echo "consistency: documented counts match reality"
bad=0
n_skills=$(ls -d skills/cwk-*/ | wc -l | tr -d ' ')
n_cmds=$(ls commands/*.md | wc -l | tr -d ' ')
check_count() {  # file, regex with ONE capture group, expected, label
  local f="$1" re="$2" want="$3" label="$4" got
  got=$(grep -oE "$re" "$f" | grep -oE '[0-9]+' | head -1)
  [ -z "$got" ] && { echo "  ✗ $f: could not find the $label count (pattern changed?)"; bad=1; return; }
  [ "$got" = "$want" ] || { echo "  ✗ $f says $got $label, actual is $want"; bad=1; }
}
check_count README.md                    '# [0-9]+ skills \(the methodology' "$n_skills" skills
check_count README.md                    'The [0-9]+ skills and 7 sub-agents' "$n_skills" skills
check_count README.md                    '# [0-9]+ slash commands'           "$n_cmds"   commands
check_count docs/skills-catalog.html     '<b>[0-9]+</b> skills'              "$n_skills" skills
check_count vscode-extension/README.md   'all [0-9]+ skills'                 "$n_skills" skills
check_count docs/manual-setup-guide.html '# [0-9]+ skill →'                  "$n_skills" skills
check_count docs/manual-setup-guide.html '# [0-9]+ command'                  "$n_cmds"   commands
[ "$bad" -eq 0 ] && echo "  ✓ documented counts match ($n_skills skills / $n_cmds commands)" || fail=1

# A skill that edits code, or whose conclusions someone acts on, carries the three trailer sections
# (see docs/skill-anatomy.md). Without a check they get written once and then omitted from the next
# skill, and the standard quietly stops being one.
echo "consistency: review skills run the shared review protocol"
# /cwk-review and /cwk-pr turn a diff into findings through references/review-protocol.md, and the
# reviewer agents report in its format. Without these checks one of them drifts back to its own flow.
bad=0
for sk in cwk-review cwk-pr; do
  for ref in review-protocol.md review-traps.md; do
    [ -f "skills/$sk/references/$ref" ] || { echo "  ✗ $sk lacks references/$ref (run scripts/sync-bundles.sh)"; bad=1; }
    grep -qF "$ref" "skills/$sk/SKILL.md" || { echo "  ✗ $sk bundles $ref but never points at it"; bad=1; }
  done
done
for ag in agents/cwk-*-reviewer.md; do
  grep -q "^## How to report (all reviewer agents)" "$ag" || { echo "  ✗ $ag has no shared finding format"; bad=1; }
  grep -q "^Quote:" "$ag" || { echo "  ✗ $ag's finding format has no Quote field"; bad=1; }
done
[ "$bad" -eq 0 ] && echo "  ✓ review skills bundle and cite the protocol; every reviewer agent reports in its format" || fail=1

echo "consistency: high-stakes skills carry rationalizations / red flags / verification"
HIGH_STAKES="cwk-build cwk-fix-bug cwk-migrate cwk-simplify cwk-perf cwk-observe
  cwk-rails-to-spring cwk-review cwk-drift cwk-runbook"
bad=0
for sk in $HIGH_STAKES; do
  f="skills/$sk/SKILL.md"
  [ -f "$f" ] || { echo "  ✗ $f missing"; bad=1; continue; }
  for sec in "Common rationalizations" "Red flags" "Verification"; do
    grep -qi "^## .*$sec" "$f" || { echo "  ✗ $sk has no '## $sec' section"; bad=1; }
  done
  # a Verification section with no checkboxes is a heading, not an exit gate
  awk '/^## Verification/,0' "$f" | grep -q '^- \[ \]' || { echo "  ✗ $sk: Verification has no checkbox items"; bad=1; }
done
# every code-editing skill must be on the list — a new one must not slip past this check
for sk in cwk-build cwk-fix-bug cwk-migrate cwk-simplify cwk-perf cwk-observe cwk-rails-to-spring; do
  # collapse the newline in the list before matching — the same whitespace trap that once made
  # git-guard's multi-line subcommand allowlist miss whichever name sat at a line boundary.
  case " ${HIGH_STAKES//[$'\n\t']/ } " in *" $sk "*) ;; *) echo "  – note: $sk edits code but is not in HIGH_STAKES (deliberate?)";; esac
done
[ "$bad" -eq 0 ] && echo "  ✓ all $(echo $HIGH_STAKES | wc -w | tr -d ' ') high-stakes skills carry the trailer" || fail=1

# build/qa/review cite rule ids (BR-V2, CF-03) to tie a test or a finding to the rule it protects.
# Those ids only exist because kb-steps tells scan to create them — if that instruction is ever
# dropped, the citations become dangling and nothing else would notice.
echo "consistency: rule ids are mandated where they are cited"
bad=0
grep -q 'BR-<AREA>' resources/kb-steps.md || { echo "  ✗ kb-steps.md no longer defines the BR-<AREA><n> id format"; bad=1; }
grep -q 'Append-only' resources/kb-steps.md || { echo "  ✗ kb-steps.md lost the append-only id rule"; bad=1; }
grep -q 'CF-01' resources/kb-steps.md       || { echo "  ✗ kb-steps.md no longer gives core flows stable ids"; bad=1; }
# every KB section the skills reference must be DEFINED in the canonical spec, not just produced
for doc in 13-business-rules 10-core-flows 16-architecture-patterns 17-async-events; do
  grep -q "$doc" resources/kb-steps.md || { echo "  ✗ kb-steps.md does not define $doc.md, but skills reference it"; bad=1; }
done
for sk in cwk-build cwk-qa; do
  grep -qE 'BR-[A-Z]?[0-9]' "skills/$sk/SKILL.md" || echo "  – note: $sk no longer cites rule ids"
done
[ "$bad" -eq 0 ] && echo "  ✓ kb-steps mandates the ids that other skills cite" || fail=1

# provenlens is an optional dependency (docs/provenlens.md). Every skill that reasons about who-calls-what
# carries the shared `### provenlens (optional)` block INCLUDING its fallback sentence — the sentence is
# the whole point, because a skill that silently degrades to grep is one whose output gets over-trusted.
# A skill that genuinely never reads a call graph is listed here with a reason instead. A skill in
# NEITHER list fails: that is what stops the standard from quietly ending at the last one written.
echo "consistency: provenlens block present where it belongs, absent where it does not"
PROVENLENS_OPT_OUT="cwk-issues cwk-pdf cwk-splunk-report"
#   issues          — turns an APPROVED plan into tickets; the blast radius is already in the plan,
#                     and re-deriving it here would be a second opinion nobody asked for
#   pdf             — renders a Markdown/HTML file to PDF; never opens the source
#   splunk-report   — queries Splunk and posts to Slack; it may not even run inside the app's repo
# discover and qa-integration were on this list and should not have been. Both ask a reach
# question -- "which existing flow does this touch?" and "which regressions do I run?" -- and
# answering either from intuition is the thing the block exists to stop.
PROVENLENS_MARK='### provenlens (optional)'
PROVENLENS_FALLBACK='grep-depth only (no provenlens index)'
bad=0
n_with=0
for d in skills/cwk-*/; do
  sk=$(basename "$d"); f="$d/SKILL.md"
  case " ${PROVENLENS_OPT_OUT//[$'\n\t']/ } " in
    *" $sk "*)
      grep -qF "$PROVENLENS_MARK" "$f" && { echo "  ✗ $sk is on the opt-out list but carries the block"; bad=1; }
      continue;;
  esac
  if ! grep -qF "$PROVENLENS_MARK" "$f"; then
    echo "  ✗ $sk has no '$PROVENLENS_MARK' block and is not on the opt-out list"; bad=1; continue
  fi
  grep -qF "$PROVENLENS_FALLBACK" "$f" || { echo "  ✗ $sk has the block but dropped the fallback sentence"; bad=1; }
  grep -qF '**Here:**' "$f" || { echo "  ✗ $sk has the block but no skill-specific '**Here:**' commands"; bad=1; }
  n_with=$((n_with+1))
done
[ -f docs/provenlens.md ] || { echo "  ✗ docs/provenlens.md is missing but every skill points at it"; bad=1; }
# the sub-agents the skills fan out to must be able to reach provenlens, or the block is a lie there
for a in cwk-impact-detector cwk-codebase-analyzer cwk-security-reviewer; do
  grep -q 'mcp__provenlens__' "agents/$a.md" || { echo "  ✗ agents/$a.md cannot reach provenlens (no mcp__provenlens__ tool)"; bad=1; }
done
# read-only sub-agents must stay read-only: granting Bash to reach the CLI would undo that
for a in agents/*.md; do
  grep -m1 '^tools:' "$a" | grep -q '\bBash\b' && { echo "  ✗ $a grants Bash — sub-agents are read-only; pass CLI output in via the prompt"; bad=1; }
done
# The investigating skills carry the evidence protocol (reach ledger + code graph) as a bundled copy and
# must point at it — a bundle nobody references is a file, not a standard. The list mirrors
# map_evidence in scripts/sync-bundles.sh; sync-bundles --check catches a copy that is not mapped.
PROVENLENS_EVIDENCE="cwk-ask cwk-document cwk-user-story cwk-plan cwk-runbook cwk-fix-bug cwk-build cwk-review cwk-qa"
for sk in $PROVENLENS_EVIDENCE; do
  f="skills/$sk/SKILL.md"
  [ -f "skills/$sk/references/provenlens-evidence.md" ] || { echo "  ✗ $sk lacks references/provenlens-evidence.md (run scripts/sync-bundles.sh)"; bad=1; }
  grep -qF "provenlens-evidence.md" "$f" || { echo "  ✗ $sk bundles the evidence protocol but never points at it"; bad=1; }
  grep -qiE "reach.ledger" "$f" || { echo "  ✗ $sk has no reach ledger in its output — the anti-miss table is the point"; bad=1; }
done
[ "$bad" -eq 0 ] && echo "  ✓ provenlens block in $n_with skills + evidence protocol in $(echo $PROVENLENS_EVIDENCE | wc -w | tr -d ' '), opted out of $(echo $PROVENLENS_OPT_OUT | wc -w | tr -d ' '), agents wired read-only" || fail=1

# Every skill reads repository content (READMEs, comments, diffs, PR text, KB pages, logs, sub-agent
# reports) and several can run Bash, write files or post outward. The shared rule that all of it is
# data, never instructions, lives in resources/untrusted-input.md; a skill that does not bundle and
# cite it, or an agent without the baseline, is one prompt injection away from acting on planted text.
echo "consistency: untrusted input is data in every skill and agent"
bad=0
for d in skills/cwk-*/; do
  sk=$(basename "$d"); f="$d/SKILL.md"
  [ -f "$d/references/untrusted-input.md" ] || { echo "  ✗ $sk lacks references/untrusted-input.md (add it to map_untrusted in scripts/sync-bundles.sh, then run it)"; bad=1; }
  grep -qF "untrusted-input.md" "$f" || { echo "  ✗ $sk never points at references/untrusted-input.md"; bad=1; }
done
for ag in agents/*.md; do
  grep -q "^## Prompt defence baseline" "$ag" || { echo "  ✗ $ag has no '## Prompt defence baseline' section"; bad=1; }
done
# the two escape hatches the audit found must not come back
grep -qi "auto-send" skills/cwk-splunk-report/SKILL.md && { echo "  ✗ cwk-splunk-report has an auto-send escape hatch again"; bad=1; }
grep -qi "trips the git-guard" skills/cwk-skillify/SKILL.md && { echo "  ✗ cwk-skillify explains how to get around the git-guard again"; bad=1; }
[ "$bad" -eq 0 ] && echo "  ✓ every skill cites untrusted-input.md; every agent carries the prompt defence baseline" || fail=1

# One version, four places. plugin.json is the source of truth; the marketplace entry, the newest
# changelog heading and any current-version claim in the README must repeat it exactly, or a user
# who reads one file installs from another and files a bug against a release that does not exist.
echo "consistency: version in sync — plugin.json == marketplace.json == newest CHANGELOG heading == README"
bad=0
plugin_v=$(grep -oE '"version": *"[0-9.]+"' .claude-plugin/plugin.json | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
[ -n "$plugin_v" ] || { echo "  ✗ .claude-plugin/plugin.json has no semver \"version\""; bad=1; }
market_v=$(grep -oE '"version": *"[0-9.]+"' .claude-plugin/marketplace.json | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
[ -n "$market_v" ] || { echo "  ✗ .claude-plugin/marketplace.json: the cwk plugin entry has no \"version\""; bad=1; }
[ -z "$market_v" ] || [ "$market_v" = "$plugin_v" ] || { echo "  ✗ marketplace.json says $market_v, plugin.json says $plugin_v"; bad=1; }
newest_cl=$(grep -oE '^## \[[0-9]+\.[0-9]+\.[0-9]+\]' CHANGELOG.md | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
[ -n "$newest_cl" ] || { echo "  ✗ CHANGELOG.md has no '## [x.y.z]' heading"; bad=1; }
[ -z "$newest_cl" ] || [ "$newest_cl" = "$plugin_v" ] || { echo "  ✗ newest CHANGELOG heading is [$newest_cl] but plugin.json is $plugin_v (bump one or the other)"; bad=1; }
# README: a semver is either the current version or a released one it refers back to ("Version 3.0.0
# dropped the prefix"); a line that presents itself as the current/latest version must carry plugin_v.
while IFS= read -r line; do
  [ -n "$line" ] || continue
  for v in $(echo "$line" | grep -oE '\b[0-9]+\.[0-9]+\.[0-9]+\b' | sort -u); do
    [ "$v" = "$plugin_v" ] && continue
    if echo "$line" | grep -qiE 'current version|latest version|badge/version|shields\.io'; then
      echo "  ✗ README.md presents $v as the current version; plugin.json is $plugin_v"; bad=1
    elif ! grep -qF "## [$v]" CHANGELOG.md; then
      echo "  ✗ README.md mentions version $v, which is neither the current $plugin_v nor a CHANGELOG release"; bad=1
    fi
  done
done < <(grep -E '\b[0-9]+\.[0-9]+\.[0-9]+\b' README.md | grep -vE 'node-version|semver\.org|keepachangelog')
[ "$bad" -eq 0 ] && echo "  ✓ version $plugin_v agrees across plugin.json, marketplace.json, CHANGELOG and README" || fail=1

# The kit is installed onto company machines. A stray "/Users/<me>/…" in a doc, an e-mail in a
# comment, or an invisible character (zero-width joiner, bidi override — the Trojan Source class) in
# a prompt is a leak or an attack vector a code review cannot see. Shipped = tracked, minus the
# changelog (release notes may quote a reported path), tests/ (fixtures plant these on purpose) and
# the vendored minified bundles (third-party, pinned by hash in vendor/SHA256SUMS). docs/*.html are
# hand-written, not generated, so they are shipped and scanned like everything else.
echo "consistency: zero footprint — no personal paths, e-mails or invisible characters ship"
bad=0
shipped=$(git ls-files | grep -vE '^(CHANGELOG\.md$|tests/|vendor/.*\.min\.js$)' | perl -ne 'chomp; print "$_\n" if -f $_ && ! -B $_')
[ -n "$shipped" ] || { echo "  ✗ git ls-files returned nothing — not a git checkout?"; bad=1; }
# grep -P is GNU-only (macOS ships BSD grep); perl is on every macOS and ubuntu-latest, so it does the
# Unicode scan, and grep -P is used for the byte patterns only where it exists.
if grep -qP '' /dev/null 2>/dev/null; then
  hits=$(echo "$shipped" | tr '\n' '\0' | xargs -0 grep -nP '/Users/[a-z]|/home/[a-z]|C:\\\\Users\\\\' 2>/dev/null)
else
  hits=$(echo "$shipped" | tr '\n' '\0' | xargs -0 perl -ne 'print "$ARGV:$.:$_" if m{/Users/[a-z]|/home/[a-z]|C:\\Users\\}; close ARGV if eof')
fi
[ -z "$hits" ] || { echo "  ✗ absolute personal path in a shipped file:"; echo "$hits" | head -10 | sed 's/^/    /'; bad=1; }
# every e-mail-shaped token is a leak unless its domain is a documentation placeholder (example.com,
# *.example), a git SSH URL (git@github.com) or a vendor address (@anthropic.com)
hits=$(echo "$shipped" | tr '\n' '\0' | xargs -0 perl -ne '
  while (/\b([A-Za-z0-9._%+-]+@([A-Za-z0-9.-]+\.[A-Za-z]{2,}))\b/g) {
    my ($addr, $dom) = ($1, lc $2);
    next if $dom =~ /(^|\.)example(\.[a-z]+)?$/ || $dom eq "github.com" || $dom eq "anthropic.com";
    print "$ARGV:$.: $addr\n";
  }
  close ARGV if eof')
[ -z "$hits" ] || { echo "  ✗ e-mail address in a shipped file:"; echo "$hits" | head -10 | sed 's/^/    /'; bad=1; }
# U+200B–U+200F zero-width + marks, U+202A–U+202E bidi embeddings/overrides, U+2060–U+2064 invisible
# operators, U+FEFF BOM/ZWNBSP — none has a legitimate use in this repo's prose or code
hits=$(echo "$shipped" | tr '\n' '\0' | xargs -0 perl -CSD -ne '
  if (/[\x{200B}-\x{200F}\x{202A}-\x{202E}\x{2060}-\x{2064}\x{FEFF}]/) { printf "%s:%d: U+%04X\n", $ARGV, $., ord($&) }
  close ARGV if eof' 2>/dev/null)
[ -z "$hits" ] || { echo "  ✗ zero-width / bidi control character in a shipped file:"; echo "$hits" | head -10 | sed 's/^/    /'; bad=1; }
[ "$bad" -eq 0 ] && echo "  ✓ $(echo "$shipped" | wc -l | tr -d ' ') shipped text files carry no personal path, e-mail or invisible character" || fail=1

# hooks.json is what Claude Code actually runs. A command that points at a renamed file, a file that
# lost its +x bit in a checkout, or a syntax error in a hook all fail the same way: the guard does not
# run and every git command sails through. The plugin loader gives no error for any of them.
echo "consistency: hooks.json wiring — every command exists, is executable and parses"
bad=0
if command -v node >/dev/null 2>&1; then
  node -e 'JSON.parse(require("fs").readFileSync("hooks/hooks.json","utf8"))' 2>/dev/null || { echo "  ✗ hooks/hooks.json is not valid JSON"; bad=1; }
elif command -v jq >/dev/null 2>&1; then
  jq empty hooks/hooks.json 2>/dev/null || { echo "  ✗ hooks/hooks.json is not valid JSON"; bad=1; }
fi
cmds=$(grep -oE '"command": *"[^"]+"' hooks/hooks.json | sed -E 's/^"command": *"//; s/"$//')
[ -n "$cmds" ] || { echo "  ✗ hooks/hooks.json declares no command hooks"; bad=1; }
n_hooks=0
for c in $cmds; do
  case "$c" in
    '${CLAUDE_PLUGIN_ROOT}/hooks/'*) f=${c#'${CLAUDE_PLUGIN_ROOT}/'} ;;
    *) echo "  ✗ hooks.json command '$c' is not under \${CLAUDE_PLUGIN_ROOT}/hooks/ — it will not resolve when the plugin is installed"; bad=1; continue ;;
  esac
  [ -f "$f" ] || { echo "  ✗ hooks.json points at $f, which does not exist"; bad=1; continue; }
  [ -x "$f" ] || { echo "  ✗ $f is not executable (chmod +x, and check core.fileMode)"; bad=1; }
  n_hooks=$((n_hooks+1))
done
for f in hooks/*.sh; do
  bash -n "$f" 2>/dev/null || { echo "  ✗ $f does not parse (bash -n)"; bad=1; }
  [ -x "$f" ] || { echo "  ✗ $f is not executable"; bad=1; }
  head -1 "$f" | grep -qE '^#!.*\b(bash|sh)\b' || { echo "  ✗ $f has no bash shebang"; bad=1; }
  grep -qF "hooks/$(basename "$f")" hooks/hooks.json || echo "  – note: hooks/$(basename "$f") is not wired in hooks.json (deliberate?)"
done
[ "$bad" -eq 0 ] && echo "  ✓ $n_hooks hook command(s) wired to existing executable scripts; every hooks/*.sh parses" || fail=1

# A mutable tag (actions/checkout@v4) is a supply-chain door: whoever controls the tag controls the
# CI runner. Every action is pinned to a full commit SHA, with the version it stands for in a trailing
# comment so a human can still read the file (and Dependabot can still bump it).
echo "consistency: GitHub Actions pinned by commit SHA"
bad=0; n_uses=0
for wf in .github/workflows/*.yml .github/workflows/*.yaml; do
  [ -f "$wf" ] || continue
  while IFS= read -r line; do
    n_uses=$((n_uses+1))
    ref=$(echo "$line" | sed -E 's/^[[:space:]]*-?[[:space:]]*uses:[[:space:]]*//')
    case "$ref" in
      ./*|docker://*) continue ;;   # a local composite action or an image digest is not a tag
    esac
    echo "$ref" | grep -qE '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(/[A-Za-z0-9_./-]+)?@[0-9a-f]{40}[[:space:]]+#[[:space:]]*v?[0-9]+\.[0-9]+(\.[0-9]+)?[[:space:]]*$' \
      || { echo "  ✗ $wf: not pinned to a 40-hex SHA with a '# vX.Y.Z' comment: $ref"; bad=1; }
  done < <(grep -E '^[[:space:]]*-?[[:space:]]*uses:' "$wf")
done
[ "$n_uses" -gt 0 ] || { echo "  ✗ no 'uses:' found under .github/workflows/ (pattern changed?)"; bad=1; }
[ "$bad" -eq 0 ] && echo "  ✓ all $n_uses action references are SHA-pinned with a version comment" || fail=1

# README's test table is the only place the suites are described to a reader deciding whether to
# trust the kit. Every suite run.sh runs gets a row, and the case count in that row is the number the
# suite prints today — the suites run here (in parallel, each in its own fixture) so the number cannot
# quietly age. A suite that prints no "N passed" summary is counted by its ✓ marks.
echo "consistency: README test table — a row per suite in run.sh, with today's case count"
bad=0
suites=$(grep -oE 'tests/[a-z0-9-]+\.test\.(sh|cjs)' tests/run.sh | sort -u)
CT=$(mktemp -d "${TMPDIR:-/tmp}/consistency-counts.XXXXXX")
for s in $suites; do
  n=$(basename "$s")
  [ "$n" = "consistency.test.sh" ] && continue   # this file; it counts itself statically below
  case "$s" in
    *.sh)  ( bash "$s" >"$CT/$n.out" 2>&1 ) & ;;
    *.cjs) if command -v node >/dev/null 2>&1; then ( node "$s" >"$CT/$n.out" 2>&1 ) & else echo skipped >"$CT/$n.skip"; fi ;;
  esac
done
wait
for s in $suites; do
  n=$(basename "$s")
  row=$(grep -E "^\| \`$n\` \|" README.md | head -1)
  [ -n "$row" ] || { echo "  ✗ README.md test table has no row for $n (it is in tests/run.sh)"; bad=1; continue; }
  documented=$(echo "$row" | awk -F'|' '{print $3}' | grep -oE '[0-9]+' | head -1)
  [ -n "$documented" ] || { echo "  ✗ README.md row for $n carries no case count"; bad=1; continue; }
  if [ "$n" = "consistency.test.sh" ]; then
    actual=$(grep -cE '^echo "consistency: [A-Za-z]' tests/consistency.test.sh)
    echo "$row" | grep -qE "\| $actual groups \|" || { echo "  ✗ README.md says $n has '$documented groups', this file has $actual"; bad=1; }
    continue
  fi
  [ -f "$CT/$n.skip" ] && { echo "  – note: $n not run (node missing); README says $documented"; continue; }
  actual=$(grep -oE '^[a-z0-9-]+: [0-9]+ passed, [0-9]+ failed' "$CT/$n.out" | grep -oE '[0-9]+ passed' | grep -oE '[0-9]+')
  [ -n "$actual" ] || actual=$(grep -c '✓' "$CT/$n.out")
  [ "$actual" = "$documented" ] || { echo "  ✗ README.md says $n has $documented cases, it has $actual today"; bad=1; }
done
# and no row for a suite run.sh no longer runs
for n in $(grep -oE '^\| `[a-z0-9-]+\.test\.(sh|cjs)` \|' README.md | grep -oE '[a-z0-9-]+\.test\.(sh|cjs)'); do
  echo "$suites" | grep -qxF "tests/$n" || { echo "  ✗ README.md lists $n but tests/run.sh does not run it"; bad=1; }
done
rm -rf "$CT"
[ "$bad" -eq 0 ] && echo "  ✓ README table covers all $(echo "$suites" | wc -l | tr -d ' ') suites with their current counts" || fail=1

echo "consistency: $([ "$fail" -eq 0 ] && echo PASS || echo FAIL)"
[ "$fail" -eq 0 ]
