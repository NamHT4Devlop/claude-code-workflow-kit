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

echo "consistency: version + changelog"
bad=0
plugin_v=$(grep -oE '"version": "[0-9.]+"' .claude-plugin/plugin.json | grep -oE '[0-9.]+')
grep -qF "## [$plugin_v]" CHANGELOG.md || { echo "  ✗ plugin.json is $plugin_v but CHANGELOG.md has no '## [$plugin_v]' entry"; bad=1; }
[ "$bad" -eq 0 ] && echo "  ✓ plugin version $plugin_v is in the changelog" || fail=1

echo "consistency: $([ "$fail" -eq 0 ] && echo PASS || echo FAIL)"
[ "$fail" -eq 0 ]
