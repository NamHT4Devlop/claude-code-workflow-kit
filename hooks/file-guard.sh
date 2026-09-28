#!/usr/bin/env bash
# file-guard.sh — Claude Code PreToolUse hook (Edit · Write · MultiEdit · NotebookEdit · Bash).
#
# The files that define what the agent may do, and the credential stores next to them, cannot be
# written by the agent — not with Edit/Write, and not through a shell command. Without that, an agent
# could edit settings.json or a hook and then do whatever it liked.
#
#   • Edit/Write/MultiEdit/NotebookEdit on a protected path  → BLOCKED
#   • Bash that writes to a protected path                     → BLOCKED: any segment that names a
#     protected path and is not a plain read (cat, grep, jq, diff, ls, …), and any output
#     redirection (>, >>, >|, &>, <>, N>, glued or not: `x>f`, `1<>f`) whose target is one.
#     Readers that can write count as writers (sed -i, awk -i inplace, yq -i, sort -o, find -delete/
#     -exec), and so does xargs/parallel running a non-read on what an earlier stage of the same
#     pipe named (`echo ~/.claude/settings.json | xargs rm`).
#   • reads of the same files                                  → ALLOWED (cat, grep, jq, diff, ls, a
#     lint by shellcheck, bash -n, uniq with one file), and so are the sources of an archive made or a
#     copy (tar czf /tmp/k.tgz hooks, zip -r x.zip hooks, 7z a, cp/rsync/ditto/scp ~/.ssh/x /tmp/)
#     — not the archive or destination, a written option value (tar -f, rsync --log-file), or an
#     option that deletes or links the sources (tar --remove-files, zip -m, cp -l/-s).
#
# Protected: ~/.claude/settings*.json and any project .claude/settings*.json, ~/.claude/hooks/*,
# ~/.claude.json (it holds the MCP server commands), the directory this hook lives in (the kit's
# hooks/), managed-settings locations, ~/.gitconfig, ~/.config/git/*, any .git/config and
# .git/hooks/*, ~/.ssh/*, ~/.aws/*, ~/.config/gh/*, ~/.netrc, and the audit log. A glob or a brace
# expansion that can expand to one of them, or to a directory above one (~/.c*), names it: every
# {a,b} group, nested ones and {a..z}/{1..9} ranges are expanded (past 256 words, a word whose {
# is outside quotes and mentions a protected name is refused; quoted text and here-document bodies
# are never brace-expanded by the shell, so there it is not).
#
# A here-document's body is data — `cat > f <<'EOF'`, `git commit -m "$(cat <<'EOF' …)"` — and is
# taken out before the command is read; the redirections on its own line are still checked. It is
# read as commands, as before, when something in its pipeline may run it (bash, sh, eval, source,
# xargs, a read loop, patch/git apply, python, node, …, a word built at run time, or a function or
# alias the command defines) or when its delimiter is unquoted and it holds $( or a backquote. A
# body fed only to a non-shell interpreter (python, node, ruby, …) is not globbed or brace-expanded.
# Where a body inside $( ) could end that $( ) early for bash 3.2, or anything else cannot be
# followed, the command is read whole. A command over 64 KB (bodies out) is not taken apart: its
# redirections are checked and it is refused if it names a protected path at all.
#
# Words are read as the shell reads them: quotes and backslashes are removed and $'\x2e' is
# decoded (~/.cl'a'ude, ~/$'.claude', .claud\e are ~/.claude); `\`+newline joins; ;, &&, ||, |, &
# and newlines end a command, and what precedes the command itself is stepped over — ! { } ( ),
# if/then/elif/else/fi, while/until/do/done, time [-p], `case W in` and a case pattern `x)`, a
# function header `f()`, redirections, and a `for NAME in LIST` / `select` header (the list is
# data; a later command handed $NAME is judged as if handed the protected path the list named) —
# so `if cd ~/.claude; then rm settings.json; fi` is followed. cd, pushd, `builtin cd` and `command
# cd` move where later relative paths resolve, and so does a `$(cd X …` / `cd X` inside backquotes
# (its later words are checked against X too). A
# command word built at run time ($(which rm), $RM, {rm,-rf,x}, /bin/r?) is not trusted to read.
#
# A .claude/ directory itself is blocked only where it is what gets removed or replaced: rm/rmdir/
# trash of it, mv to or from it, a copy INTO it (cp/rsync/ditto/ln/install) that is recursive or
# brings settings*.json or hooks (a glob or brace source that can match them — tpl/*,
# tpl/{settings,x}.json — counts), `cp -R x/.claude ~` over it, tar/unzip extracting into it
# (-C/-d), wget -P or curl --output-dir into it, find … -delete/-exec naming it (bar `-name .claude
# -prune -o …`, where the action is on the other branch), and a command word built at run time.
# Naming it otherwise is fine (ls, rsync --exclude .claude, a copy out of it).
#
# git is not policed as git (since 4.0.0 the kit restricts no git command), and git's own files
# (~/.gitconfig, ~/.config/git, .git/config, .git/hooks) stay writable through it. When a git
# command names another protected path or a .claude dir, git may not be the way to rewrite it:
# --work-tree, GIT_WORK_TREE=/GIT_DIR= and -c core.worktree pointing there, --output, config --file
# onto it, and checkout, switch, restore (bar --staged), rm (bar --cached), mv, stash, apply, am,
# merge, pull, rebase, cherry-pick, revert, reset --hard, clean, clone, checkout-index, merge-file,
# read-tree are blocked there. add, diff, log, show, commit stay allowed. `git -C <dir>` resolves
# the paths after it against <dir>; a work tree given by --work-tree, GIT_WORK_TREE or
# core.worktree resolves the pathspecs against it too, and when it holds a protected path (~, /,
# an ancestor of the kit) those same rewriting subcommands are blocked whatever the pathspec.
#
# Last check: when everything above allowed the command, its text is normalised once more (quotes
# and backslashes dropped, $'…' decoded); if that names a protected path more often than the text
# as written does — the name was assembled through quoting — or a word with a {x..y} range or two
# brace groups names one, it is refused: write the path plainly.
#
# On macOS paths and command names compare case-insensitively, as the filesystem does; option
# letters stay case-sensitive (tar -x is not -X, git restore -S is not -s).
#
# Its limit: it is a guard against accidents and planted instructions, not a sandbox. Claude Code's
# permission mode is the real boundary. It reads the text of one tool call: a script file it is
# asked to run is opaque to it — including one a here-document writes and a later command of the
# same call runs (`cat > x.sh <<'EOF' … EOF; bash x.sh`) — and a path assembled at run time (a
# variable other than $HOME or a for-loop's, command substitution) is not resolved; a here-document
# fed to a program that runs its stdin but is not on the list above is read as data. What still
# gets through: the string an interpreter or eval runs (bash -c, python -c/-e, node -e, eval, and
# echo "$(cat <<'EOF' … EOF)" | bash) when it names only a .claude dir
# (a protected file named inside such a string is still caught); a symlink made in one command
# and written through in another; find by -name/-path without the protected directory in its
# start path; removers and copiers it does not know (busybox rm, srm, shred -u, perl -e unlink, …)
# on a .claude dir; and a working directory changed by other means (env -C, sudo -D, a subshell's
# cd leaking back out is assumed). Fails closed without jq.

input=$(cat)
# Byte-wise strings: in a UTF-8 locale every ${s:i:1} rescans the command from its start.
LC_ALL=C

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
# Like unq and canon it sets a variable (SQ) instead of printing: a $(…) per word forks, and a
# heredoc is thousands of words.
squash() {
  local out="" part; local IFS='/'
  for part in $1; do
    case "$part" in ''|'.') ;; '..') out=${out%/*};; *) out="$out/$part";; esac
  done
  SQ=${out:-/}
}
squash "$HOME_DIR"; HOME_DIR=$SQ; squash "$cwd"; cwd=$SQ; [ -n "$SELF_DIR" ] && { squash "$SELF_DIR"; SELF_DIR=$SQ; }

# macOS volumes are case-insensitive by default: ~/.Claude/Settings.json IS ~/.claude/settings.json,
# and RM is rm. There paths and command names match under nocasematch (case, [[ == ]] and =~);
# option letters must not, so flag parsing switches it off (flags) and back (names).
FOLD=0; case "${OSTYPE:-}" in darwin*) FOLD=1;; esac
names() { [ "$FOLD" -eq 0 ] || shopt -s nocasematch; }
flags() { shopt -u nocasematch; }
names

# ── audit log (one JSON line per deny; never the command text) ─────────────
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

# Expand ~ and $HOME, make absolute against cwd (or <base>), and collapse ./ and ../ without
# touching the disk (the target may not exist yet — a Write creates it). Sets C.
canon() { # <path> [base]
  local p=$1
  p=${p//\$HOME/$HOME_DIR}; p=${p//\$\{HOME\}/$HOME_DIR}
  case "$p" in "~"|"~/"*) p="$HOME_DIR${p#\~}";; esac
  case "$p" in /*) ;; *) p="${2:-$cwd}/$p";; esac
  case "$p" in *//*|*/./*|*/../*|*/.|*/..|*?/) squash "$p"; C=$SQ;; *) C=$p;; esac
}

# The audit log may live elsewhere.
AUDIT_C=""; if [ -n "${CWK_AUDIT_LOG:-}" ] && [ "$CWK_AUDIT_LOG" != off ]; then canon "$CWK_AUDIT_LOG"; AUDIT_C=$C; fi

# Is this (canonical) path protected? Directories protect everything under them.
protected() {
  case "$1" in
    "$HOME_DIR"/.claude/settings.json|"$HOME_DIR"/.claude/settings.local.json|"$HOME_DIR"/.claude.json) return 0;;
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
    case "$1" in "$SELF_DIR"|"$SELF_DIR"/*) return 0;; esac
  fi
  [ -n "$AUDIT_C" ] && [[ $1 == "$AUDIT_C" ]] && return 0
  return 1
}

# A .claude/ directory holds settings: removing it, or copying/unpacking over it, rewrites them.
policy_dir() { case "$1" in */.claude) return 0;; esac; return 1; }

