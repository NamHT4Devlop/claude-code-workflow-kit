#!/usr/bin/env bash
# Drift guards: commands/ ↔ skills/ ↔ extension ALLOWED ↔ help.md must stay in sync.
set -uo pipefail
cd "$(dirname "$0")/.."
fail=0

# Intentional exceptions:
#   help — command-only (commands/help.md is documentation; there is no skills/namht-help/).
CMD_ONLY="help"
# Tokens that match the namht-* shape but are NOT skills — the artifact folder every skill
# writes to. Keep this list tiny; anything else matching namht-* must be a real skill/agent.
NON_SKILL="namht-sessions"

echo "consistency: commands reference existing skills"
bad=0
for f in commands/*.md; do
  base=$(basename "$f" .md)
  refs=$(grep -oE 'namht-[a-z-]+' "$f" | sort -u | grep -vxF "$NON_SKILL")
  if [ -z "$refs" ]; then echo "  ✗ $f references no namht-* skill"; bad=1; continue; fi
  for r in $refs; do
    [ -d "skills/$r" ] && continue
    [ -f "agents/$r.md" ] && continue   # sub-agents (namht-codebase-analyzer, …) are valid references
    short=${r#namht-}
    # help.md lists commands, so a command-only reference is fine there
    if [ "$base" = "help" ] && [ -f "commands/$short.md" ]; then continue; fi
    echo "  ✗ $f references $r — no skills/$r/ and no agents/$r.md"; bad=1
  done
done
[ "$bad" -eq 0 ] && echo "  ✓ command → skill references OK" || fail=1

echo "consistency: every skill has a matching command"
bad=0
for d in skills/namht-*/; do
  s=$(basename "$d"); short=${s#namht-}
  [ -f "commands/$short.md" ] || { echo "  ✗ skills/$s/ has no commands/$short.md"; bad=1; }
done
[ "$bad" -eq 0 ] && echo "  ✓ skill → command mapping OK" || fail=1

echo "consistency: extension ALLOWED == skills/namht-*/"
allowed=$(sed -n '/const ALLOWED = new Set(\[/,/\]);/p' vscode-extension/src/extension.ts | grep -oE "'namht-[a-z-]+'" | tr -d "'" | sort -u)
skills_set=$(for d in skills/namht-*/; do basename "$d"; done | sort -u)
if [ "$allowed" = "$skills_set" ]; then
  echo "  ✓ ALLOWED matches skills/"
else
  echo "  ✗ ALLOWED != skills/namht-*/ (< only in ALLOWED, > only in skills/):"
  diff <(echo "$allowed") <(echo "$skills_set") | grep '^[<>]' | sed 's/^/    /'
  fail=1
fi

echo "consistency: help.md mentions every command"
bad=0
for f in commands/*.md; do
  base=$(basename "$f" .md)
  [ "$base" = "$CMD_ONLY" ] && continue
  grep -qE "/namht-$base([^a-z-]|\$)" commands/help.md || { echo "  ✗ /namht-$base missing from commands/help.md"; bad=1; }
done
[ "$bad" -eq 0 ] && echo "  ✓ help.md covers every command" || fail=1

echo "consistency: extension card (media/main.js) per skill"
bad=0
cards=$(grep -oE "^  A\('namht-[a-z-]+'" vscode-extension/media/main.js | grep -oE "namht-[a-z-]+" | sort -u)
for s in $skills_set; do
  echo "$cards" | grep -qxF "$s" || { echo "  ✗ $s has no A(...) card in media/main.js"; bad=1; }
done
[ "$bad" -eq 0 ] && echo "  ✓ every skill has a UI card" || fail=1

echo "consistency: docs/skills-catalog.html lists every skill"
bad=0
rows=$(grep -oE 'class="name">namht-[a-z-]+' docs/skills-catalog.html | sed 's/.*>//' | sort -u)
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
n_skills=$(ls -d skills/namht-*/ | wc -l | tr -d ' ')
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
HIGH_STAKES="namht-build namht-fix-bug namht-migrate namht-simplify namht-perf namht-observe
  namht-rails-to-spring namht-review namht-drift namht-runbook"
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
for sk in namht-build namht-fix-bug namht-migrate namht-simplify namht-perf namht-observe namht-rails-to-spring; do
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
for sk in namht-build namht-qa; do
  grep -qE 'BR-[A-Z]?[0-9]' "skills/$sk/SKILL.md" || echo "  – note: $sk no longer cites rule ids"
