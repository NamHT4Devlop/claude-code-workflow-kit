#!/usr/bin/env bash
# schedule.sh — run a cwk-* skill on a schedule (cron), for the two that are genuinely periodic:
# the Splunk error digest and keeping a Knowledge Base fresh.
#
#   scripts/schedule.sh list
#   scripts/schedule.sh add rescan  "0 7 * * 1"  /path/to/repo
#   scripts/schedule.sh add drift   "0 8 1 * *"  /path/to/repo
#   scripts/schedule.sh add splunk  "30 8 * * *" /path/to/repo -- "index=app_logs cai_enviroment=prod 24h"
#   scripts/schedule.sh remove rescan /path/to/repo
#
# Flags: --dry-run (print the crontab line, change nothing) · --yes (skip the confirmation prompt)
#
# Design notes, because this edits a persistent system setting:
#   * Every entry this script owns is tagged with a marker comment. It only ever adds or removes
#     ITS OWN lines — your other cron jobs are copied through untouched.
#   * It ALWAYS shows you the resulting change and asks before writing, unless you pass --yes.
#   * It never schedules a skill that edits code. Unattended source edits are not something you
#     should be able to set up by accident.
set -euo pipefail

MARK="# cwk-kit"
# Entries written by 2.x carry the old marker. They are still ours: list them, replace them on add,
# and let remove find them — a job that only the old name can reach is a job nobody can delete.
MARK_RE='# (cwk|namht)-kit'
DRY=0; YES=0; args=()
for a in "$@"; do
  case "$a" in
    --dry-run|-n) DRY=1 ;;
    --yes|-y) YES=1 ;;
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
    *) args+=("$a") ;;
  esac
done
set -- "${args[@]:-}"

die() { echo "✗ $*" >&2; exit 1; }

# preset → the slash command it runs. Read-only skills only, on purpose.
preset_cmd() {
  case "$1" in
    rescan) echo "/cwk-rescan" ;;
    drift)  echo "/cwk-drift" ;;
    splunk) echo "/cwk-splunk-report" ;;
    *) return 1 ;;
  esac
}

cmd=${1:-list}

if [ "$cmd" = "list" ]; then
  echo "Scheduled cwk entries:"
  crontab -l 2>/dev/null | grep -E "$MARK_RE" || echo "  (none)"
  exit 0
fi

name=${2:-}; sched=${3:-}; repo=${4:-}
[ -n "$name" ] || die "which preset? one of: rescan · drift · splunk"
slash=$(preset_cmd "$name") || die "unknown preset '$name' (rescan · drift · splunk). Code-editing skills are deliberately not schedulable."

if [ "$cmd" = "remove" ]; then
  repo=${3:-}
  [ -n "$repo" ] || die "usage: schedule.sh remove <preset> <repo>"
  repo=$(cd "$repo" 2>/dev/null && pwd) || die "no such directory: ${3}"
  tag="$MARK:$name:$repo"
  current=$(crontab -l 2>/dev/null || true)
  # The tag sits at END OF LINE, so match it anchored. A substring match makes the tag for /x/api
  # also match the line for /x/api-v2 — removing or replacing a DIFFERENT repo's job silently.
  tag_re="$MARK_RE:$name:$(printf '%s' "$repo" | sed 's/[][\.^$*\/&]/\\&/g')"
  echo "$current" | grep -qE "${tag_re}\$" || die "no entry for '$name' in $repo"
  new=$(echo "$current" | grep -vE "${tag_re}\$" || true)
  echo "Will remove:"; echo "$current" | grep -E "${tag_re}\$" | sed 's/^/  - /'
  if [ "$DRY" = 1 ]; then echo "(dry run — nothing written)"; exit 0; fi
  if [ "$YES" != 1 ]; then printf 'Write this crontab? [y/N] '; read -r ans; [ "$ans" = y ] || [ "$ans" = Y ] || die "aborted"; fi
  printf '%s\n' "$new" | crontab -
  echo "✔ removed"
  exit 0
fi

[ "$cmd" = "add" ] || die "unknown command '$cmd' (list · add · remove)"
[ -n "$sched" ] || die "missing the cron schedule, e.g. \"0 7 * * 1\" (Mon 07:00)"
[ -n "$repo" ] || die "missing the repo path"
repo=$(cd "$repo" 2>/dev/null && pwd) || die "no such directory: ${4}"
[ "$(echo "$sched" | wc -w | tr -d ' ')" = "5" ] || die "a cron schedule has 5 fields, got: $sched"

# everything after `--` is passed to the skill as its arguments
extra=""
shift 4 2>/dev/null || true
if [ "${1:-}" = "--" ]; then shift; extra="${*:-}"; fi

claude_bin=$(command -v claude || true)
[ -n "$claude_bin" ] || die "the 'claude' CLI is not on PATH — cron needs an absolute path to it"

log="$HOME/.claude/logs/cwk-$name.log"
tag="$MARK:$name:$repo"
prompt="$slash${extra:+ $extra}"
# cron gives you a bare environment: cd into the repo, use the absolute binary, append to a log.
line="$sched cd $(printf '%q' "$repo") && $(printf '%q' "$claude_bin") -p $(printf '%q' "$prompt") >> $(printf '%q' "$log") 2>&1 $tag"
# cron treats an unescaped % as a newline and feeds the remainder to the command on stdin,
# so a Splunk window like `earliest=-1d@d%2B7h` would silently truncate the scheduled command.
# printf %q quotes for the shell, not for crontab(5) — escape percent signs separately.
line=${line//%/\\%}

current=$(crontab -l 2>/dev/null || true)
tag_re="$MARK_RE:$name:$(printf '%s' "$repo" | sed 's/[][\.^$*\/&]/\\&/g')"
if echo "$current" | grep -qE "${tag_re}\$"; then
  echo "Replacing the existing entry for '$name' in $repo:"
  echo "$current" | grep -E "${tag_re}\$" | sed 's/^/  - /'
  # `|| true`: with set -e, a grep that filters away the ONLY line returns 1 and would abort here.
  current=$(echo "$current" | grep -vE "${tag_re}\$" || true)
fi
echo "Will add:"; echo "  + $line"
echo
echo "Notes:"
echo "  · output goes to $log (create the folder if it doesn't exist: mkdir -p \"$(dirname "$log")\")"
echo "  · an unattended run cannot answer a permission prompt — a skill needing one will just fail in the log"
echo "  · on macOS, cron may need Full Disk Access (System Settings ▸ Privacy & Security) to read your repo"

if [ "$DRY" = 1 ]; then echo; echo "(dry run — nothing written)"; exit 0; fi
if [ "$YES" != 1 ]; then printf '\nWrite this to your crontab? [y/N] '; read -r ans; [ "$ans" = y ] || [ "$ans" = Y ] || die "aborted"; fi

mkdir -p "$(dirname "$log")"
printf '%s\n%s\n' "$current" "$line" | grep -v '^$' | crontab -
echo "✔ scheduled — check it with: scripts/schedule.sh list"