# Is <dir> neutral — can a bare name in it (no /, not .claude, .git…, .ssh, .aws, .netrc) be
# nothing protected? Not when it is protected itself, HOME, a .claude/.git/.config dir, /etc, the
# managed-settings parent, or the directory above the kit's hooks/ or the audit log. Sets NB.
neutral() {
  NB=0
  protected "$1" && return 0
  case "$1" in */.claude|*/.git|*/.config|"$HOME_DIR"|/etc|"/Library/Application Support") return 0;; esac
  [ -n "$SELF_DIR" ] && [[ ${SELF_DIR%/*} == "$1" ]] && return 0
  [ -n "$AUDIT_C" ] && [[ ${AUDIT_C%/*} == "$1" ]] && return 0
  NB=1
}

# git's own files, which git may go on writing.
gitown() {
  case "$1" in "$HOME_DIR"/.gitconfig|"$HOME_DIR"/.config/git|"$HOME_DIR"/.config/git/*|*/.git/config|*/.git/hooks|*/.git/hooks/*) return 0;; esac
  return 1
}

# Can glob <pattern> expand to <path>, or to a directory above or below it? Compared part by part
# as the shell expands a glob: * does not cross a /, and a leading dot is matched only by a dot.
reach() { # <pattern> <path>
  local IFS=/ k=0 m; local -a pp cc
  pp=($1); cc=($2); m=${#pp[@]}; [ "${#cc[@]}" -lt "$m" ] && m=${#cc[@]}
  while [ $k -lt $m ]; do
    case "${cc[k]}" in .*) case "${pp[k]}" in .*) ;; *) return 1;; esac;; esac
    [[ ${cc[k]} == ${pp[k]} ]] || return 1
    k=$((k+1))
  done
  return 0
}

# Does a glob (canonical, resolved against <base>) name a protected path? Sets GH to that path.
globhit() { # <pattern> <base>
  local d=${1%/*} bn=${1##*/} x pre=${1%%[\*\?\[]*}
  # the directory it expands in is itself protected: ~/.ssh/id_*, ~/.claude/hooks/*
  pre=${pre%/*}; protected "$pre" && { GH=$pre; return 0; }
  # its last part can match a protected name there: ~/.claude/settings.js?n, x/.claude/settings.*
  for x in settings.json settings.local.json hooks cwk-audit.jsonl config .gitconfig .netrc .ssh .aws .claude.json; do
    case "$x" in .*) case "$bn" in .*) ;; *) continue;; esac;; esac
    [[ $x == $bn ]] && protected "$d/$x" && { GH=$d/$x; return 0; }
  done
  # it can reach a concrete protected path: ~/.c*/settings.json, ~/.cl*, ~/.config/g? (not in a
  # here-document body fed to python, node, …: nothing globs there, and /** is a comment)
  [ "${GLIT:-0}" -eq 1 ] && return 1
  for x in "$HOME_DIR"/.claude/settings.json "$HOME_DIR"/.claude/settings.local.json "$HOME_DIR"/.claude/hooks \
           "$HOME_DIR"/.claude/cwk-audit.jsonl "$HOME_DIR"/.claude.json "$HOME_DIR"/.gitconfig "$HOME_DIR"/.netrc \
           "$HOME_DIR"/.ssh "$HOME_DIR"/.aws "$HOME_DIR"/.config/gh "$HOME_DIR"/.config/git ${SELF_DIR:+"$SELF_DIR"} \
           "$2"/.claude/settings.json "$2"/.claude/settings.local.json "$2"/.git/config "$2"/.git/hooks \
           "/Library/Application Support/ClaudeCode" /etc/claude-code ${AUDIT_C:+"$AUDIT_C"}; do
    reach "$1" "$x" && { GH=$x; return 0; }
  done
  return 1
}

# Brace expansion, done textually as bash does it: every {a,b} group, nested ones and {a..e} /
# {1..9} ranges, in all combinations (${…} is not one). Sets ALTS. BOVER=1 when the word would give
# more than BCAP words or is too long to take apart; ALTS is then the word alone.
BCAP=256
RANGE_N='^(-?[0-9]+)\.\.(-?[0-9]+)(\.\.(-?[0-9]+))?$'
RANGE_A='^([a-zA-Z])\.\.([a-zA-Z])(\.\.(-?[0-9]+))?$'
braces() {
  ALTS=("$1"); BOVER=0
  case "$1" in *\{*\}*) ;; *) return 0;; esac
  [ "${#1}" -gt 1024 ] && { BOVER=1; return 0; }
  local -a work st out; local wn=1 on=0 total=1 w i n ch sp s body pre post alt j c d lo hi step f
  work[0]=$1
  while [ "$wn" -gt 0 ]; do
    wn=$((wn-1)); w=${work[wn]}; n=${#w}; i=0; sp=0; f=0
    while [ $i -lt $n ]; do
      ch=${w:i:1}
      if [ "$ch" = '{' ]; then
        if [ $i -gt 0 ] && [ "${w:i-1:1}" = '$' ]; then st[sp]=-1; else st[sp]=$i; fi; sp=$((sp+1))
      elif [ "$ch" = '}' ] && [ "$sp" -gt 0 ]; then
        sp=$((sp-1)); s=${st[sp]}
        if [ "$s" -ge 0 ]; then
          body=${w:s+1:i-s-1}; pre=${w:0:s}; post=${w:i+1}
          local -a alts=(); alts=()
          if [[ $body =~ $RANGE_N ]] || [[ $body =~ $RANGE_A ]]; then
            lo=${BASH_REMATCH[1]}; hi=${BASH_REMATCH[2]}; step=${BASH_REMATCH[4]:-1}; step=${step#-}; [ "$step" -eq 0 ] 2>/dev/null && step=1
            case "$lo" in [a-zA-Z]) printf -v lo '%d' "'$lo"; printf -v hi '%d' "'$hi"; c=1;; *) c=0;; esac
            if [ $(( (hi>lo ? hi-lo : lo-hi) / step + 1 )) -gt "$BCAP" ]; then ALTS=("$1"); BOVER=1; return 0; fi
            [ "$hi" -ge "$lo" ] && d=$step || d=$((0-step))
            j=$lo
            while :; do
              if [ "$c" -eq 1 ]; then printf -v alt '%03o' "$j"; printf -v alt "\\$alt"; else alt=$j; fi
              alts+=("$alt"); j=$((j+d))
              if [ "$d" -gt 0 ]; then [ "$j" -gt "$hi" ] && break; else [ "$j" -lt "$hi" ] && break; fi
            done
          else
            # split on the commas that are not inside an inner (literal) group
            local dep=0 k2=0 m=${#body} cur=""
            while [ $k2 -lt $m ]; do
              c=${body:k2:1}
              case "$c" in '{') dep=$((dep+1)); cur+=$c;; '}') dep=$((dep-1)); cur+=$c;;
                ',') if [ "$dep" -eq 0 ]; then alts+=("$cur"); cur=""; else cur+=$c; fi;;
                *) cur+=$c;; esac
              k2=$((k2+1))
            done
            [ "${#alts[@]}" -gt 0 ] && alts+=("$cur")
          fi
          if [ "${#alts[@]}" -gt 0 ]; then
            total=$((total+${#alts[@]}))
            [ "$total" -gt "$BCAP" ] && { ALTS=("$1"); BOVER=1; return 0; }
            for alt in "${alts[@]}"; do work[wn]="$pre$alt$post"; wn=$((wn+1)); done
            f=1; break
          fi
        fi
      fi
      i=$((i+1))
    done
    [ "$f" -eq 0 ] && { out[on]=$w; on=$((on+1)); }
  done
  ALTS=("${out[@]}")
}

# ── file tools ──────────────────────────────────────────────────────────────
case "$tool" in
  Edit|Write|MultiEdit|NotebookEdit)
    fp=$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null)
    [ -z "$fp" ] && exit 0
    canon "$fp"; protected "$C" && deny "$tool on protected file $C"
    exit 0;;
  Bash) ;;
  *) exit 0;;
esac

# ── Bash ────────────────────────────────────────────────────────────────────
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$cmd" ] && exit 0

