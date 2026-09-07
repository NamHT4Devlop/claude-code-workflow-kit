#!/usr/bin/env bash
# kb-pipeline.test.sh — kb-pipeline.sh spends real money: every step it runs is a `claude -p` over
# someone's repository. The failures that matter are silent ones — redoing a scan that was already
# done, or running anything at all under --dry-run. Stubs stand in for claude and provenlens so the
# decisions can be exercised without a single token.
set -uo pipefail
cd "$(dirname "$0")/.."
PIPE="$PWD/scripts/kb-pipeline.sh"
pass=0; fail=0
ok()   { echo "  ✓ $1"; pass=$((pass+1)); }
bad()  { echo "  ✗ $1"; fail=$((fail+1)); }
check(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (want '$3', got '$2')"; fi; }

TMP=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/kb-pipeline.XXXXXX")" && pwd); trap 'rm -rf "$TMP"' EXIT
export CALLS="$TMP/calls.log"; : > "$CALLS"

# --- stubs: record what would have been spent, do nothing else --------------------
mkdir -p "$TMP/bin"
for t in claude provenlens; do
  printf '#!/usr/bin/env bash\necho "%s $*" >> "$CALLS"\nexit 0\n' "$t" > "$TMP/bin/$t"
  chmod +x "$TMP/bin/$t"
done
export PATH="$TMP/bin:$PATH"

mk_repo() {  # $1 name, $2… which outputs already exist
  local r="$TMP/$1"; rm -rf "$r"; mkdir -p "$r"; printf 'class A {}\n' > "$r/A.java"
  shift
  for have in "$@"; do
    case "$have" in
      kb)      mkdir -p "$r/knowledge-base"; printf '# x\n' > "$r/knowledge-base/01-x.md";;
      runbook) mkdir -p "$r/cwk-sessions/runbook"; printf '# rb\n' > "$r/cwk-sessions/runbook/r.md";;
      map)     mkdir -p "$r/cwk-sessions/maps"; printf '<html></html>\n' > "$r/cwk-sessions/maps/m.html";;
      index)   mkdir -p "$r/.provenlens";;
    esac
  done
  echo "$r"
}
calls() { grep -c "$1" "$CALLS" 2>/dev/null; true; }

echo "kb-pipeline: --dry-run spends nothing"
r=$(mk_repo dry)
"$PIPE" --dry-run --hub "$TMP/hub" "$r" >/dev/null 2>&1
check "no claude invocation"     "$(calls '^claude')" 0
check "no provenlens invocation" "$(calls '^provenlens')" 0
check "no hub written"           "$([ -e "$TMP/hub" ] && echo yes || echo no)" no

echo "kb-pipeline: a step whose output exists is skipped, not redone"
r=$(mk_repo done-already kb runbook map index)
out=$("$PIPE" --dry-run --hub "$TMP/hub" "$r" 2>&1)
check "nothing left to do" "$(printf '%s' "$out" | grep -c '(nothing to do)')" 1
r=$(mk_repo partial kb index)
out=$("$PIPE" --dry-run --hub "$TMP/hub" "$r" 2>&1)
check "scan skipped when a KB exists"   "$(printf '%s' "$out" | grep -c 'would: claude -p /cwk-scan')" 0
check "runbook still queued"            "$(printf '%s' "$out" | grep -c 'would: claude -p /cwk-runbook')" 1

echo "kb-pipeline: --force redoes what is already there"
out=$("$PIPE" --dry-run --force --hub "$TMP/hub" "$r" 2>&1)
check "scan queued again" "$(printf '%s' "$out" | grep -c 'would: claude -p /cwk-scan')" 1

echo "kb-pipeline: the depth is validated before anything runs"
"$PIPE" --depth exhaustive --yes --hub "$TMP/hub" "$r" >/dev/null 2>&1
check "bad depth refused"    "$([ $? -ne 0 ] && echo yes || echo no)" yes
check "and spent nothing"    "$(calls '^claude')" 0

echo "kb-pipeline: a missing path is reported, never silently skipped"
out=$("$PIPE" --dry-run --hub "$TMP/hub" "$TMP/no-such-repo" 2>&1)
check "named in the output" "$(printf '%s' "$out" | grep -c 'not a directory')" 1

echo "kb-pipeline: it never clones — a URL is not a repo path"
out=$("$PIPE" --dry-run --hub "$TMP/hub" "https://github.com/x/y" 2>&1)
check "URL rejected as a path" "$(printf '%s' "$out" | grep -c 'not a directory')" 1
check "no clone attempted"     "$(grep -c 'clone' "$CALLS" 2>/dev/null; true)" 0

echo "kb-pipeline: a real run spends exactly the queued steps"
r=$(mk_repo real kb)
: > "$CALLS"
"$PIPE" --yes --hub "$TMP/hub2" "$r" >/dev/null 2>&1
check "indexed once"      "$(calls '^provenlens init')" 1
check "no scan (KB there)" "$(calls 'cwk-scan')" 0
check "runbook once"       "$(calls 'cwk-runbook')" 1

echo "kb-pipeline: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
