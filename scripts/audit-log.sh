#!/usr/bin/env bash
# audit-log.sh — append one JSON line per notable kit action, so a security team can answer
# "what was scanned, reviewed or exported, by whom, on which commit" without asking anyone.
#
#   scripts/audit-log.sh <action> [key=value ...]
#   scripts/audit-log.sh kb.export repo=https://github.com/acme/api commit=9f2c1ab hub=/srv/kb-hub
#
# Destination: ${CWK_AUDIT_LOG:-$HOME/.claude/cwk-audit.jsonl}. CWK_AUDIT_LOG=off disables it.
# Every line carries: ts (ISO-8601 UTC), user ($USER), host (hostname -s), action, cwd, plus the
# key=value pairs given. Ship it with `tail -F` or a cron copy — see docs/company-setup-guide.html.
#
# What it never records: command text, file contents, tokens. A value that looks like a URL with
# credentials (https://user:pass@host/…) is redacted to https://host/… before it is written.
#
# It NEVER fails the caller: a missing directory, a read-only home, a missing jq — every error path
# exits 0 silently. An audit line is worth having; a scan aborted because the log could not be
# written is not.
set -u

log="${CWK_AUDIT_LOG:-$HOME/.claude/cwk-audit.jsonl}"
case "$log" in off|OFF|0|"") exit 0 ;; esac
action="${1:-}"; [ -n "$action" ] || exit 0
shift

ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "")
user="${USER:-$(id -un 2>/dev/null || echo unknown)}"
host=$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo unknown)
cwd=$(pwd -P 2>/dev/null || echo "")

# https://user:token@host/… → https://host/…  (the only secret-shaped thing a caller passes by accident)
redact() { printf '%s' "$1" | sed -E 's#(https?://)[^/@[:space:]]+@#\1#g'; }

# key=value → parallel arrays. A key is [A-Za-z0-9_.-]; anything else, or an arg without '=', is dropped.
keys=(); vals=()
for kv in "$@"; do
  case "$kv" in *=*) ;; *) continue ;; esac
  k="${kv%%=*}"; v="${kv#*=}"
  case "$k" in ''|*[!A-Za-z0-9_.-]*) continue ;; esac
  keys+=("$k"); vals+=("$(redact "$v")")
done

if command -v jq >/dev/null 2>&1; then
  pairs=()
  for i in "${!keys[@]}"; do pairs+=("${keys[$i]}" "${vals[$i]}"); done
  line=$(jq -cn --arg ts "$ts" --arg user "$user" --arg host "$host" --arg action "$action" --arg cwd "$cwd" \
    '{ts:$ts,user:$user,host:$host,action:$action,cwd:$cwd}
     + ($ARGS.positional | [range(0; length; 2) as $i | {key: .[$i], value: .[$i+1]}] | from_entries)' \
    --args "${pairs[@]+"${pairs[@]}"}" 2>/dev/null) || line=""
else
  # Minimal escaper for a machine without jq: backslash, double quote, newline → \n; tabs become a
  # space; every other control character is dropped. Enough for the values this kit passes.
  esc() {
    printf '%s' "$1" | tr '\011' ' ' | tr -d '\000-\010\013-\037\177' \
      | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | awk 'NR>1{printf "\\n"} {printf "%s",$0}'
  }
  line="{\"ts\":\"$(esc "$ts")\",\"user\":\"$(esc "$user")\",\"host\":\"$(esc "$host")\",\"action\":\"$(esc "$action")\",\"cwd\":\"$(esc "$cwd")\""
  for i in "${!keys[@]}"; do line="$line,\"$(esc "${keys[$i]}")\":\"$(esc "${vals[$i]}")\""; done
  line="$line}"
fi
[ -n "$line" ] || exit 0

{
  umask 077
  mkdir -p "$(dirname "$log")"
  [ -e "$log" ] || : > "$log"
  chmod 0600 "$log"
  printf '%s\n' "$line" >> "$log"
} 2>/dev/null || true
exit 0
