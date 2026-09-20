#!/usr/bin/env bash
# file-guard.sh — Claude Code PreToolUse hook (Edit · Write · MultiEdit · NotebookEdit · Bash).
#
# The git-guard decides what git and gh may do. Nothing stopped the agent from editing the
# git-guard itself, or settings.json, or ~/.gitconfig, and then doing whatever it liked. This hook
# closes that: the files that define the policy, and the credential stores next to them, cannot be
# written by the agent — not with Edit/Write, and not through a shell command.
#
#   • Edit/Write/MultiEdit/NotebookEdit on a protected path  → BLOCKED
#   • Bash that writes to a protected path                     → BLOCKED: any segment that names a
#     protected path and is not a plain read (cat, grep, jq, diff, ls, …) or that redirects output
#   • reads of the same files                                  → ALLOWED (cat, grep, jq, diff, ls)
#
# Protected: ~/.claude/settings*.json and any project .claude/settings*.json, ~/.claude/hooks/*,
# the directory this hook lives in (the kit's hooks/), managed-settings locations, ~/.gitconfig,
# ~/.config/git/*, any .git/config and .git/hooks/*, ~/.ssh/*, ~/.aws/*, ~/.config/gh/*, ~/.netrc,
# and the audit log.
#
# Same limits as the git-guard: it reads the text of one tool call. A script file it is asked to
# run is opaque to it. Fails closed without jq.

input=$(cat)

if ! command -v jq >/dev/null 2>&1; then
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"🚫 cwk file-guard cannot run: jq is not installed, so the tool call cannot be read. Install jq -- the guard fails closed rather than open."}}\n'
  exit 0
fi

tool=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$cwd" ] && cwd=$PWD
HOME_DIR=${HOME:-/nonexistent}
SELF_DIR=$(cd "$(dirname "$(readlink "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")")" 2>/dev/null && pwd -P)