# A here-document's body is data (a file's contents, a commit message), not commands: it is taken
# out before anything below reads the command. Kept, and read as commands as before: a body fed to
# something that runs it (a word of the pipeline it is in — with the command a $(…) holding it sits
# in — is bash, sh, python, node, eval, source, xargs, a read loop's done, patch, git apply, … or is
# built at run time, "$PY"), and an unquoted-delimiter body holding $( or a backquote (it runs).
# Quotes, $'…', ${…}, $(…), `…`, $((…)), ((…)), comments and case patterns are followed, so a <<
# inside one is not taken for a here-document; bash ending a body at "EOF)" inside $( ) is followed
# too. What it cannot follow (a delimiter built at run time, a body that never ends, a newline in
# quotes before a body) leaves the command whole. One awk pass, linear.
case "$cmd" in *'<<'*)
read -r -d '' HD_AWK <<'AWK' || true
function push(t) { st[++sp] = t; cs[sp] = 0; rp[sp] = 0 }
function pop() { if (sp > 0) sp-- }
function interp(p,   a, nw, k, w, b, r) {
  gsub(/[0-9]*(>>|>\||>&|&>>|&>|<>|>|<)[ \t]*("[^"]*"|'[^']*'|[^ \t;&|<>()]+)/, " ", p)
  gsub(/["'\\]/, "", p); gsub(/[;&|()<>`\t\n]/, " ", p)
  nw = split(p, a, / +/); r = 0
  for (k = 1; k <= nw; k++) {
    w = a[k]; if (w == "") continue
    if (w ~ /\$./) return 2
    b = tolower(w); sub(/.*\//, "", b); sub(/^[a-z_][a-z0-9_]*=/, "", b)
    if (b ~ SRE) return 2
    if (b ~ LRE) r = 1
  }
  return r
}
function runs(p,   a, nw, k, w) {
  gsub(/["'\\]/, "", p); gsub(/[;&|()<>`\t\n]/, " ", p); nw = split(p, a, / +/)
  for (k = 1; k <= nw; k++) { w = tolower(a[k]); if (w ~ /^\.\.?\// || w ~ XRE) return 1 }
  return 0
}
function brk(   k, v) {
  if (P ~ /(^|[^A-Za-z0-9_])(function|alias)[ \t]/ || P ~ /[A-Za-z0-9_][ \t]*\([ \t]*\)/) fdef = 1
  if (pn > 0) { v = interp(P); for (k = 1; k <= pn; k++) hint[pend[k]] = v }
  else if (runs(P)) xrun = 1       # this command also RUNS something — a body written to a file may be it
  pn = 0; P = ""
}
function scan(s, i,   n, c, t, nx, j, d, q, x, k, strip) {
  n = length(s); cont = 0; pstart = i
  while (i <= n) {
    c = substr(s, i, 1); t = (sp > 0 ? st[sp] : "U")
    if (t == "S") { if (c == "'") pop(); i++; continue }
    if (t == "A") { if (c == "\\") { i += 2; continue } if (c == "'") pop(); i++; continue }
    if (t == "D" || t == "B" || t == "R") {
      if (c == "\\") { i += 2; continue }
      if (t == "D" && c == "\"") { pop(); i++; continue }
      if (t == "B" && c == "}") { pop(); i++; continue }
      if (t == "B" && c == "{") { push("B"); i++; continue }
      if (t == "R" && c == "(") { rp[sp]++; i++; continue }
      if (t == "R" && c == ")") {
        if (rp[sp] > 0) { rp[sp]--; i++; continue }
        pop(); i += (substr(s, i + 1, 1) == ")") ? 2 : 1; continue
      }
      if (t != "D" && c == "'") { push("S"); i++; continue }
      if (t != "D" && c == "\"") { push("D"); i++; continue }
      if (c == "$") {
        nx = substr(s, i + 1, 1)
        if (nx == "(") { if (substr(s, i + 2, 1) == "(") { push("R"); i += 3 } else { push("M"); i += 2; ws = 1 } continue }
        if (nx == "{") { push("B"); i += 2; continue }
      }
      if (c == "`") { push("T"); ws = 1; i++; continue }
      i++; continue
    }
    # a command context: the top level, ( ), $( ) (M), ` `
    if (c == "\\") { if (i == n) { cont = 1; i++; continue } i += 2; ws = 0; continue }
    if (c == "'") { push("S"); ws = 0; i++; continue }
    if (c == "\"") { push("D"); ws = 0; i++; continue }
    if (c == "`") { if (t == "T") { pop(); ws = 0 } else { push("T"); ws = 1 } i++; continue }
    if (c == "$") {
      nx = substr(s, i + 1, 1)
      if (nx == "'") { push("A"); i += 2; ws = 0; continue }
      if (nx == "\"") { push("D"); i += 2; ws = 0; continue }
      if (nx == "(") { if (substr(s, i + 2, 1) == "(") { push("R"); i += 3 } else { push("M"); i += 2; ws = 1 } continue }
      if (nx == "{") { push("B"); i += 2; continue }
      ws = 0; i++; continue
    }
    if (c == "(") { if (ws && substr(s, i + 1, 1) == "(") { push("R"); i += 2; continue } push("C"); ws = 1; i++; continue }
    if (c == ")") { if ((t == "C" || t == "M") && cs[sp] == 0) pop(); ws = 1; i++; continue }
    if (c == "#" && ws) break
    if (c == " " || c == "\t") { ws = 1; i++; continue }
    if ((c == "<" || c == ">") && substr(s, i + 1, 1) == "(") { push("M"); i += 2; ws = 1; continue }   # <( ) >( )
    if (c == ">") { i++; while (substr(s, i, 1) ~ /[>&|]/) i++; ws = 1; continue }
    if (c == "<") {
      if (substr(s, i + 1, 1) != "<") { i++; while (substr(s, i, 1) ~ /[<>&]/) i++; ws = 1; continue }
      if (substr(s, i + 2, 1) == "<") { i += 3; ws = 1; continue }          # <<< here-string
      j = i + 2; strip = 0; if (substr(s, j, 1) == "-") { strip = 1; j++ }
      while (substr(s, j, 1) == " " || substr(s, j, 1) == "\t") j++
      d = ""; q = 0
      while (j <= n) {
        x = substr(s, j, 1)
        if (x ~ /[ \t;&|<>()]/) break
        if (x == "'") { k = index(substr(s, j + 1), "'"); if (k == 0) { abort = 1; return } d = d substr(s, j + 1, k - 1); j += k + 1; q = 1; continue }
        if (x == "\"") {
          q = 1; j++
          while (j <= n && substr(s, j, 1) != "\"") {
            if (substr(s, j, 1) == "\\" && substr(s, j + 1, 1) ~ /[\\"$`]/) j++
            d = d substr(s, j, 1); j++
          }
          if (j > n) { abort = 1; return }
          j++; continue
        }
        if (x == "\\") { d = d substr(s, j + 1, 1); j += 2; q = 1; continue }
        if (x == "$" || x == "`") { abort = 1; return }
        d = d x; j++
      }
      if (d == "") { abort = 1; return }
      nid++; hdelim[nid] = d; hstrip[nid] = strip; hquoted[nid] = q; hq[++hn] = nid; pend[++pn] = nid
      for (k = 1; k <= sp; k++) { if (st[k] == "M") hin[nid] = hinM[nid] = 1; if (st[k] == "T") hin[nid] = hinT[nid] = 1 }
      i = j; ws = 1; continue
    }
    if (c == ";" || c == "&" || c == "|") {
      nx = substr(s, i + 1, 1)
      if (c == "&" && nx == ">") { i += 2; ws = 1; continue }
      if (sp == 0 && !(c == "|" && nx != "|")) {
        P = P substr(s, pstart, i - pstart); brk()
        i += (nx == c) ? 2 : 1; pstart = i; ws = 1; continue
      }
      i += (c == "|" && nx == "&") ? 2 : 1; ws = 1; continue
    }
    if (ws) {
      x = substr(s, i + 4, 1)
      if (x == "" || x == " " || x == "\t" || x == ";" || x == ")") {
        if (substr(s, i, 4) == "case") cs[sp]++
        else if (substr(s, i, 4) == "esac" && cs[sp] > 0) cs[sp]--
      }
    }
    ws = 0; i++
  }
}
# A body inside $( ) or ` `: bash 3.2 finds the end of the substitution by scanning its text, the
# body's too, for quotes, backquotes, comments and parentheses. Where that scan would end it inside
# the body (a ) the body did not open, a backquote closing ` `), or leave a quote open past it, the
# body is not plain data for every shell: leave the command whole (abort). A # ends the line for (
# but not for ); ${ $[ and $( inside "…" are not followed, so they abort too.
function comsub(s, id,   k, n, c, q) {
  n = length(s); q = hq2[id]
  if (hinT[id]) for (k = 1; k <= n; k++) { c = substr(s, k, 1); if (c == "\\") k++; else if (c == "`") abort = 1 }
  if (!hinM[id]) return
  for (k = 1; k <= n; k++) {
    c = substr(s, k, 1)
    if (q == "'") { if (c == "'") q = ""; continue }
    if (c == "\\") { k++; continue }
    if (q == "\"") {
      if (c == "\"") q = ""; else if (c == "`") q = "d`"; else if (c == "$" && substr(s, k + 1, 1) ~ /[({[]/) abort = 1
      continue
    }
    if (q == "`" || q == "d`") { if (c == "`") q = (q == "d`") ? "\"" : ""; continue }
    if (c == "'" || c == "\"") { q = c; continue }
    if (c == "`") { q = "`"; continue }
    if (c == "$" && substr(s, k + 1, 1) ~ /[{[]/) { abort = 1; continue }
    if (c == "#") { for (k++; k <= n; k++) if (substr(s, k, 1) == ")" && --hdep[id] < 0) abort = 1; break }
    if (c == "(") hdep[id]++
    else if (c == ")" && --hdep[id] < 0) abort = 1
  }
  hq2[id] = q
}
function eol(s,   t, r) {
  if (abort) return
  t = (sp > 0 ? st[sp] : "U")
  P = P substr(s, pstart)
  if (cont) return
  if (t != "U" && t != "C" && t != "M" && t != "T") { if (hn > 0) abort = 1; P = P "\n"; return }
  r = s; sub(/[ \t]+$/, "", r)
  if (sp == 0 && r !~ /(^|[^|])\|&?$/) brk(); else P = P "\n"
  if (hn > 0) hcur = 1
  ws = 1
}
BEGIN {
  # a body fed to a shell (or to what runs a shell) is shell text; one fed only to another
  # interpreter is kept but marked literal (no glob or brace expansion happens in it)
  SRE = "^(bash|sh|zsh|dash|ksh|mksh|yash|fish|csh|tcsh|busybox|npx|pnpx|bunx|uvx|make|gmake|ssh|eval|source|\\.|exec|xargs|parallel|read|mapfile|readarray|done|env|sudo|doas|su|at|batch|crontab|script)$"
  LRE = "^(python[0-9.]*|pypy[0-9.]*|node|nodejs|deno|bun|tsx|ts-node|ruby|irb|jruby|perl[0-9.]*|php[0-9.]*|lua[0-9.]*|luajit|tclsh[0-9.]*|wish|expect|osascript|swift|rscript|r|julia|pwsh|powershell|groovy|jshell|awk|gawk|mawk|nawk|sed|gsed|ed|ex|vi|vim|nvim|emacs|sqlite3|psql|mysql|dc|bc|gdb|lldb|ftp|sftp|lftp|patch|apply|am)$"
  XRE = "^(bash|sh|zsh|dash|ksh|mksh|fish|source|\\.|exec|eval|xargs|parallel|make|gmake|npx|bunx|uvx|python[0-9.]*|pypy[0-9.]*|node|nodejs|deno|bun|tsx|ts-node|ruby|perl[0-9.]*|php[0-9.]*|lua[0-9.]*|osascript|pwsh|chmod)$"
  sp = 0; hn = 0; hcur = 0; nid = 0; pn = 0; m = 0; abort = 0; ws = 1; P = ""; xrun = 0
}
{
  line = $0; out[++m] = line; ref[m] = 0
  if (abort) next
  if (hcur > 0) {
    id = hq[hcur]; l2 = line; d = hdelim[id]
    if (hstrip[id]) sub(/^\t+/, "", l2)
    if (l2 == d || substr(l2, 1, length(d) + 1) == d ")") {
      if (hinM[id] && hq2[id] != "") { abort = 1; next }
      hcur++; if (hcur > hn) { hcur = 0; hn = 0 }
      if (l2 == d) next
      scan(l2, length(d) + 1); eol(l2); next
    }
    ref[m] = id
    if (!hquoted[id] && (index(line, "$(") || index(line, "`"))) hsub[id] = 1
    if (hin[id]) comsub(line, id)
    next
  }
  if (!cont) ws = 1
  scan(line, 1); eol(line)
}
END {
  if (!abort && hcur == 0) brk()
  if (fdef) for (k = 1; k <= nid; k++) hint[k] = 2          # a function or alias may be what runs it
  if (xrun) for (k = 1; k <= nid; k++) hint[k] = 2          # `cat > x.sh <<EOF … EOF; bash x.sh`: the body is code
  for (k = 1; k <= m; k++) {
    if (abort || hcur > 0 || ref[k] == 0) { print out[k]; continue }
    if (hsub[ref[k]] || hint[ref[k]] == 2 || (hint[ref[k]] == 1 && nomark)) print out[k]
    else if (hint[ref[k]] == 1) print "\002" out[k]
  }
}
AWK
  nomark=0; case "$cmd" in *$'\002'*) nomark=1;; esac
  hd=$(printf '%s\n' "$cmd" | LC_ALL=C awk -v nomark="$nomark" "$HD_AWK" 2>/dev/null) && [ -n "$hd" ] && cmd=$hd;;
esac

# The command as the shell would spell its words: quotes and backslashes dropped, `\`+newline
# joined, $'…' escapes (\xHH, \NNN) decoded. One awk pass, linear; only when there is quoting.
read -r -d '' NORM_AWK <<'AWK' || true
{
  line = $0; n = length(line); cont = 0
  if (!ansi && index(line, "$'") == 0) {
    if (match(line, /\\+$/) && RLENGTH % 2 == 1) cont = 1
    gsub(/["'\\]/, "", line); printf "%s", line
    if (!cont) printf "\n"
    next
  }
  for (i = 1; i <= n; i++) {
    c = substr(line, i, 1)
    if (ansi) {
      if (c == "'") { ansi = 0; continue }
      if (c == "\\" && i < n) {
        d = substr(line, i + 1, 1)
        if (d == "x") {
          v = 0; k = i + 2
          while (k <= n && k < i + 4 && (h = index("0123456789abcdef", tolower(substr(line, k, 1)))) > 0) { v = v * 16 + h - 1; k++ }
          if (k > i + 2) { if (v) printf "%c", v; i = k - 1; continue }
        } else if (d ~ /[0-7]/) {
          v = 0; k = i + 1
          while (k <= n && k < i + 4 && substr(line, k, 1) ~ /[0-7]/) { v = v * 8 + substr(line, k, 1); k++ }
          if (v) printf "%c", v
          i = k - 1; continue
        }
        printf "%s", d; i++; continue
      }
      printf "%s", c; continue
    }
    if (c == "$" && substr(line, i + 1, 1) == "'") { ansi = 1; i++; continue }
    if (c == "\\" && i == n) { cont = 1; continue }
    if (c == "'" || c == "\"" || c == "\\") continue
    printf "%s", c
  }
  if (!cont) printf "\n"
}
AWK
NORM=$cmd
case "$cmd" in *[\'\"\\]*) NORM=$(printf '%s\n' "$cmd" | awk "$NORM_AWK");; esac

# cheap pre-filter: nothing protected is mentioned, as written or once normalised. `hooks` counts
# only as a word of its own (not webhooks, useHooks); a dot-name holding a glob or brace (~/.c*/x,
# .{claude,x}) may be one; a git work tree (git --work-tree ~ reset --hard) may hold one.
printf '%s\n%s\n' "$cmd" "$NORM" | grep -qiE '\.claude|\.gitconfig|\.git/(config|hooks)|\.ssh|\.aws|\.config/(gh|git)|\.netrc|ClaudeCode|claude-code|cwk-audit|(^|[^a-z])hooks|file-guard|work[-_]?tree|(^|[/~[:space:]])\.[a-z0-9_.-]*(/[a-z0-9_.-]*)*[*?[{]' || exit 0

# A protected path as text (the last check below, and the long-command check here).
FRAG='\.claude/settings|\.claude\.json|\.claude/hooks|/\.claude/?([^a-z0-9_./-]|$)|\.ssh/|/\.ssh/?([^a-z0-9_./-]|$)|\.aws/|/\.aws/?([^a-z0-9_./-]|$)|\.gitconfig|\.git/config|\.git/hooks|\.netrc|\.config/gh|\.config/git|ClaudeCode|/etc/claude-code'

# Over 64 KB (here-document bodies already out) it is not taken apart word by word — that could
# outrun the hook's timeout. Its output redirections are checked, and it is refused if it names a
# protected path at all, the guard's directory or the kit's, or runs where a bare name can be one.
if [ "${#cmd}" -gt 65536 ]; then
  while IFS= read -r x; do
    [ -z "$x" ] && continue
    canon "$x"; protected "$C" && deny "shell output redirected into protected file $C"
  done <<EOF
$(printf '%s\n' "$NORM" | grep -oE '(>>?|>\||&>>?|<>)[[:space:]]*[^[:space:];|&<>()]+' | sed -E 's/^(>>?|>\||&>>?|<>)[[:space:]]*//')
EOF
  printf '%s\n' "$NORM" | grep -qiE "$FRAG" && deny "a command over 64 KB that names a protected path is too long to check; split it up"
  if [ -n "$SELF_DIR" ]; then
    [[ $NORM == *"$SELF_DIR"* ]] || [[ $NORM == *"${SELF_DIR%/*}"* ]] && deny "a command over 64 KB that names the guard's directory is too long to check; split it up"
  fi
  neutral "$cwd"; [ "$NB" -eq 0 ] && deny "a command over 64 KB, run in $cwd where a bare name can be protected, is too long to check; split it up"
  exit 0
fi

# A word with its quoting removed, for classification. Sets U. Quotes, backslashes, backquotes and
# parentheses go (splitting on them is linear; ${x//…} is quadratic in bash 3.2); a word with $'…'
# or $"…" is walked so the escapes decode ($'\x2eclaude' is .claude).
unq() {
  case "$1" in
    *\$[\'\"]*) unq_slow "$1";;
    *[\"\'\\\`\(\)]*) local IFS=$'"\'\\`()'; local -a parts; parts=($1); IFS=; U="${parts[*]}";;
    *) U=$1;;
  esac
}
unq_slow() {
  local s=$1 i=0 n=${#1} ch q="" out="" f
  while [ $i -lt $n ]; do
    ch=${s:i:1}; i=$((i+1))
    if [ "$q" = "'" ]; then
      if [ "$ch" = "'" ]; then q=""; else out+=$ch; fi; continue
    fi
    if [ "$q" = '"' ]; then
      case "$ch" in \") q="";; \\) out+=${s:i:1}; i=$((i+1));; [\`\(\)]) ;; *) out+=$ch;; esac; continue
    fi
    case "$ch" in
      \') q="'";;
      \") q='"';;
      \\) out+=${s:i:1}; i=$((i+1));;
      [\`\(\)]) ;;
      \$) case "${s:i:1}" in
            \') f=""; i=$((i+1))
                while [ $i -lt $n ]; do
                  ch=${s:i:1}; i=$((i+1))
                  case "$ch" in \') break;; \\) f+="$ch${s:i:1}"; i=$((i+1));; *) f+=$ch;; esac
                done
                printf -v f -- "${f//%/%%}" 2>/dev/null; out+=$f;;
            \") q='"'; i=$((i+1));;
            *) out+=$ch;;
          esac;;
      *) out+=$ch;;
    esac
  done
  U=$out
}

# Is this raw word a redirection operator (>, >>, >|, >&, &>, <, <<, <<<, <>, 2>, 1<>, …)?
isop() {
  case "$1" in
    \<*|\>*|\&\>*|[0-9]\<*|[0-9]\>*|[0-9][0-9]\<*|[0-9][0-9]\>*) case "$1" in *[!0-9\<\>\&\|]*) return 1;; esac; return 0;;
  esac
  return 1
}

# Quote-aware tokeniser. Commands end at unquoted ; && || | & and newlines (not the & of 2>&1 or
# &>f): TOK holds each word as ":word", and "0" or "1" between two commands — 1 when a single |
# feeds the next from this one. A separator after an empty command opens no new one: `a |<newline>
# b` is still a pipe. An unquoted < or > is a word of its own with the fd number written before it
# (x>f is x > f, 1<>f is 1<> f). It splits each line into blank-separated words first and walks
# only the words holding a special character, so a long line or heredoc stays linear. Blanks
# inside quotes come out as one space — enough to classify a word. A word with a { outside quotes
# (the shell may brace-expand it) is "+word" instead of ":word"; a word of a line marked \002 (a
# here-document body fed to python, node, … — not shell text, so nothing in it is globbed or
# brace-expanded as a word) is "=word".
TOK=(); WS=$' \t'; NL=$'\n'
tokenise() {
  local lines line words w q="" cur="" have=0 segn=0 i n ch run cont nw j op esc ub=0 lit=0 IFS
  flush() {
    if [ "$have" -eq 1 ]; then
      if [ "$lit" -eq 1 ]; then TOK+=("=$cur"); elif [ "$ub" -eq 1 ]; then TOK+=("+$cur"); else TOK+=(":$cur"); fi; segn=1
    fi
    cur=""; have=0; ub=0
  }
  cut_seg() { flush; if [ "$segn" -eq 1 ]; then TOK+=("$1"); segn=0; fi; }
  IFS=$NL; lines=($1)
  for line in "${lines[@]}"; do
    lit=0; case "$line" in $'\002'*) lit=1; line=${line#$'\002'};; esac
    IFS=$WS; words=($line); nw=${#words[@]}; j=0; cont=0
    for w in "${words[@]}"; do
      j=$((j+1))
      if [ -n "$q" ]; then
        [ "$j" -gt 1 ] && cur+=" "
      elif [ "$have" -eq 0 ]; then
        case "$w" in
          *[\;\|\&\<\>\'\"\\]*) ;;
          *) if [ "$lit" -eq 1 ]; then TOK+=("=$w"); else case "$w" in *\{*) TOK+=("+$w");; *) TOK+=(":$w");; esac; fi
             segn=1; continue;;
        esac
      fi
      i=0; n=${#w}; esc=0
      while [ $i -lt $n ]; do
        ch=${w:i:1}
        if [ -n "$q" ]; then
          if [ "$ch" = "$q" ]; then q=""; cur+=$ch; i=$((i+1)); continue; fi
          if [ "$q" = '"' ] && [ "$ch" = '\' ]; then cur+="$ch${w:i+1:1}"; i=$((i+2)); continue; fi
          run=${w:i}; if [ "$q" = "'" ]; then run=${run%%\'*}; else run=${run%%[\"\\]*}; fi
          cur+=$run; i=$((i+${#run})); continue
        fi
        case "$ch" in
          \'|\") q=$ch; cur+=$ch; have=1;;
          \\) if [ $((i+1)) -lt $n ]; then cur+="$ch${w:i+1:1}"; have=1; i=$((i+1)); else esc=1; fi;;
          ';') cut_seg 0;;
          '|') if [ "${w:i+1:1}" = '|' ]; then cut_seg 0; i=$((i+1))
               else cut_seg 1; [ "${w:i+1:1}" = '&' ] && i=$((i+1)); fi;;
          '&') if [ "${w:i+1:1}" = '>' ]; then
                 flush; op='&>'; i=$((i+2)); [ "${w:i:1}" = '>' ] && { op+='>'; i=$((i+1)); }
                 TOK+=(":$op"); segn=1; continue
               fi
               cut_seg 0; [ "${w:i+1:1}" = '&' ] && i=$((i+1));;
          '<'|'>')
               case "$cur" in ''|*[!0-9]*) flush; op="";; *) op=$cur; cur=""; have=0;; esac
               op+=$ch; i=$((i+1))
               while [ $i -lt $n ]; do case "${w:i:1}" in '<'|'>') op+=${w:i:1}; i=$((i+1));; *) break;; esac; done
               case "${w:i:1}" in '&'|'|') op+=${w:i:1}; i=$((i+1));; esac
               TOK+=(":$op"); segn=1; continue;;
          *) run=${w:i}; run=${run%%[\;\|\&\<\>\'\"\\]*}; [ "$lit" -eq 0 ] && case "$run" in *\{*) ub=1;; esac
             cur+=$run; have=1; i=$((i+${#run})); continue;;
        esac
        i=$((i+1))
      done
      # the end of a word: inside quotes the text goes on; after a lone \ the blank is escaped (or,
      # at the end of the line, the newline is); else the word is done
      if [ -n "$q" ]; then :
      elif [ "$esc" -eq 1 ]; then if [ "$j" -lt "$nw" ]; then cur+=" "; have=1; else cont=1; fi
      else flush; fi
    done
    # the newline: text inside quotes, nothing after a trailing \, else the end of a command
    if [ -n "$q" ]; then cur+=$NL; have=1; elif [ "$cont" -eq 0 ]; then cut_seg 0; fi
  done
  flush
}
tokenise "$cmd"

# Commands that only read. Anything else that names a protected path is a write until proven
# otherwise; so is output redirected onto one.
READ_ONLY_RE='^(cat|less|more|head|tail|grep|egrep|fgrep|rg|ugrep|ls|stat|file|wc|diff|cmp|jq|shellcheck|md5sum|md5|shasum|sha256sum|realpath|readlink|test|\[|\[\[|bat|cut|tr|od|xxd|hexdump|strings|du|basename|dirname|echo|printf|type|which|command|true|:|env|printenv|pwd|cd|pushd|popd)$'
LAUNCHER_RE='^(sudo|env|command|builtin|nohup|time|exec|xargs|parallel|nice|ionice|timeout|stdbuf|doas)$'

# Is short option <letter> in word <k> — alone, last of a bundle (-xC), or with its value attached
# (-C.claude)? Sets OV to what its value names (TK: p, g, d or empty). Reads TU/TK; call it under
# `flags`. optdir: is that value a .claude dir?
optval() { # <k> <letter>
  local lr=${TU[$1]#-}; lr=${lr%%[!a-zA-Z]*}
  case "$lr" in *"$2") ;; *) return 1;; esac
  if [ "${TU[$1]}" = "-$lr" ]; then OV=${TK[$1+1]:-}; else OV=${TK[$1]}; fi
}
optdir() { optval "$1" "$2" && [ "$OV" = d ]; }

# Step over what comes before the command itself: redirections with their target, ! { } ( ) and
# the reserved words, `case W in`, a case pattern (x) or (x)), a function header f() / f (). From
# word <k> of toks; sets K. `for NAME in LIST` / `select NAME in LIST` runs nothing: the list is
# data, so the whole segment is stepped over (LOOPH=1, LOOPV=NAME).
lead() {
  K=$1; local r
  while [ "$K" -lt "$n" ]; do
    r=${toks[$K]}
    if isop "$r"; then K=$((K+2)); continue; fi
    unq "$r"
    case "$U" in
      ''|'!'|'{'|'}'|if|then|elif|else|fi|do|done|while|until|esac) K=$((K+1)); continue;;
      time) K=$((K+1)); [ "${toks[$K]:-}" = -p ] && K=$((K+1)); continue;;
      function) K=$((K+2)); continue;;
      case) K=$((K+3)); continue;;
      for|select) LOOPH=1; unq "${toks[$((K+1))]:-}"; LOOPV=$U; K=$n; continue;;
    esac
    case "$r" in
      *'()'|\(*\)) K=$((K+1)); continue;;
      *\(*) ;;
      *\)) K=$((K+1)); continue;;
    esac
    [ "${toks[$((K+1))]:-}" = '()' ] && { K=$((K+2)); continue; }
    break
  done
}

# tar/zip/7z making an archive, cp/rsync/ditto/scp copying: is every protected word a source it
# only reads? Not the archive or the destination, not the value of an option that writes or runs
# (tar -f/-g, zip -O/-b, rsync --log-file/--backup-dir/-e, scp -S, cp -t), not an option word, not
# a word before the command; and no option that deletes or links the sources (tar --remove-files,
# zip -m, 7z -sdel, rsync --remove-source-files, cp -l/-s) or runs a program (tar -I/--to-command,
# zip -TT). Reads toks/TU/TK/ci/n/cmdword.
srcread() { flags; srcread_; local r=$?; names; return $r; }
srcread_() {
  local k w lr s=" " cls mode=c dk=-1 dd=0 x m first=0; local -a pos=()
  case "$cmdword" in
    tar|gtar|bsdtar) cls="tar"; mode="";; zip) cls="zip";; 7z|7za|7zz|7zr) cls="7z";;
    cp|gcp) cls="cp";; rsync) cls="rsync";; ditto) cls="ditto";; scp) cls="scp";;
    *) return 1;;
  esac
  k=$((ci+1))
  while [ $k -lt $n ]; do
    w=${TU[k]}
    if isop "${toks[k]}"; then
      case "${toks[k]}" in *\>*) ;; *) s+="$((k+1)) ";; esac   # an input redirection is read
      k=$((k+2)); continue
    fi
    if [ "$dd" -eq 1 ]; then pos+=("$k"); k=$((k+1)); continue; fi
    case "$cls:$w" in
      *:--) dd=1;;
      tar:--create|tar:--append|tar:--update|tar:--list|tar:--diff|tar:--compare|tar:--catenate|tar:--concatenate) mode=c;;
      tar:--extract|tar:--get|tar:--delete) mode=x;;
      tar:--remove-files|tar:--to-command*|tar:--checkpoint-action*|tar:--use-compress-program*|tar:--rsh-command*|tar:--info-script*|tar:--new-volume-script*|tar:--rmt-command*) return 1;;
      tar:--file|tar:--listed-incremental|tar:--index-file) k=$((k+1));;
      tar:--directory|tar:--files-from|tar:--exclude-from|tar:--exclude) s+="$((k+1)) "; k=$((k+1));;
      tar:--directory=*|tar:--files-from=*|tar:--exclude-from=*|tar:--exclude=*) s+="$k ";;
      zip:--move|zip:-TT|zip:--unzip-command*) return 1;;
      zip:-O|zip:--output-file|zip:-b|zip:--temp-path|zip:-lf|zip:--logfile-path|zip:-n|zip:--suffixes|zip:-t|zip:--from-date|zip:-tt|zip:--before-date|zip:-P|zip:--password|zip:-Z|zip:--compression-method|zip:-s|zip:--split-size) k=$((k+1));;
      zip:-x|zip:-i|zip:--exclude|zip:--include) ;;
      7z:-sdel) return 1;;
      cp:-l|cp:-s|cp:--link|cp:--symbolic-link|rsync:--remove-source-files|rsync:--remove-sent-files) return 1;;
      cp:-t|cp:--target-directory) dk=$((k+1)); k=$((k+1));;
      cp:--target-directory=*) dk=$k;;
      cp:-S|cp:--suffix) k=$((k+1));;
      rsync:--exclude|rsync:--include|rsync:--filter|rsync:-f|rsync:--exclude-from|rsync:--include-from|rsync:--files-from|scp:-F|scp:-i|ditto:--bom) s+="$((k+1)) "; k=$((k+1));;
      rsync:--exclude=*|rsync:--include=*|rsync:--filter=*|rsync:--exclude-from=*|rsync:--include-from=*|rsync:--files-from=*) s+="$k ";;
      rsync:-e|rsync:--rsh|rsync:--rsync-path|rsync:--log-file|rsync:--log-file-format|rsync:--backup-dir|rsync:--suffix|rsync:--partial-dir|rsync:-T|rsync:--temp-dir|rsync:--link-dest|rsync:--copy-dest|rsync:--compare-dest|rsync:--write-batch|rsync:--only-write-batch|rsync:--read-batch|rsync:--password-file|rsync:--chmod|rsync:--chown|rsync:--usermap|rsync:--groupmap|rsync:--out-format|rsync:--timeout|rsync:--contimeout|rsync:--bwlimit|rsync:--max-size|rsync:--min-size|rsync:--max-delete|rsync:-B|rsync:--block-size|rsync:--modify-window|rsync:--port|rsync:--address|rsync:--sockopts|rsync:--protocol|rsync:--iconv|rsync:--info|rsync:--debug|rsync:-M|rsync:--remote-option|rsync:--outbuf|rsync:--checksum-choice|rsync:--compress-choice|rsync:--compress-level|rsync:-@) k=$((k+1));;
      scp:-o|scp:-P|scp:-c|scp:-l|scp:-J|scp:-S|scp:-D|scp:-X) k=$((k+1));;
      *:--*) ;;
      *:-?*)
        lr=${w#-}; lr=${lr%%[!a-zA-Z0-9@]*}; x=0; [ "$w" = "-$lr" ] && x=1   # x: its value is the next word
        case "$cls" in
          tar) case "$lr" in *[IF]*) return 1;; esac
               case "$lr" in *[ctrudA]*) mode=c;; esac; case "$lr" in *x*) mode=x;; esac
               case "$lr" in *[fg]) [ "$x" -eq 1 ] && k=$((k+1));; *[CTX]) [ "$x" -eq 1 ] && { s+="$((k+1)) "; k=$((k+1)); };; esac;;
          zip) case "$lr" in *m*) return 1;; esac;;
          cp) case "$lr" in *[ls]*) return 1;; esac
              case "$lr" in *t) [ "$x" -eq 1 ] && { dk=$((k+1)); k=$((k+1)); };; *S) [ "$x" -eq 1 ] && k=$((k+1));; esac;;
          rsync) case "$lr" in *[eTBM@]) [ "$x" -eq 1 ] && k=$((k+1));; *f) [ "$x" -eq 1 ] && { s+="$((k+1)) "; k=$((k+1)); };; esac;;
          scp) case "$lr" in *[Fi]) [ "$x" -eq 1 ] && { s+="$((k+1)) "; k=$((k+1)); };; *[oPclJDXS]) [ "$x" -eq 1 ] && k=$((k+1));; esac;;
        esac;;
      tar:*) if [ "$k" -eq $((ci+1)) ] && [[ $w =~ ^[a-zA-Z]+$ ]]; then   # old style: tar czf a.tgz dir
               case "$w" in *[IF]*) return 1;; esac
               case "$w" in *[ctrudA]*) mode=c;; esac; case "$w" in *x*) mode=x;; esac
               case "$w" in *f*) k=$((k+1));; esac
             else pos+=("$k"); fi;;
      *) pos+=("$k");;
    esac
    k=$((k+1))
  done
  [ "$mode" = c ] || return 1
  m=${#pos[@]}
  case "$cls" in
    zip) first=1;;                                                      # zip ARCHIVE sources…
    7z) [ "$m" -ge 2 ] || return 1; case "${TU[pos[0]]}" in a|u|l|t|h) first=2;; *) return 1;; esac;;
    cp|rsync|ditto|scp) if [ "$dk" -lt 0 ] && [ "$m" -ge 2 ]; then m=$((m-1)); fi;;   # the last is the destination
  esac
  while [ "$first" -lt "$m" ]; do s+="${pos[first]} "; first=$((first+1)); done
  k=0
  while [ $k -lt $n ]; do
    case "${TK[k]:-}" in p|g) case "$s" in *" $k "*) ;; *) return 1;; esac;; esac
    k=$((k+1))
  done
  return 0
}

