#!/usr/bin/env bash
# migrate-sessions.test.sh — scripts/migrate-sessions.sh touches a user's REAL session data in
# other repos, so every branch gets a fixture test. The rule it must never break: no data loss.
set -uo pipefail
cd "$(dirname "$0")/.."
SCRIPT="$PWD/scripts/migrate-sessions.sh"
pass=0; fail=0
ok()   { echo "  ✓ $1"; pass=$((pass+1)); }
bad()  { echo "  ✗ $1"; fail=$((fail+1)); }
check(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (want '$3', got '$2')"; fi; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# --- fixture: a repo with only the legacy folder ---------------------------------
mk_legacy() {
  local r="$TMP/$1"; rm -rf "$r"; mkdir -p "$r/spec-kit-sessions/answers" "$r/spec-kit-sessions/builds"
  printf 'old answer\n'  > "$r/spec-kit-sessions/answers/a.md"
  printf 'old journal\n' > "$r/spec-kit-sessions/answers/_journal.md"
  printf 'old build\n'   > "$r/spec-kit-sessions/builds/b.md"
  echo "$r"
}

echo "migrate-sessions: --dry-run changes nothing"
r=$(mk_legacy dry)
"$SCRIPT" --dry-run "$r" >/dev/null 2>&1
check "legacy folder still there"  "$([ -d "$r/spec-kit-sessions" ] && echo yes || echo no)" yes
check "new folder NOT created"     "$([ -e "$r/cwk-sessions"    ] && echo yes || echo no)" no

echo "migrate-sessions: plain rename when only the legacy folder exists"
r=$(mk_legacy plain)
"$SCRIPT" "$r" >/dev/null 2>&1
check "legacy folder gone"         "$([ -e "$r/spec-kit-sessions" ] && echo yes || echo no)" no
check "new folder exists"          "$([ -d "$r/cwk-sessions"    ] && echo yes || echo no)" yes
check "nested file preserved"      "$(cat "$r/cwk-sessions/builds/b.md" 2>/dev/null)" "old build"
check "file count preserved"       "$(find "$r/cwk-sessions" -type f | wc -l | tr -d ' ')" 3

echo "migrate-sessions: merge without overwriting when BOTH exist"
r=$(mk_legacy merge)
mkdir -p "$r/cwk-sessions/answers"
printf 'NEW journal\n' > "$r/cwk-sessions/answers/_journal.md"   # same relative path, different content
printf 'new only\n'    > "$r/cwk-sessions/answers/n.md"
"$SCRIPT" "$r" >/dev/null 2>&1
check "existing file NOT overwritten" "$(cat "$r/cwk-sessions/answers/_journal.md")" "NEW journal"
check "legacy-only file carried over" "$(cat "$r/cwk-sessions/answers/a.md" 2>/dev/null)" "old answer"
check "new-only file untouched"       "$(cat "$r/cwk-sessions/answers/n.md")" "new only"
check "nested legacy dir carried"     "$(cat "$r/cwk-sessions/builds/b.md" 2>/dev/null)" "old build"
check "legacy folder KEPT — its journal differs and was not merged" "$([ -d "$r/spec-kit-sessions" ] && echo yes || echo no)" yes
check "the unmerged legacy file still has its content" "$(cat "$r/spec-kit-sessions/answers/_journal.md" 2>/dev/null)" "old journal"

echo "migrate-sessions: nothing to do is not an error"
r="$TMP/empty"; mkdir -p "$r"
"$SCRIPT" "$r" >/dev/null 2>&1
check "exit 0 with no legacy folder" "$?" 0
check "no folder invented"           "$([ -e "$r/cwk-sessions" ] && echo yes || echo no)" no

echo "migrate-sessions: a missing directory is reported, not silently skipped"
"$SCRIPT" "$TMP/does-not-exist" >/dev/null 2>&1
check "exit non-zero for a bad path" "$([ $? -ne 0 ] && echo yes || echo no)" yes

echo "migrate-sessions: filenames with spaces survive"
r="$TMP/spaces"; rm -rf "$r"; mkdir -p "$r/spec-kit-sessions/qa reports"
printf 'spaced\n' > "$r/spec-kit-sessions/qa reports/my report.md"
mkdir -p "$r/cwk-sessions"; printf 'x\n' > "$r/cwk-sessions/keep.md"   # force the merge path
"$SCRIPT" "$r" >/dev/null 2>&1
check "spaced path carried over" "$(cat "$r/cwk-sessions/qa reports/my report.md" 2>/dev/null)" "spaced"

echo "migrate-sessions: the 2.x name (namht-sessions) is a legacy name too"
r="$TMP/namht"; rm -rf "$r"; mkdir -p "$r/namht-sessions/builds"
printf 'v2 build\n' > "$r/namht-sessions/builds/b.md"
"$SCRIPT" "$r" >/dev/null 2>&1
check "namht-sessions renamed"        "$([ -e "$r/namht-sessions" ] && echo yes || echo no)" no
check "content landed in cwk-sessions" "$(cat "$r/cwk-sessions/builds/b.md" 2>/dev/null)" "v2 build"

echo "migrate-sessions: both legacy names present merge into one folder, nothing overwritten"
r="$TMP/both"; rm -rf "$r"; mkdir -p "$r/spec-kit-sessions/answers" "$r/namht-sessions/answers"
printf 'v1\n' > "$r/spec-kit-sessions/answers/_journal.md"
printf 'v2\n' > "$r/namht-sessions/answers/_journal.md"
printf 'only v2\n' > "$r/namht-sessions/answers/n.md"
"$SCRIPT" "$r" >/dev/null 2>&1
check "oldest name renamed first"     "$(cat "$r/cwk-sessions/answers/_journal.md" 2>/dev/null)" "v1"
check "newer legacy file carried"     "$(cat "$r/cwk-sessions/answers/n.md" 2>/dev/null)" "only v2"
check "namht-sessions left in place (its journal could not merge)" "$([ -f "$r/namht-sessions/answers/_journal.md" ] && echo yes || echo no)" yes

echo "migrate-sessions: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
