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
#   * A headless `claude -p` cannot answer an approval prompt and, in the default mode, refuses every
#     write — so a scheduled rescan could never save the KB. rescan and drift therefore get exactly
#     the writes they need and nothing more: Edit/Write under knowledge-base/ (rescan only) and
#     cwk-sessions/, plus read-only git. Not acceptEdits — that would let an unattended run, reading
#     other people's diffs and commit messages, edit your source. splunk stays in the default mode.
#   * cron's PATH has no /opt/homebrew/bin or nvm, and `claude` is a node script, so the line
#     carries the directories of claude, node, git, jq and provenlens — not the whole interactive
#     PATH: macOS cron cuts a command at 1000 bytes, and a cut line never runs (it refuses those).
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
    -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
    *) args+=("$a") ;;
  esac
done
set -- "${args[@]:-}"

die() { echo "✗ $*" >&2; exit 1; }
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Quote for /bin/sh, which cron runs the line with: POSIX single quotes, a ' written as '\''.
# Not printf %q — bash 3.2 renders a non-ASCII path as $'…', which dash (cron's sh on Debian) rejects.
sq() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }

# Our lines for $name/$repo, or with -v every OTHER line. The tag sits at END OF LINE and is compared
# there as a plain string: a substring match makes /x/api's tag hit /x/api-v2's line, and a regex
# built from the path breaks on ( + | — `a|b` even matched other repos' lines. Both markers count
# (2.x wrote namht-kit), and % is compared escaped, the way the line was written (see below).
ours() {
  local r; r=${repo//%/\\%}
  CWK_T1="# cwk-kit:$name:$r" CWK_T2="# namht-kit:$name:$r" CWK_V="${1:-}" awk '
    function ends(s, t) { return length(s) >= length(t) && substr(s, length(s) - length(t) + 1) == t }
    { m = ends($0, ENVIRON["CWK_T1"]) || ends($0, ENVIRON["CWK_T2"]) }
    (ENVIRON["CWK_V"] == "-v") != m'
}

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
  current=$(crontab -l 2>/dev/null || true)
  # anchored, plain-string match on the tag — see ours()
  hit=$(echo "$current" | ours)
  [ -n "$hit" ] || die "no entry for '$name' in $repo"
  new=$(echo "$current" | ours -v)
  echo "Will remove:"; echo "$hit" | sed 's/^/  - /'
  if [ "$DRY" = 1 ]; then echo "(dry run — nothing written)"; exit 0; fi
  if [ "$YES" != 1 ]; then printf 'Write this crontab? [y/N] '; read -r ans; [ "$ans" = y ] || [ "$ans" = Y ] || die "aborted"; fi
  printf '%s\n' "$new" | crontab -
  echo "✔ removed"
  [ -f "$HERE/audit-log.sh" ] && bash "$HERE/audit-log.sh" schedule.remove "preset=$name" "repo=$repo" || true
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
# The writes each job needs, and read-only git — see the header.
GIT_RO='Bash(git diff:*),Bash(git log:*),Bash(git status:*),Bash(git rev-parse:*),Bash(git show:*)'
perm=""
case "$name" in
  rescan) perm=" --permission-mode default --allowedTools $(sq "Read,Grep,Glob,Edit(knowledge-base/**),Write(knowledge-base/**),Edit(cwk-sessions/**),Write(cwk-sessions/**),$GIT_RO")" ;;
  drift)  perm=" --permission-mode default --allowedTools $(sq "Read,Grep,Glob,Edit(cwk-sessions/**),Write(cwk-sessions/**),$GIT_RO")" ;;
esac
# cron gives you a bare environment: cd into the repo, carry a PATH that finds the tools, use the
# absolute binary, append to a log.
cron_path=""
for b in "$claude_bin" node git jq provenlens; do
  p=$(command -v "$b" 2>/dev/null) || continue
  d=$(dirname "$p"); case ":$cron_path:" in *":$d:"*) ;; *) cron_path="${cron_path:+$cron_path:}$d" ;; esac
done
for d in /opt/homebrew/bin /usr/local/bin /usr/bin /bin /usr/sbin /sbin; do
  [ -d "$d" ] || continue; case ":$cron_path:" in *":$d:"*) ;; *) cron_path="$cron_path:$d" ;; esac
done
line="$sched cd $(sq "$repo") && PATH=$(sq "$cron_path") $(sq "$claude_bin")$perm -p $(sq "$prompt") >> $(sq "$log") 2>&1 $tag"
# cron treats an unescaped % as a newline and feeds the remainder to the command on stdin,
# so a Splunk window like `earliest=-1d@d%2B7h` would silently truncate the scheduled command.
# Shell quoting is not crontab(5) quoting — escape percent signs separately.
line=${line//%/\\%}
# macOS cron reads at most 1000 bytes of command; the rest is cut, the quoting breaks and the job
# never runs — silently, since the log redirect is cut too.
cmd_bytes=$(printf '%s' "${line#"$sched "}" | wc -c | tr -d ' ')
[ "$cmd_bytes" -lt 1000 ] || die "the cron line would be $cmd_bytes bytes; cron cuts a command at 1000, and a cut line never runs. Shorten the repo path or the skill arguments."

current=$(crontab -l 2>/dev/null || true)
old=$(echo "$current" | ours)
if [ -n "$old" ]; then
  echo "Replacing the existing entry for '$name' in $repo:"
  echo "$old" | sed 's/^/  - /'
  current=$(echo "$current" | ours -v)
fi
echo "Will add:"; echo "  + $line"
echo
echo "Notes:"
echo "  · output goes to $log (create the folder if it doesn't exist: mkdir -p \"$(dirname "$log")\")"
echo "  · an unattended run cannot answer a permission prompt — a skill needing one will just fail in the log"
if [ -n "$perm" ]; then
  echo "    ($slash may write only its own output — knowledge-base/ for rescan, cwk-sessions/ — and read git; nothing else)"
else
  echo "    ($slash runs in the default mode: allow its MCP tools and its save to cwk-sessions/ in your settings)"
fi
echo "  · the line carries the folders of claude, node, git, jq and provenlens — re-run add if you move them"
echo "  · on macOS, cron may need Full Disk Access (System Settings ▸ Privacy & Security) to read your repo"

if [ "$DRY" = 1 ]; then echo; echo "(dry run — nothing written)"; exit 0; fi
if [ "$YES" != 1 ]; then printf '\nWrite this to your crontab? [y/N] '; read -r ans; [ "$ans" = y ] || [ "$ans" = Y ] || die "aborted"; fi

mkdir -p "$(dirname "$log")"
printf '%s\n%s\n' "$current" "$line" | grep -v '^$' | crontab -
echo "✔ scheduled — check it with: scripts/schedule.sh list"
# Audit trail: a crontab entry is a standing, unattended run — record who installed it, for what.
[ -f "$HERE/audit-log.sh" ] && bash "$HERE/audit-log.sh" schedule.install "preset=$name" "repo=$repo" "cron=$sched" || true