# $NAME / ${NAME} in raw word <t>, the loop variable, replaced by LP, what its list named. Sets ST.
sublv() {
  local t=${1//\$\{$LV\}/$LP} so="" rest
  while [[ $t == *\$$LV* ]]; do
    so+=${t%%\$$LV*}; rest=${t#*\$$LV}
    case "$rest" in [A-Za-z0-9_]*) so+="\$$LV";; *) so+=$LP;; esac
    t=$rest
  done
  ST=$so$t
}

acc=(); accb=(); toks=(); TB=(); pnext=0; named=0; xcwd=""; LV=""; LP=""
for t in "${TOK[@]}" 0; do
  case "$t" in :*) acc+=("${t#:}"); accb+=(0); continue;; +*) acc+=("${t#+}"); accb+=(1); continue;; =*) acc+=("${t#=}"); accb+=(2); continue;; esac
  toks=("${acc[@]}"); TB=("${accb[@]}"); acc=(); accb=(); piped=$pnext; pnext=$t
  n=${#toks[@]}; [ "$n" -eq 0 ] && continue
  names
  # after `for f in <a protected path>`, a command handed $f is handed that path
  if [ -n "$LV" ]; then
    k=0
    while [ $k -lt $n ]; do
      case "${toks[k]}" in *\$"$LV"*|*\$\{"$LV"\}*) sublv "${toks[k]}"; toks[k]=$ST;; esac
      k=$((k+1))
    done
  fi
  LOOPH=0
  # what an earlier stage named reaches this one only through a single |, never across ; && || &
  [ "$piped" = 1 ] || named=0

  # a cd/pushd here changes where the NEXT segments' relative paths resolve (once this one's own
  # words — a redirect of the cd itself — are checked)
  ncwd=""
  lead 0; k=$K
  unq "${toks[$k]:-}"
  case "$U" in builtin|command) unq "${toks[$((k+1))]:-}"; case "$U" in cd|pushd) k=$((k+1));; esac;; esac
  unq "${toks[$k]:-}"
  case "$U" in
    cd|pushd)
      k=$((k+1)); flags
      while [ $k -lt $n ]; do   # cd -P, cd -L, cd --, pushd -n
        if isop "${toks[$k]}"; then k=$((k+2)); continue; fi
        unq "${toks[$k]}"
        case "$U" in --) k=$((k+1)); break;; -?*) case "${U#-}" in *[!LPe@n]*) break;; esac; k=$((k+1));; *) break;; esac
      done
      names
      if [ $k -lt $n ] && ! isop "${toks[$k]}"; then unq "${toks[$k]}"; canon "$U"; ncwd=$C; else ncwd=$HOME_DIR; fi;;
  esac

  # first command word, skipping VAR=… prefixes, redirections and launchers with their options.
  # xargs/parallel run it on what the pipe feeds them, so note that. dyn: the word is built at run
  # time ($(which rm), `…`, $RM, {rm,-rf,x}, /bin/r?), so what it runs is unknown.
  lead 0; k=$K; cmdword=""; ci=$n; viax=0; dyn=0
  while [ $k -lt $n ]; do
    if isop "${toks[$k]}"; then k=$((k+2)); continue; fi
    unq "${toks[$k]}"
    case "$U" in *=*) k=$((k+1)); continue;; esac
    w=${U##*/}
    if ! [[ $w =~ $LAUNCHER_RE ]]; then
      cmdword=$w; ci=$k
      case "${toks[$k]}" in *\$*|*\`*) dyn=1; cmdword=${toks[$k]};; esac
      case "$U" in '['|'[[') ;; *\{*,*\}*|*\{*..*\}*|*[\*\?\[]*) dyn=1; cmdword=$U;; esac
      break
    fi
    vals=" "; dur=0
    case "$w" in
      xargs|parallel) viax=1; vals=" -n -I -L -P -s -d -E -a -J -R -S -j ";;
      sudo|doas) vals=" -u -g -U -C -h -p -D -r -t -T -R ";;
      env) vals=" -u -C -P -S ";;
      nice|ionice|stdbuf) vals=" -n -c -p -i -o -e ";;
      timeout) vals=" -s -k "; dur=1;;
      exec) vals=" -a ";;
    esac
    k=$((k+1)); flags
    while [ $k -lt $n ]; do
      unq "${toks[$k]}"
      case "$U" in -*) ;; *) break;; esac
      case "$vals" in *" $U "*) k=$((k+2));; *) k=$((k+1));; esac
    done
    names; k=$((k+dur))   # timeout's duration
  done

  # git -C <dir>: the words after it resolve against <dir>. A work tree (--work-tree, -c
  # core.worktree, GIT_WORK_TREE=) resolves the pathspecs after the subcommand too; wanc: it holds
  # a protected path (~, /, an ancestor of the kit), so a subcommand that rewrites files there is
  # blocked whatever the pathspec.
  base=$cwd; gcut=$n; gi=$n; gwt=""; wanc=""
  if [[ $cmdword == git ]]; then
    k=0
    while [ $k -lt $ci ]; do
      unq "${toks[$k]}"; case "$U" in GIT_WORK_TREE=*) canon "${U#GIT_WORK_TREE=}"; gwt=$C;; esac; k=$((k+1))
    done
    k=$((ci+1)); flags
    while [ $k -lt $n ]; do
      unq "${toks[$k]}"
      case "$U" in
        -C) unq "${toks[$((k+1))]:-}"; canon "$U" "$base"; base=$C; gcut=$((k+1)); k=$((k+2));;
        --work-tree) unq "${toks[$((k+1))]:-}"; canon "$U" "$base"; gwt=$C; k=$((k+2));;
        --work-tree=*) canon "${U#--work-tree=}" "$base"; gwt=$C; k=$((k+1));;
        -c) unq "${toks[$((k+1))]:-}"; shopt -s nocasematch
            case "$U" in core.worktree=*) canon "${U#*=}" "$base"; gwt=$C;; esac; flags; k=$((k+2));;
        --git-dir|--namespace|--config-env) k=$((k+2));;
        -*) k=$((k+1));;
        *) gi=$k; break;;
      esac
    done
    names
    if [ -n "$gwt" ]; then
      [ "$gwt" = / ] && wanc=/
      for x in "$HOME_DIR"/.claude "$HOME_DIR"/.claude.json "$HOME_DIR"/.ssh "$HOME_DIR"/.aws "$HOME_DIR"/.netrc \
               "$HOME_DIR"/.config/gh ${SELF_DIR:+"$SELF_DIR"} "/Library/Application Support/ClaudeCode" /etc/claude-code; do
        [[ $x == "$gwt"/* ]] && wanc=$gwt
      done
    fi
  fi

  # which protected paths (hit; ghit when not git's own) and .claude dirs (anc) does it name?
  # Per word: TU unquoted, TC canonical, TK what it names (p protected, g git's own, d .claude dir).
  # An output redirection onto a protected path is refused on the spot; onto a path built at run
  # time (dynred), when the command names one.
  hit=""; ghit=""; anc=""; TU=(); TC=(); TK=(); k=-1; b=$cwd; rt=0; dynred=0; subcd=-1
  neutral "$b"; [ -n "$gwt$xcwd" ] && NB=0
  for t in "${toks[@]}"; do
    k=$((k+1))
    case "$t" in *[\$\"\'\\\`\(\)]*) unq "$t";; *) U=$t;; esac
    TU[k]=$U; u=$U
    [ "$k" -eq $((gcut+1)) ] && { b=$base; neutral "$b"; [ -n "$gwt$xcwd" ] && NB=0; }
    case "$t" in [0-9\<\>\&]*) if isop "$t"; then case "$t" in *\<\<*) rt=2;; *\>*) rt=1;; *) rt=0;; esac; continue; fi;; esac
    red=$rt; rt=0; [ "$red" = 2 ] && continue   # a heredoc's tag
    # fast path: in a neutral directory a bare word (no / ~ $, glob, brace or protected name) can
    # name nothing protected — most of a long command or a heredoc
    if [ "$NB" -eq 1 ] && [ "$red" -eq 0 ] && [ "$k" -ne "$subcd" ]; then
      case "$t" in *[\(\`]cd|*[\(\`]pushd) ;; *)
        case "$U" in *[/~\$\*\?\[\{]*|*.claude*|*.git*|*.netrc*|*.ssh*|*.aws*) ;; *) continue;; esac;; esac
    fi
    # $(cd X …) / `cd X …`: the words after it may run in X
    if [ "$k" -eq "$subcd" ]; then case "$U" in -*) subcd=$((k+1));; *) canon "$U" "$b"; xcwd=$C;; esac; fi
    case "$t" in *[\(\`]cd|*[\(\`]pushd) subcd=$((k+1));; esac
    if [ "$red" = 1 ]; then x=${t//\$\{HOME\}/}; x=${x//\$HOME/}; case "$x" in *\$*|*\`*) dynred=1;; esac; fi
    # an option can carry the path: --output-document=<p>, -o<p>, -so<p>, -o.claude/settings.json
    case "$u" in
      --*=*) x=${u%%=*}; u=${u:${#x}+1};;
      --*) continue;;
      -*) u=${u#-}; u=${u#"${u%%[!a-zA-Z]*}"};;
    esac
    case "$u" in *=*) x=${u%%=*}; u=${u:${#x}+1};; esac
    [ -z "$u" ] && continue
    # a word quoted whole ('…' or "…") is neither a glob nor a brace expansion
    fq=0; case "$t" in \'*\'|\"*\") x=${t:1:${#t}-2}; case "$x" in *[\'\"]*) ;; *) fq=1;; esac;; esac
    if [ "$fq" -eq 1 ]; then ALTS=("$u"); BOVER=0; else braces "$u"; fi
    # too large to expand counts only for a { outside quotes and outside a here-document body (the
    # shell expands neither; a string an interpreter runs is still expanded above when small)
    [ "$BOVER" -eq 1 ] && [ "${TB[k]:-1}" != 1 ] && { ALTS=("$u"); BOVER=0; }
    GLIT=0; [ "${TB[k]:-0}" = 2 ] && GLIT=1
    if [ "$BOVER" -eq 1 ]; then
      case "$u" in *claude*|*.ssh*|*.aws*|*.git*|*.netrc*|*.config*|*hooks*|*file-guard*) deny "a brace expansion too large to check, beside a protected name";; esac
    fi
    b2=""; [ -n "$gwt" ] && [ "$k" -gt "$gi" ] && b2=$gwt
    for a in "${ALTS[@]}"; do
      for bb in "$b" ${b2:+"$b2"} ${xcwd:+"$xcwd"}; do
        canon "$a" "$bb"; [ "$bb" = "$b" ] && TC[k]=$C; hc=""
        if protected "$C"; then hc=$C
        elif [ "$fq" -eq 0 ]; then case "$C" in *[\*\?\[]*) globhit "$C" "$bb" && hc=$GH;; esac
        fi
        if [ -n "$hc" ]; then
          [ "$red" = 1 ] && deny "shell output redirected into protected file $hc"
          hit=$hc
          if gitown "$hc"; then TK[k]=${TK[k]:-g}; else TK[k]=p; ghit=$hc; fi
        elif policy_dir "$C"; then
          anc=$C; [ "${TK[k]}" = p ] || TK[k]=d
        fi
      done
    done
  done
  [ -n "$ncwd" ] && cwd=$ncwd
  [ "$dynred" -eq 1 ] && [ -n "$hit" ] && deny "output redirected to a path built at run time, beside protected $hit"
  # `for f in LIST`: the list is data. When it names a protected path or a .claude dir, a later
  # command handed $f is judged as if handed that path (sublv).
  if [ "$LOOPH" -eq 1 ]; then
    LV=""; if [ -n "$hit$anc" ] && [[ $LOOPV =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then LV=$LOOPV; LP=${hit:-$anc}; fi
  fi
  # no command word (`done < ~/.claude/settings.json`, X=…): only its redirections run, checked above
  if [ "$ci" -eq "$n" ]; then case "${toks[*]}" in *'$('*|*\`*) ;; *) continue;; esac; fi

  if [ -z "$hit" ] && [ -z "$anc" ] && [ -z "$wanc" ]; then
    # `echo ~/.claude/settings.json | xargs rm` — the path arrives through the pipe
    if [ "$named" -eq 1 ] && [ "$viax" -eq 1 ] && ! [[ $cmdword =~ $READ_ONLY_RE ]]; then
      deny "xargs $cmdword fed from a protected path"
    fi
    continue
  fi
  [ -n "$hit$anc" ] && named=1

  if [[ $cmdword == git ]]; then
    # git is not policed as git — the kit restricts no git command since 4.0.0 — and its own files
    # (~/.gitconfig, .git/config, .git/hooks) stay writable through it. It is only kept from being
    # the way around this guard for the others and for a .claude dir.
    [ -z "$ghit" ] && [ -z "$anc" ] && [ -z "$wanc" ] && continue
    what=${ghit:-${anc:-$wanc}}; gsub=""; gi=$n; k=0; flags
    while [ $k -lt $n ]; do
      w=${TU[k]}
      if [ $k -lt $ci ]; then
        case "$w" in GIT_WORK_TREE=*|GIT_DIR=*) case "${TK[k]}" in p|d) deny "git with ${w%%=*} at $what";; esac;; esac
      else
        [ -n "$ghit$anc" ] && case "$w" in --work-tree*|--output*) deny "git ${w%%=*} on $what";; esac
        if [ $k -gt $ci ] && [ -z "$gsub" ]; then
          case "$w" in
            -c) shopt -s nocasematch; case "${TU[k+1]:-}" in core.worktree=*) [ -n "$ghit$anc" ] && deny "git -c core.worktree on $what";; esac; flags; k=$((k+2)); continue;;
            -C|--git-dir|--namespace|--config-env|--work-tree) k=$((k+2)); continue;;
            -*) ;;
            *) gsub=$w; gi=$k;;
          esac
        fi
      fi
      k=$((k+1))
    done
    names
    case "$gsub" in
      checkout|switch|mv|stash|apply|am|merge|pull|rebase|cherry-pick|revert|clone|checkout-index|merge-file|read-tree) deny "git $gsub on $what";;
      restore|rm|reset|clean|config|archive|format-patch) ;;
      *) continue;;
    esac
    # restore --staged and rm --cached touch only the index; reset only with --hard/--merge/--keep
    # rewrites files; clean -n only lists; config writes where --file points; archive/format-patch -o
    st=0; wt=0; ca=0; hard=0; dry=0; fo=0; oo=0; flags; k=$((gi+1))
    while [ $k -lt $n ]; do
      w=${TU[k]}
      case "$w" in
        --) break;;
        --staged) st=1;; --worktree) wt=1;; --cached) ca=1;; --hard|--merge|--keep) hard=1;; --dry-run) dry=1;;
        --file) case "${TK[k+1]:-}" in p|d) fo=1;; esac;;
        --file=*) case "${TK[k]}" in p|d) fo=1;; esac;;
        --*) ;;
        -?*) lr=${w#-}; lr=${lr%%[!a-zA-Z]*}
             case "$lr" in *S*) st=1;; esac; case "$lr" in *W*) wt=1;; esac; case "$lr" in *n*) dry=1;; esac
             case "$lr" in *o) oo=1;; esac
             [ "$lr" = f ] && case "${TK[k]}${TK[k+1]:-}" in *p*|*d*) fo=1;; esac;;
      esac
      k=$((k+1))
    done
    names
    case "$gsub" in
      restore) [ "$st" -eq 1 ] && [ "$wt" -eq 0 ] || deny "git restore on $what";;
      rm) [ "$ca" -eq 1 ] || deny "git rm on $what";;
      reset) [ "$hard" -eq 1 ] && deny "git reset --hard on $what";;
      clean) [ "$dry" -eq 1 ] || deny "git clean on $what";;
      config) [ "$fo" -eq 1 ] && deny "git config --file on $what";;
      archive|format-patch) [ "$oo" -eq 1 ] && deny "git $gsub -o on $what";;
    esac
    continue
  fi
  [ -z "$hit" ] && [ -z "$anc" ] && continue

  # an archive being made, or a copy, only reads its sources (tar czf /tmp/k.tgz hooks, zip -r
  # x.zip hooks, cp ~/.claude/settings.json /tmp/): the protected path is a read there, and what is
  # left is whether a .claude dir is what it writes into
  if [ -n "$hit" ] && [ "$dyn" -eq 0 ] && srcread; then
    hit=""; [ -z "$anc" ] && continue
  fi

  if [ -z "$hit" ]; then
    # Only a .claude dir is named: blocked where it is what gets removed or replaced.
    [ "$dyn" -eq 1 ] && deny "'$cmdword' on $anc: a command built at run time cannot be checked"
    cls=""; rec=0
    case "$cmdword" in
      rm|rmdir|trash|grm|unlink|mv|gmv) deny "'$cmdword' on $anc, which holds settings files";;
      cp|gcp|rsync) cls="cp";;
      ditto) cls="ditto"; rec=1;;
      ln|gln|install|ginstall) cls="ln";;
      tar|gtar|bsdtar) cls="tar";;
      unzip) cls="unzip";;
      wget) cls="wget";;
      curl) cls="curl";;
      find|gfind) cls="find";;
    esac
    flags
    case "$cls" in
      cp|ditto|ln)
        # the DESTINATION — -t <dir>, or the last word that is not an option — must be the .claude dir
        dk=-1; pos=(); dd=0; k=$((ci+1))
        while [ $k -lt $n ]; do
          w=${TU[k]}; k=$((k+1))
          if [ "$dd" -eq 0 ]; then
            case "$w" in
              --) dd=1; continue;;
              -t|--target-directory) dk=$k; k=$((k+1)); continue;;
              --target-directory=*) dk=$((k-1)); continue;;
              --recursive|--archive) rec=1; continue;;
              --no-dereference) [ "$cls" = ln ] && rec=1; continue;;
              --exclude|--include|--filter|--exclude-from|--include-from|--files-from|--rsh|--suffix|--mode) k=$((k+1)); continue;;
              --*) continue;;
              -?*) lr=${w#-}; lr=${lr%%[!a-zA-Z]*}
                   case "$cls:$lr" in cp:*[rRa]*|ln:*[nhT]*) rec=1;; esac; continue;;
            esac
          fi
          case "$w" in \>*|\<*|[0-9]\>*|[0-9]\<*|\&\>*) [ -z "${w//[0-9&<>|]/}" ] && k=$((k+1)); continue;; esac
          pos+=("$((k-1))")
        done
        m=${#pos[@]}
        if [ "$dk" -lt 0 ] && [ "$m" -ge 2 ]; then dk=${pos[m-1]}; unset "pos[$((m-1))]"; fi
        [ "$dk" -ge 0 ] || continue
        if [ "${TK[dk]}" = d ]; then
          # a tree copied over it, settings*.json or hooks dropped into it (a source glob or brace
          # that can match them counts: tpl/*, tpl/{settings,x}.json), or whatever xargs brings
          [ "$rec" -eq 1 ] || [ "$viax" -eq 1 ] && deny "'$cmdword' into $anc, which holds settings files"
          names
          for s in ${pos[@]+"${pos[@]}"}; do
            braces "${TU[s]}"
            [ "$BOVER" -eq 1 ] && [ "${TB[s]:-1}" = 1 ] && deny "'$cmdword' into $anc from a brace expansion too large to check"
            for a in "${ALTS[@]}"; do
              x=${a%/}; x=${x##*/}; [ -z "$x" ] && continue
              for y in settings.json settings.local.json hooks; do
                [[ $y == $x ]] && deny "'$cmdword' of $x into $anc (it can be $y)"
              done
            done
          done
        elif [ "$cls" = cp ] && [ "$rec" -eq 1 ]; then
          # cp -R x/.claude ~ lands as ~/.claude: a .claude dir copied by name (no trailing /) onto
          # the home or working directory replaces the one there
          names
          [[ ${TC[dk]} == "$HOME_DIR" ]] || [[ ${TC[dk]} == "$cwd" ]] || continue
          for s in ${pos[@]+"${pos[@]}"}; do
            [ "${TK[s]}" = d ] && case "${TU[s]}" in */|*/.) ;; *) deny "'$cmdword' of $anc onto ${TC[dk]}/.claude";; esac
          done
        fi;;
      tar)
        ext=0; into=0; k=$((ci+1))
        while [ $k -lt $n ]; do
          w=${TU[k]}
          case "$w" in
            --extract|--get) ext=1;;
            --directory|--cd) [ "${TK[k+1]:-}" = d ] && into=1;;
            --directory=*|--cd=*) [ "${TK[k]}" = d ] && into=1;;
            --*) ;;
            -?*) lr=${w#-}; lr=${lr%%[!a-zA-Z]*}; case "$lr" in *x*) ext=1;; esac; optdir "$k" C && into=1;;
            *) [ "$k" -eq $((ci+1)) ] && case "$w" in *x*) ext=1;; esac;;   # old style: tar xzf a.tar
          esac
          k=$((k+1))
        done
        [ "$ext" -eq 1 ] && [ "$into" -eq 1 ] && deny "tar extracting into $anc, which holds settings files";;
      unzip)
        k=$((ci+1))
        while [ $k -lt $n ]; do
          case "${TU[k]}" in --*) ;; -?*) optdir "$k" d && deny "unzip -d into $anc, which holds settings files";; esac
          k=$((k+1))
        done;;
      wget|curl)
        if [ "$cls" = wget ]; then L=--directory-prefix; else L=--output-dir; fi
        k=$((ci+1))
        while [ $k -lt $n ]; do
          case "${TU[k]}" in
            "$L") [ "${TK[k+1]:-}" = d ] && deny "$cls $L into $anc, which holds settings files";;
            "$L"=*) [ "${TK[k]}" = d ] && deny "$cls $L into $anc, which holds settings files";;
            --*) ;;
            -?*) [ "$cls" = wget ] && optdir "$k" P && deny "wget -P into $anc, which holds settings files";;
          esac
          k=$((k+1))
        done;;
      find)
        act=""; inside=0; k=$((ci+1))
        while [ $k -lt $n ]; do
          case "${TU[k]}" in -delete|-exec|-execdir|-ok|-okdir) act=${TU[k]};; esac
          if [ "${TK[k]}" = d ]; then
            # `-name .claude -prune -o …` only skips it: the action is on the other branch. Without
            # the -o (`find ~/.claude -prune -delete`) the action still applies to it.
            j=$((k+1)); [ "${TU[j]:-}" = -prune ] && j=$((j+1))
            while [ "$j" -lt "$n" ] && [ -z "${TU[j]}" ]; do j=$((j+1)); done   # a closing \)
            case "${TU[k+1]:-}:${TU[j]:-}" in -prune:-o|-prune:-or) ;; *) inside=1;; esac
          fi
          k=$((k+1))
        done
        [ -n "$act" ] && [ "$inside" -eq 1 ] && deny "find $act in $anc, which holds settings files";;
    esac
    continue
  fi

  if [ "$dyn" -eq 0 ] && [[ $cmdword =~ $READ_ONLY_RE ]]; then
    continue
  fi
  if [ "$dyn" -eq 0 ]; then
    # bash -n only parses; uniq with one file (uniq -c f) only reads it — a second is its output
    np=0; nopt=0; k=$((ci+1)); flags
    while [ $k -lt $n ]; do
      if isop "${toks[k]}"; then k=$((k+2)); continue; fi
      case "${TU[k]}" in
        -f|-s|-w) [ "$cmdword" = uniq ] && k=$((k+1));;
        -n) ;;
        -*) nopt=1;;
        *) np=$((np+1));;
      esac
      k=$((k+1))
    done
    names
    case "$cmdword" in
      bash|sh|zsh|dash|ksh) [ "${TU[ci+1]:-}" = -n ] && [ "$nopt" -eq 0 ] && continue;;
      uniq|guniq) [ "$np" -le 1 ] && continue;;
    esac
  fi
  # readers that can still write: sed -i, awk -i inplace, find -delete/-exec, yq -i, sort -o
  cls=""
  case "$cmdword" in sed|gsed) cls="sed";; awk|gawk) cls="awk";; find|gfind) cls="find";; yq) cls="yq";; sort|gsort) cls="sort";; esac
  if [ "$dyn" -eq 0 ] && [ -n "$cls" ]; then
    flags
    k=-1
    for w in "${TU[@]}"; do
      k=$((k+1)); lr=""; case "$w" in --*) ;; -?*) lr=${w#-}; lr=${lr%%[!a-zA-Z]*};; esac
      case "$cls" in
        sed) case "$w" in --in-place*) deny "sed -i on protected file $hit";; esac
             case "$lr" in *[iI]*) deny "sed -i on protected file $hit";; esac;;
        awk) case "$w" in -i|--in-place|inplace) deny "awk in-place on protected file $hit";; esac;;
        find) case "$w" in -delete|-exec|-execdir|-ok|-okdir) deny "find $w under protected path $hit";; esac;;
        yq) case "$w" in --inplace*) deny "yq -i on protected file $hit";; esac
            case "$lr" in *i*) deny "yq -i on protected file $hit";; esac;;
        sort) # only where -o / --output points: sort ~/.claude/settings.json -o /tmp/x is a read
              OV=""; case "$w" in --output) OV=${TK[k+1]:-};; --output=*) OV=${TK[k]};; -?*) optval "$k" o;; esac
              case "$OV" in p|g) deny "sort -o on protected file $hit";; esac;;
      esac
    done
    continue
  fi
  deny "'$cmdword' on protected file $hit (only reads are allowed there)"
done

# ── last check: a protected name spelled through quoting ──────────────────────
# Everything above allowed it. If the normalised text names a protected path more often than the
# text as written, a name was assembled out of quotes or escapes (~/.cl'a'ude, $'\x2e'ssh/) — refuse
# rather than trust that the reading above followed it. Same for a word whose {x..y} range or
# second brace group can make one.
if [ "$NORM" != "$cmd" ]; then
  # a \/ (sed 's/\.claude\/x/') is read as / by the check above already; not counted as assembled
  r=$(printf '%s\n' "$cmd" | sed 's#\\/#/#g' | grep -oiE "$FRAG" | wc -l)
  m=$(printf '%s\n' "$NORM" | grep -oiE "$FRAG" | wc -l)
  [ $((m+0)) -gt $((r+0)) ] && deny "a protected path spelled through quoting or escapes; write it plainly"
  [ -n "$SELF_DIR" ] && [[ $NORM == *"$SELF_DIR"* ]] && ! [[ $cmd == *"$SELF_DIR"* ]] && deny "the guard's own directory spelled through quoting or escapes; write it plainly"
fi
case "$NORM" in
  *\{*)
    if printf '%s\n' "$NORM" | grep -v $'^\002' | grep -oE '[^[:space:];|&<>]*\{[^[:space:];|&<>]*' | grep -E '\{[^}]*\.\.|\{.*\{' \
       | grep -qiE "$FRAG|[{,]\.?(claude|ssh|aws|netrc|gitconfig)[},]"; then
      deny "a brace expansion ({x..y} or several groups) that can name a protected path; write the paths out"
    fi;;
esac

exit 0