done
[ "$bad" -eq 0 ] && echo "  ✓ kb-steps mandates the ids that other skills cite" || fail=1

# codelens is an optional dependency (docs/codelens.md). Every skill that reasons about who-calls-what
# carries the shared `### codelens (optional)` block INCLUDING its fallback sentence — the sentence is
# the whole point, because a skill that silently degrades to grep is one whose output gets over-trusted.
# A skill that genuinely never reads a call graph is listed here with a reason instead. A skill in
# NEITHER list fails: that is what stops the standard from quietly ending at the last one written.
echo "consistency: codelens block present where it belongs, absent where it does not"
CODELENS_OPT_OUT="namht-discover namht-issues namht-pdf namht-qa-integration namht-splunk-report"
#   discover        — runs before any code exists
#   issues          — turns an approved plan into tickets; touches a tracker, not a repo
#   pdf             — renders a Markdown/HTML file to PDF
#   qa-integration  — drives a live browser; its evidence is the DOM, not the source
#   splunk-report   — queries Splunk and posts to Slack
CODELENS_MARK='### codelens (optional)'
CODELENS_FALLBACK='grep-depth only (no codelens index)'
bad=0
n_with=0
for d in skills/namht-*/; do
  sk=$(basename "$d"); f="$d/SKILL.md"
  case " ${CODELENS_OPT_OUT//[$'\n\t']/ } " in
    *" $sk "*)
      grep -qF "$CODELENS_MARK" "$f" && { echo "  ✗ $sk is on the opt-out list but carries the block"; bad=1; }
      continue;;
  esac
  if ! grep -qF "$CODELENS_MARK" "$f"; then
    echo "  ✗ $sk has no '$CODELENS_MARK' block and is not on the opt-out list"; bad=1; continue
  fi
  grep -qF "$CODELENS_FALLBACK" "$f" || { echo "  ✗ $sk has the block but dropped the fallback sentence"; bad=1; }
  grep -qF '**Here:**' "$f" || { echo "  ✗ $sk has the block but no skill-specific '**Here:**' commands"; bad=1; }
  n_with=$((n_with+1))
done
[ -f docs/codelens.md ] || { echo "  ✗ docs/codelens.md is missing but every skill points at it"; bad=1; }
# the sub-agents the skills fan out to must be able to reach codelens, or the block is a lie there
for a in namht-impact-detector namht-codebase-analyzer namht-security-reviewer; do
  grep -q 'mcp__codelens__' "agents/$a.md" || { echo "  ✗ agents/$a.md cannot reach codelens (no mcp__codelens__ tool)"; bad=1; }
done
# read-only sub-agents must stay read-only: granting Bash to reach the CLI would undo that
for a in agents/*.md; do
  grep -m1 '^tools:' "$a" | grep -q '\bBash\b' && { echo "  ✗ $a grants Bash — sub-agents are read-only; pass CLI output in via the prompt"; bad=1; }
done
[ "$bad" -eq 0 ] && echo "  ✓ codelens block in $n_with skills, opted out of $(echo $CODELENS_OPT_OUT | wc -w | tr -d ' '), agents wired read-only" || fail=1

echo "consistency: version + changelog"
bad=0
plugin_v=$(grep -oE '"version": "[0-9.]+"' .claude-plugin/plugin.json | grep -oE '[0-9.]+')
grep -qF "## [$plugin_v]" CHANGELOG.md || { echo "  ✗ plugin.json is $plugin_v but CHANGELOG.md has no '## [$plugin_v]' entry"; bad=1; }
[ "$bad" -eq 0 ] && echo "  ✓ plugin version $plugin_v is in the changelog" || fail=1

echo "consistency: $([ "$fail" -eq 0 ] && echo PASS || echo FAIL)"
[ "$fail" -eq 0 ]
