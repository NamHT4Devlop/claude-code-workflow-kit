#!/usr/bin/env bash
# schedule.test.sh — schedule.sh edits the user's crontab, a persistent system setting, and had zero
# tests. The failure that matters is silent: a job for another repo disappearing without a word.
#
# The real `crontab` is never touched — a stub earlier on PATH reads/writes a file instead.
set -uo pipefail
cd "$(dirname "$0")/.."
SCHED="$PWD/scripts/schedule.sh"
pass=0; fail=0
ok()   { echo "  ✓ $1"; pass=$((pass+1)); }
bad()  { echo "  ✗ $1"; fail=$((fail+1)); }
check(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (want '$3', got '$2')"; fi; }

# canonicalise: $TMPDIR ends with a slash on macOS, so the raw mktemp path can contain `//` while
# schedule.sh stores the `cd && pwd` form — the two would never compare equal in an assertion.
TMP=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/schedule-test.XXXXXX")" && pwd); trap 'rm -rf "$TMP"' EXIT
export FAKE_CRONTAB="$TMP/crontab.txt"
: > "$FAKE_CRONTAB"

# --- crontab stub: `crontab -l` prints the file, `crontab -` replaces it -----------
mkdir -p "$TMP/bin"
cat > "$TMP/bin/crontab" <<'STUB'
#!/usr/bin/env bash
case "${1:-}" in
  -l) cat "$FAKE_CRONTAB" ;;
  -)  cat > "$FAKE_CRONTAB" ;;
  *)  exit 2 ;;
esac
STUB
chmod +x "$TMP/bin/crontab"
# a real `claude` must resolve too (schedule.sh needs an absolute path for cron)
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/bin/claude"; chmod +x "$TMP/bin/claude"
export PATH="$TMP/bin:$PATH"

mkdir -p "$TMP/api" "$TMP/api-v2"
# grep -c already prints 0 when it finds nothing (and exits 1) — an `|| echo 0` would print it twice.
lines() { grep -c "cwk-kit" "$FAKE_CRONTAB" 2>/dev/null; true; }

echo "schedule: add writes one tagged line"
"$SCHED" add rescan "0 7 * * 1" "$TMP/api" --yes >/dev/null 2>&1
check "one entry"        "$(lines)" 1
check "tag names the repo" "$(grep -c "cwk-kit:rescan:$TMP/api\$" "$FAKE_CRONTAB")" 1

echo "schedule: a prefix-sibling repo is a DIFFERENT job (the bug this file exists for)"
"$SCHED" add rescan "0 8 * * 1" "$TMP/api-v2" --yes >/dev/null 2>&1
check "two entries now"  "$(lines)" 2
# adding /api again must replace ONLY /api — an unanchored match would eat api-v2
"$SCHED" add rescan "0 9 * * 1" "$TMP/api" --yes >/dev/null 2>&1
check "still two entries after re-add" "$(lines)" 2
check "api-v2 survived"  "$(grep -c "cwk-kit:rescan:$TMP/api-v2\$" "$FAKE_CRONTAB")" 1
check "api was replaced" "$(grep -c '^0 9 ' "$FAKE_CRONTAB")" 1

echo "schedule: removing /api leaves /api-v2 alone"
"$SCHED" remove rescan "$TMP/api" --yes >/dev/null 2>&1
check "one entry left"   "$(lines)" 1
check "the survivor is api-v2" "$(grep -c "cwk-kit:rescan:$TMP/api-v2\$" "$FAKE_CRONTAB")" 1

echo "schedule: unrelated cron lines are never touched"
printf '@daily /usr/local/bin/backup.sh\n' >> "$FAKE_CRONTAB"
"$SCHED" add drift "0 8 1 * *" "$TMP/api" --yes >/dev/null 2>&1
check "backup line intact" "$(grep -c 'backup.sh' "$FAKE_CRONTAB")" 1
"$SCHED" remove drift "$TMP/api" --yes >/dev/null 2>&1
check "backup line still intact" "$(grep -c 'backup.sh' "$FAKE_CRONTAB")" 1

echo "schedule: removing the last entry does not abort under set -e"
: > "$FAKE_CRONTAB"
"$SCHED" add rescan "0 7 * * 1" "$TMP/api" --yes >/dev/null 2>&1
"$SCHED" remove rescan "$TMP/api" --yes >/dev/null 2>&1
check "exit 0"           "$?" 0
check "no entries left"  "$(lines)" 0

echo "schedule: percent signs are escaped for crontab(5)"
: > "$FAKE_CRONTAB"
"$SCHED" add splunk "30 8 * * *" "$TMP/api" --yes -- 'index=app earliest=-1d@d%2B7h' >/dev/null 2>&1
check "raw % never reaches the file" "$(grep -c '[^\\]%' "$FAKE_CRONTAB")" 0
check "escaped \\% is there"          "$(grep -c '\\%2B7h' "$FAKE_CRONTAB")" 1

echo "schedule: refuses what it should"
: > "$FAKE_CRONTAB"
"$SCHED" add build "0 7 * * 1" "$TMP/api" --yes >/dev/null 2>&1
check "code-editing skill refused"  "$([ $? -ne 0 ] && echo yes || echo no)" yes
"$SCHED" add rescan "0 7 * *" "$TMP/api" --yes >/dev/null 2>&1
check "4-field schedule refused"    "$([ $? -ne 0 ] && echo yes || echo no)" yes
"$SCHED" add rescan "0 7 * * 1" "$TMP/nope" --yes >/dev/null 2>&1
check "missing repo refused"        "$([ $? -ne 0 ] && echo yes || echo no)" yes
"$SCHED" remove rescan "$TMP/api" --yes >/dev/null 2>&1
check "removing a missing entry refused" "$([ $? -ne 0 ] && echo yes || echo no)" yes
check "nothing was written"         "$(lines)" 0

echo "schedule: a 2.x entry (namht-kit marker) is still ours"
: > "$FAKE_CRONTAB"
printf '0 6 * * 1 cd %s && claude -p /namht-rescan # namht-kit:rescan:%s\n' "$TMP/api" "$TMP/api" >> "$FAKE_CRONTAB"
check "legacy entry is listed"      "$("$SCHED" list 2>/dev/null | grep -c 'namht-kit:rescan')" 1
"$SCHED" add rescan "0 7 * * 1" "$TMP/api" --yes >/dev/null 2>&1
check "add replaced it, no duplicate" "$(grep -c "kit:rescan:$TMP/api\$" "$FAKE_CRONTAB")" 1
check "the survivor carries the new marker" "$(grep -c "# cwk-kit:rescan:$TMP/api\$" "$FAKE_CRONTAB")" 1
printf '0 6 * * 1 cd %s && claude -p /namht-drift # namht-kit:drift:%s\n' "$TMP/api" "$TMP/api" >> "$FAKE_CRONTAB"
"$SCHED" remove drift "$TMP/api" --yes >/dev/null 2>&1
check "remove finds a legacy entry" "$(grep -c "kit:drift:" "$FAKE_CRONTAB")" 0
: > "$FAKE_CRONTAB"

echo "schedule: --dry-run writes nothing"
"$SCHED" add rescan "0 7 * * 1" "$TMP/api" --dry-run >/dev/null 2>&1
check "still empty" "$(lines)" 0

echo "schedule: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
