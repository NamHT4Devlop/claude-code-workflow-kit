#!/usr/bin/env bash
# onboard.test.sh — onboard-project.sh writes into someone else's repo: it appends to .gitignore and
# can create CLAUDE.md. Its header promises "idempotent, safe to re-run" and "only if none exists",
# and nothing checked either. The expensive failure is overwriting a project's own CLAUDE.md.
set -uo pipefail
cd "$(dirname "$0")/.."
ONBOARD="$PWD/scripts/onboard-project.sh"
pass=0; fail=0
ok()   { echo "  ✓ $1"; pass=$((pass+1)); }
bad()  { echo "  ✗ $1"; fail=$((fail+1)); }
check(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (want '$3', got '$2')"; fi; }

TMP=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/onboard-test.XXXXXX")" && pwd); trap 'rm -rf "$TMP"' EXIT

echo "onboard: a fresh repo gets both ignores and a starter CLAUDE.md"
mkdir -p "$TMP/fresh"
"$ONBOARD" "$TMP/fresh" >/dev/null 2>&1
check "cwk-sessions ignored"  "$(grep -cxF 'cwk-sessions/' "$TMP/fresh/.gitignore")" 1
check "knowledge-base ignored"  "$(grep -cxF 'knowledge-base/' "$TMP/fresh/.gitignore")" 1
check "CLAUDE.md created"       "$([ -f "$TMP/fresh/CLAUDE.md" ] && echo yes || echo no)" yes
check "it names the project"    "$(grep -c '^# fresh$' "$TMP/fresh/CLAUDE.md")" 1

echo "onboard: re-running adds nothing twice"
"$ONBOARD" "$TMP/fresh" >/dev/null 2>&1
"$ONBOARD" "$TMP/fresh" >/dev/null 2>&1
check "one cwk-sessions line" "$(grep -cxF 'cwk-sessions/' "$TMP/fresh/.gitignore")" 1
check "one knowledge-base line" "$(grep -cxF 'knowledge-base/' "$TMP/fresh/.gitignore")" 1

echo "onboard: an existing CLAUDE.md is never overwritten (the costly failure)"
mkdir -p "$TMP/hasclaude"
printf 'MY OWN INSTRUCTIONS — do not clobber\n' > "$TMP/hasclaude/CLAUDE.md"
"$ONBOARD" "$TMP/hasclaude" >/dev/null 2>&1
check "content untouched" "$(cat "$TMP/hasclaude/CLAUDE.md")" "MY OWN INSTRUCTIONS — do not clobber"

echo "onboard: .claude/CLAUDE.md also counts as existing"
mkdir -p "$TMP/nested/.claude"
printf 'nested instructions\n' > "$TMP/nested/.claude/CLAUDE.md"
"$ONBOARD" "$TMP/nested" >/dev/null 2>&1
check "no root CLAUDE.md invented" "$([ -f "$TMP/nested/CLAUDE.md" ] && echo yes || echo no)" no
check "nested one untouched"       "$(cat "$TMP/nested/.claude/CLAUDE.md")" "nested instructions"

echo "onboard: an existing .gitignore keeps its own entries"
mkdir -p "$TMP/hasgi"
printf 'node_modules/\ndist/\n' > "$TMP/hasgi/.gitignore"
"$ONBOARD" "$TMP/hasgi" >/dev/null 2>&1
check "node_modules kept" "$(grep -cxF 'node_modules/' "$TMP/hasgi/.gitignore")" 1
check "dist kept"         "$(grep -cxF 'dist/' "$TMP/hasgi/.gitignore")" 1
check "ours appended"     "$(grep -cxF 'knowledge-base/' "$TMP/hasgi/.gitignore")" 1

echo "onboard: a near-miss line does not count as already-present"
# `-qxF` matches whole lines; a substring match would skip a legitimate addition and leave the
# repo un-ignored — which is how a Knowledge Base ends up committed to a team repo.
mkdir -p "$TMP/nearmiss"
printf '# knowledge-base/ was here\nsrc/knowledge-base/\n' > "$TMP/nearmiss/.gitignore"
"$ONBOARD" "$TMP/nearmiss" >/dev/null 2>&1
check "the real pattern was added" "$(grep -cxF 'knowledge-base/' "$TMP/nearmiss/.gitignore")" 1

echo "onboard: a missing directory is an error, not a silent no-op"
"$ONBOARD" "$TMP/does-not-exist" >/dev/null 2>&1
check "exit non-zero" "$([ $? -ne 0 ] && echo yes || echo no)" yes

echo "onboard: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