# Collapse //, ./ and ../ so paths compare as strings. Applied to HOME, cwd and the hook's own
# directory too: a TMPDIR ending in "/" once gave HOME a double slash that no pattern matched.
squash() {
  local out="" part; local IFS='/'
  for part in $1; do
    case "$part" in ''|'.') ;; '..') out=${out%/*};; *) out="$out/$part";; esac
  done
  printf '%s' "${out:-/}"
}
HOME_DIR=$(squash "$HOME_DIR"); cwd=$(squash "$cwd"); [ -n "$SELF_DIR" ] && SELF_DIR=$(squash "$SELF_DIR")

# ── audit log (shared shape with git-guard; never the command text) ─────────
audit() { # <decision> <reason>
  local log=${CWK_AUDIT_LOG:-$HOME_DIR/.claude/cwk-audit.jsonl}
  [ "$log" = off ] && return 0
  mkdir -p "$(dirname "$log")" 2>/dev/null || return 0
  [ -f "$log" ] || { : > "$log" 2>/dev/null && chmod 600 "$log" 2>/dev/null; }
  jq -cn --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg user "${USER:-}" --arg host "$(hostname -s 2>/dev/null)" \
     --arg tool "$tool" --arg decision "$1" --arg reason "$2" --arg cwd "$cwd" \
     '{ts:$ts,user:$user,host:$host,guard:"file-guard",tool:$tool,decision:$decision,reason:$reason,cwd:$cwd}' >> "$log" 2>/dev/null || true
}

deny() {
  audit deny "$1"
  local msg="🚫 cwk file-guard blocked this: $1
The files that hold the guard policy and credentials (settings.json, the hooks, ~/.gitconfig, .git/config, ~/.ssh, ~/.aws, ~/.config/gh) cannot be written by the agent. Reading them is fine. Need a change → make it yourself."
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' \
    "$(printf '%s' "$msg" | jq -Rs .)"
  exit 0
}

set -f

# Expand ~ and $HOME, make absolute against cwd, and collapse ./ and ../ without touching the disk
# (the target may not exist yet — a Write creates it).
canon() {
  local p=$1
  p=${p//\$HOME/$HOME_DIR}; p=${p//\$\{HOME\}/$HOME_DIR}
  case "$p" in "~"|"~/"*) p="$HOME_DIR${p#\~}";; esac
  case "$p" in /*) ;; *) p="$cwd/$p";; esac
  squash "$p"
}

# Is this (canonical) path protected? Directories protect everything under them.
protected() {
  local p=$1
  case "$p" in
    "$HOME_DIR"/.claude/settings.json|"$HOME_DIR"/.claude/settings.local.json) return 0;;
    "$HOME_DIR"/.claude/hooks|"$HOME_DIR"/.claude/hooks/*) return 0;;
    "$HOME_DIR"/.claude/cwk-audit.jsonl) return 0;;
    */.claude/settings.json|*/.claude/settings.local.json) return 0;;
    "/Library/Application Support/ClaudeCode"|"/Library/Application Support/ClaudeCode/"*|/etc/claude-code|/etc/claude-code/*) return 0;;
    "$HOME_DIR"/.gitconfig|"$HOME_DIR"/.config/git|"$HOME_DIR"/.config/git/*) return 0;;
    */.git/config|*/.git/hooks|*/.git/hooks/*) return 0;;
    "$HOME_DIR"/.ssh|"$HOME_DIR"/.ssh/*|"$HOME_DIR"/.aws|"$HOME_DIR"/.aws/*) return 0;;
    "$HOME_DIR"/.config/gh|"$HOME_DIR"/.config/gh/*|"$HOME_DIR"/.netrc) return 0;;
  esac
  if [ -n "$SELF_DIR" ]; then
    case "$p" in "$SELF_DIR"|"$SELF_DIR"/*) return 0;; esac
  fi
  # The audit log may live elsewhere.
  [ -n "${CWK_AUDIT_LOG:-}" ] && [ "$CWK_AUDIT_LOG" != off ] && [ "$p" = "$(canon "$CWK_AUDIT_LOG")" ] && return 0
  return 1
}

# ── file tools ──────────────────────────────────────────────────────────────
case "$tool" in
  Edit|Write|MultiEdit|NotebookEdit)
    fp=$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null)
    [ -z "$fp" ] && exit 0
    protected "$(canon "$fp")" && deny "$tool on protected file $(canon "$fp")"
    exit 0;;
  Bash) ;;
  *) exit 0;;
esac

# ── Bash ────────────────────────────────────────────────────────────────────
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$cmd" ] && exit 0
# cheap pre-filter: nothing protected is mentioned
printf '%s' "$cmd" | grep -qE '\.claude|\.gitconfig|\.git/(config|hooks)|\.ssh|\.aws|\.config/(gh|git)|\.netrc|ClaudeCode|claude-code|cwk-audit|hooks/' || exit 0

# Strip quoting/grouping chars from a token for classification.
unq() {
  local t=$1 bt='`'
  t=${t//\"/}; t=${t//\'/}; t=${t//\\/}; t=${t//$bt/}; t=${t//\(/}; t=${t//\)/}
  printf '%s' "$t"
}

# Quote-aware tokeniser, segments split on unquoted ; && || | & and newlines (same as git-guard).
TOK=(); SEGOF=()
tokenise() {
  local s=$1 i=0 n=${#1} ch cur="" q="" seg=0 have=0
  flush() { if [ "$have" -eq 1 ]; then TOK+=("$cur"); SEGOF+=("$seg"); fi; cur=""; have=0; }
  while [ $i -lt $n ]; do
    ch=${s:i:1}
    if [ -n "$q" ]; then
      if [ "$ch" = "$q" ]; then q=""; cur+=$ch
      elif [ "$q" = '"' ] && [ "$ch" = '\' ] && [ $((i+1)) -lt $n ]; then cur+="$ch${s:i+1:1}"; i=$((i+1))
      else cur+=$ch; fi
      have=1; i=$((i+1)); continue
    fi
    case "$ch" in
      \'|\") q=$ch; cur+=$ch; have=1;;
      \\) if [ $((i+1)) -lt $n ]; then cur+="$ch${s:i+1:1}"; have=1; i=$((i+1)); fi;;
      ' '|$'\t') flush;;
      $'\n'|';') flush; seg=$((seg+1));;
      '|'|'&') flush; seg=$((seg+1)); [ "${s:i+1:1}" = "$ch" ] && i=$((i+1));;
      *) cur+=$ch; have=1;;
    esac
    i=$((i+1))
  done
  flush
}
tokenise "$cmd"
NTOK=${#TOK[@]}

# Commands that only read. Anything else that names a protected path is a write until proven
# otherwise; so is any segment with output redirection.
READ_ONLY_RE='^(cat|less|more|head|tail|grep|egrep|fgrep|rg|ugrep|ls|stat|file|wc|diff|cmp|jq|yq|md5sum|md5|shasum|sha256sum|realpath|readlink|test|\[|bat|cut|sort|uniq|tr|od|xxd|hexdump|strings|du|basename|dirname|echo|printf|type|which|command|true|:|env|printenv|pwd)$'
LAUNCHER_RE='^(sudo|env|command|nohup|time|exec|xargs|nice|ionice|timeout|stdbuf|doas)$'

i=0
while [ $i -lt $NTOK ]; do
  seg=${SEGOF[$i]}
  toks=(); while [ $i -lt $NTOK ] && [ "${SEGOF[$i]}" = "$seg" ]; do toks+=("${TOK[$i]}"); i=$((i+1)); done
  n=${#toks[@]}; [ "$n" -eq 0 ] && continue

  # a cd/pushd here changes where the NEXT segments' relative paths resolve
  case "$(unq "${toks[0]}")" in
    cd|pushd) if [ "$n" -ge 2 ]; then cwd=$(canon "$(unq "${toks[1]}")"); else cwd=$HOME_DIR; fi; continue;;
  esac

  # which protected paths does this segment name?
  hit=""
  redirect=0
  for t in "${toks[@]}"; do
    u=$(unq "$t")
    case "$u" in
      \>*|\>\>*|[0-9]\>*|\&\>*) redirect=1; u=${u#*>}; u=${u#>}; u=${u#>}; [ -z "$u" ] && continue;;
    esac
    case "$u" in -*) continue;; esac
    case "$u" in *"="*) u=${u#*=};; esac
    [ -z "$u" ] && continue
    c=$(canon "$u")
    protected "$c" && hit=$c
  done
  [ -z "$hit" ] && continue

  # first command word, skipping launchers and VAR=… prefixes
  k=0; cmdword=""
  while [ $k -lt $n ]; do
    w=$(unq "${toks[$k]}"); w=${w##*/}
    case "$w" in *=*) k=$((k+1)); continue;; esac
    if [[ $w =~ $LAUNCHER_RE ]]; then k=$((k+1)); continue; fi
    cmdword=$w; break
  done

  [ "$redirect" -eq 1 ] && deny "shell output redirected into protected file $hit"
  if [[ $cmdword =~ $READ_ONLY_RE ]]; then
    # readers that can still write: sed -i, awk -i, find -delete/-exec, jq with a file target is fine
    continue
  fi
  case "$cmdword" in
    sed|gsed) for t in "${toks[@]}"; do case "$(unq "$t")" in -i*|--in-place*) deny "sed -i on protected file $hit";; esac; done; continue;;
    awk|gawk) for t in "${toks[@]}"; do case "$(unq "$t")" in -i|--in-place|inplace) deny "awk in-place on protected file $hit";; esac; done; continue;;
    find) for t in "${toks[@]}"; do case "$(unq "$t")" in -delete|-exec|-execdir|-ok|-okdir) deny "find $(unq "$t") under protected path $hit";; esac; done; continue;;
    git) continue;;   # git's own writes are the git-guard's business
  esac
  deny "'$cmdword' on protected file $hit (only reads are allowed there)"
done

exit 0
