#!/usr/bin/env bash
# git-guard.sh — Claude Code PreToolUse hook (Bash).
#
# Policy:
#   • git push          → ALLOWED only to a WHITELISTED personal remote (see ALLOW_OWNER_RE);
#                         pushes to any other remote (team/org repos) are BLOCKED.
#   • other remote ops  → BLOCKED (remote add/set-url/…, send-email, svn dcommit, p4 submit)
#   • git config / -c   → only an ALLOWLIST of harmless keys may be set (user.name, color.*, …);
#                         anything that can retarget a push, run a command or load config
#                         (remote.*, url.*.insteadOf, branch.*.pushRemote, alias.*, core.sshCommand,
#                         include.*, credential.*, …) is BLOCKED. Reads (--get, --list) are allowed.
#   • GIT_* env         → BLOCKED anywhere in the command (GIT_DIR=… retargets the repository).
#   • gh                → commands that change GitHub state (pr merge/close/comment/review/create,
#                         issue create/close, repo delete/edit, api writes, release, secret, …) are
#                         ALLOWED only against a whitelisted personal repo; reads are allowed.
#   • interpreters      → `sh -c`, `python -c`, `node -e`, … whose code mentions git or gh are BLOCKED:
#                         the real command cannot be read.
#   • destructive local → BLOCKED (reset --hard, clean -f, checkout --/./-f, restore of the worktree,
#                         switch -C/--discard-changes, stash drop/clear, branch -D / -d -f,
#                         commit --amend, rebase, filter-branch, reflog expire, gc --prune, update-ref -d)
#   • everything else   → ALLOWED (fetch, pull, status, log, diff, show, blame, add, commit, stash,
#                         merge, checkout <branch>, restore --staged, config --get, …)
#
# How it reads a command: heredoc bodies are removed first (a commit message is prose, not a
# command), then the text is tokenised with shell quoting honoured and split into SEGMENTS on
# unquoted ; && || | & and newlines. Each segment's git SUBCOMMAND is the first non-option token
# after git and its global options, so rule words inside arguments (`git log --grep rebase`,
# `grep "git push" notes.md`) do not false-positive. Push targets are resolved from the push's own
# segment (its `-C <dir>`, else a `cd` in an EARLIER segment, else the session cwd).
#
# Limits, stated plainly: this is defence in depth, not a security boundary. It cannot see inside
# a script file it is asked to run, a shell alias defined elsewhere, or a tool other than Bash.
# The whitelist below lives in this file; an environment that needs it enforced installs the hook
# read-only from managed settings.

# ── EDIT ME: personal namespaces allowed to receive pushes ────────────────────
# Anchored at the start of the URL, so hosts like evil.example/github.com/… or
# github.com@evil.example cannot impersonate github.com.
# Add more owners: (NamHT4Devlop|my-other-user)
ALLOW_OWNER_RE='^(https://([^@/]+@)?|ssh://([^@/]+@)?|git@)github\.com[:/](NamHT4Devlop)/'
# The same owners, as `gh -R owner/repo` names them.
ALLOW_GH_REPO_RE='^(https://github\.com/)?(NamHT4Devlop)/'

# git config keys that `-c key=value` and `git config key value` may set. Everything else is
# refused: the list of dangerous keys (remote.*, url.*, alias.*, core.sshCommand, include.*, …)
# is open-ended, the list of keys a coding session legitimately sets is not.
CONFIG_KEY_ALLOW_RE='^(user\.(name|email|signingkey)|color\.[a-z.]+|advice\.[a-z]+|core\.(autocrlf|safecrlf|quotepath|ignorecase|filemode|eol|longpaths|preloadindex|fscache)|log\.[a-z.]+|diff\.(renames|renamelimit|context|noprefix|mnemonicprefix|algorithm)|commit\.(gpgsign|verbose|cleanup)|tag\.gpgsign|status\.[a-z.]+|column\.[a-z]+|i18n\.[a-z]+|gc\.auto|pull\.(rebase|ff)|push\.(default|autosetupremote)|init\.defaultbranch|branch\.autosetuprebase|fetch\.prune|rerere\.enabled|merge\.(conflictstyle|ff)|rebase\.(autostash|autosquash))$'

input=$(cat)

# The command text arrives as JSON, and jq is how it is read. Without jq, $cmd is empty, and an
# empty $cmd used to mean "not a git command" -- exit 0, allowed. So a machine that simply lacked jq
# had no guard at all, silently, for every push. Refuse to reason rather than guess.
if ! command -v jq >/dev/null 2>&1; then
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"🚫 cwk git-guard cannot run: jq is not installed, so the command cannot be read. Install jq (brew install jq / apt install jq) -- the guard fails closed rather than open."}}\n'
  exit 0
fi

cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$cmd" ] && exit 0
# Cheap pre-filter: nothing to guard unless the text mentions git, gh or a GIT_ variable.
printf '%s' "$cmd" | grep -qE '(^|[^[:alnum:]_])(git|gh)([^[:alnum:]_]|$)|GIT_[A-Z0-9_]+=' || exit 0

deny() {
  local msg="🚫 cwk git-guard blocked this command: $1
Allowed: read/sync git (fetch·pull·status·log·diff·show·blame·add·commit·stash·merge·checkout <branch>·config --get) and PUSH / gh writes to a whitelisted personal repo. Forbidden: pushing to other repos, config that retargets git, GIT_* overrides, git or gh hidden in an interpreter string, destructive operations. Need something else → run it yourself in a terminal."
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' \
    "$(printf '%s' "$msg" | jq -Rs .)"
  exit 0
}

set -f   # never glob-expand command text

# Known git subcommands. Anything else is treated as an ALIAS and denied: an alias
# starting with `!` runs an arbitrary shell command, which would bypass every rule below
# (e.g. `git -c alias.zz='!sh -c ...' zz`). Fail closed — add legitimate names here.
GIT_SUBCOMMANDS=" add am annotate apply archive bisect blame branch bugreport bundle cat-file
check-attr check-ignore check-mailmap checkout cherry cherry-pick citool clean clone column commit
commit-tree config count-objects describe diff diff-files diff-index diff-tree difftool fast-export
fast-import fetch fetch-pack filter-branch filter-repo for-each-ref format-patch fsck gc
get-tar-commit-id grep gui hash-object help init instaweb interpret-trailers log ls-files ls-remote
ls-tree mailinfo mailsplit maintenance merge merge-base merge-file merge-index merge-one-file
merge-tree mergetool mktag mktree multi-pack-index mv name-rev notes p4 pack-objects pack-redundant
pack-refs patch-id prune prune-packed pull push quiltimport range-diff read-tree rebase reflog remote
repack replace request-pull rerere reset restore rev-list rev-parse revert rm send-email send-pack
shortlog show show-branch show-index show-ref sparse-checkout stash status stripspace submodule svn
switch symbolic-ref tag unpack-file unpack-objects update-index update-ref update-server-info var
verify-commit verify-pack verify-tag version whatchanged worktree write-tree "

# Hide credentials embedded in a remote URL before echoing it back into the transcript.
redact() { printf '%s' "$1" | sed -E 's#//[^/@]*@#//***@#g'; }

# Strip shell quoting/grouping chars from a token for classification
# ("push" → push, \git → git, $(git → $git). $ is deliberately KEPT: stripping
# it could make a hostname like gith$ub.com look whitelisted.
unq() {
  local t=$1 bt='`'
  t=${t//\"/}; t=${t//\'/}; t=${t//\\/}
  t=${t//$bt/}; t=${t//\(/}; t=${t//\)/}; t=${t//\{/}; t=${t//\}/}
  printf '%s' "$t"
}

# ── 1. remove heredoc bodies ──────────────────────────────────────────────────
# A heredoc body is data (a commit message, a file being written), not commands. Dropping it is
# what stops a message that says "git command" or "git push" from being judged as one. Fail
# closed: a body under an UNQUOTED delimiter is expanded by the shell, so `$(…)` or backticks
# inside it would run — such a body is kept and judged as commands.
strip_heredocs() {
  local text=$1 out="" line delim quoted body keep=0 in=0 dash=0
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$in" -eq 1 ]; then
      local cmp=$line
      [ "$dash" -eq 1 ] && cmp=${cmp##*([[:space:]])}
      if [ "$cmp" = "$delim" ]; then
        in=0
        if [ "$keep" -eq 1 ]; then out+="$body"; fi
        body=""
        continue
      fi
      body+="$line"$'\n'
      case "$line" in *'$('*|*'`'*) [ "$quoted" -eq 0 ] && keep=1;; esac
      continue
    fi
    if [[ $line =~ \<\<(-?)[[:space:]]*(\'([^\']+)\'|\"([^\"]+)\"|([A-Za-z_][A-Za-z0-9_]*)) ]]; then
      dash=0; [ -n "${BASH_REMATCH[1]}" ] && dash=1
      if [ -n "${BASH_REMATCH[3]}" ]; then delim=${BASH_REMATCH[3]}; quoted=1
      elif [ -n "${BASH_REMATCH[4]}" ]; then delim=${BASH_REMATCH[4]}; quoted=1
      else delim=${BASH_REMATCH[5]}; quoted=0; fi
      in=1; keep=0; body=""
      out+="$line"$'\n'
      continue
    fi
    out+="$line"$'\n'
  done <<< "$text"
  # an unterminated heredoc: keep its body, the shell would run it as commands
  [ "$in" -eq 1 ] && out+="$body"
  printf '%s' "$out"
}
shopt -s extglob
cmd=$(strip_heredocs "$cmd")

# ── 2. tokenise with quoting honoured, split into segments ───────────────────
# TOK holds every token; SEGOF holds the segment number of each token. Quotes are kept in the
# token text (unq strips them for classification) so `"/tmp/has space"` stays one token and a
# quoted "git push" stays prose.
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

# ── 3. checks over the whole command ─────────────────────────────────────────
# GIT_DIR=…, GIT_WORK_TREE=…, GIT_SSH_COMMAND=… retarget or rewire git wherever they appear:
# as a prefix, after `export`, in an earlier segment. Refuse to reason about any of them.
for t in "${TOK[@]}"; do
  case "$(unq "$t")" in
    GIT_[A-Z0-9_]*=*) deny "GIT_* environment override ($(unq "$t" | cut -d= -f1)) can retarget the repository";;
  esac
done

# Aliasing the binary through a variable (`g=git; $g push …`) would sail past the token match,
# because `$g` is not `git`. We cannot follow shell variables, so refuse to reason about it.
for t in "${TOK[@]}"; do
  case "$(unq "$t")" in
    [A-Za-z_]*=git|[A-Za-z_]*=*/git) deny "git assigned to a shell variable (the real command cannot be verified)";;
  esac
done

# git or gh inside code handed to an interpreter (`sh -c "git push …"`, `python -c "os.system('gh …')"`)
# cannot be parsed here. Deny when the code string mentions either.
INTERP_RE='^(sh|bash|zsh|dash|ksh|fish|python[0-9.]*|node|nodejs|deno|bun|ruby|perl|php|lua|osascript)$'
i=0
while [ $i -lt $NTOK ]; do
  t=$(unq "${TOK[$i]}")
  if [[ ${t##*/} =~ $INTERP_RE ]]; then
    j=$((i+1))
    while [ $j -lt $NTOK ] && [ "${SEGOF[$j]}" = "${SEGOF[$i]}" ]; do
      case "$(unq "${TOK[$j]}")" in
        -c|-e|--eval|-r|-p|--print|-E)
          k=$((j+1))
          while [ $k -lt $NTOK ] && [ "${SEGOF[$k]}" = "${SEGOF[$i]}" ]; do
            if printf '%s' "${TOK[$k]}" | grep -qE '(^|[^[:alnum:]_])(git|gh)([^[:alnum:]_]|$)'; then
              deny "git/gh inside a string passed to ${t##*/} (the real command cannot be verified)"
            fi
            k=$((k+1))
          done;;
      esac
      j=$((j+1))
    done
  fi
  i=$((i+1))
done

# ── 4. per-segment rules ──────────────────────────────────────────────────────
CLEAN_F_RE='^-[A-Za-z]*f'

# Resolve the origin URL for a segment: its own `git -C <dir>` / `gh` cwd, else a cd/pushd from an
# EARLIER segment, else the session cwd. Never scan the whole command: a `cd` that runs AFTER the
# push must not decide which repo the push is validated against.
session_cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
resolve_dir() {
  local d=$1
  [ -z "$d" ] && d=$chdir_prefix
  [ -z "$d" ] && d=$session_cwd
  [ -z "$d" ] && d="$PWD"
  printf '%s' "${d/#\~/$HOME}"
}
config_key_ok() { printf '%s' "$1" | tr 'A-Z' 'a-z' | grep -qE "$CONFIG_KEY_ALLOW_RE"; }

chdir_prefix=""
seg=-1
segstart=0
while [ $segstart -lt $NTOK ]; do
  seg=${SEGOF[$segstart]}
  # collect this segment's tokens
  toks=(); i=$segstart
  while [ $i -lt $NTOK ] && [ "${SEGOF[$i]}" = "$seg" ]; do toks+=("${TOK[$i]}"); i=$((i+1)); done
  segstart=$i
  n=${#toks[@]}
  [ "$n" -eq 0 ] && continue

  case "$(unq "${toks[0]}")" in
    cd|pushd) [ "$n" -ge 2 ] && chdir_prefix=$(unq "${toks[1]}");;
  esac

  # ── gh ──
  gi=-1; i=0
  while [ $i -lt $n ]; do
    t=$(unq "${toks[$i]}")
    case "$t" in gh|*/gh) gi=$i; break;; esac
    i=$((i+1))
  done
  if [ $gi -ge 0 ]; then
    cmdpos=1; k=0
    while [ $k -lt $gi ]; do
      case "$(unq "${toks[$k]}")" in
        ''|*=*|sudo|env|command|nohup|time|exec|xargs|nice|ionice|timeout|stdbuf|'!'|then|do|else|elif|'$(') ;;
        *) cmdpos=0; break;;
      esac
      k=$((k+1))
    done
    if [ "$cmdpos" -eq 1 ]; then
      sub=$(unq "${toks[$((gi+1))]:-}"); act=$(unq "${toks[$((gi+2))]:-}")
      mut=0; repo=""
      case "$sub" in
        auth)      case "$act" in logout|refresh|setup-git) deny "gh auth $act (changes account state)";; esac;;
        alias)     [ "$act" = set ] && deny "gh alias set (an alias can run an arbitrary command)";;
        extension) case "$act" in install|upgrade|remove) deny "gh extension $act";; esac;;
        config)    [ "$act" = set ] && deny "gh config set";;
        secret|variable) case "$act" in set|delete|remove) mut=1;; esac;;
        pr)        case "$act" in merge|close|reopen|edit|ready|review|comment|create|lock|unlock) mut=1;; esac;;
        issue)     case "$act" in create|close|reopen|edit|delete|comment|transfer|pin|unpin|lock|unlock|develop) mut=1;; esac;;
        repo)      case "$act" in delete|archive|unarchive|rename|edit|sync|create|fork|deploy-key|set-default) mut=1;; esac;;
        release)   case "$act" in create|delete|edit|upload|delete-asset) mut=1;; esac;;
        workflow)  case "$act" in run|enable|disable) mut=1;; esac;;
        run)       case "$act" in cancel|rerun|delete) mut=1;; esac;;
        gist)      case "$act" in create|delete|edit) mut=1;; esac;;
        label|ruleset|cache|project|codespace) case "$act" in create|delete|edit|clone|set|rebuild|stop) mut=1;; esac;;
        api)
          for ((k=gi+2; k<n; k++)); do
            a=$(unq "${toks[$k]}")
            case "$a" in
              -X|--method) m=$(unq "${toks[$((k+1))]:-}" | tr 'a-z' 'A-Z'); [ "$m" != GET ] && mut=1;;
              -X*|--method=*) m=$(printf '%s' "${a#-X}" | sed 's/^--method=//' | tr 'a-z' 'A-Z'); [ "$m" != GET ] && mut=1;;
              -f|-F|--field|--raw-field|--input|-f*=*|-F*=*|--field=*|--raw-field=*|--input=*) mut=1;;
            esac
          done;;
      esac
      if [ "$mut" -eq 1 ]; then
        for ((k=gi+1; k<n; k++)); do
          a=$(unq "${toks[$k]}")
          case "$a" in
            -R|--repo) repo=$(unq "${toks[$((k+1))]:-}");;
            -R*|--repo=*) repo=${a#-R}; repo=${repo#--repo=};;
            # a repository named positionally: any GitHub URL, owner/repo for `gh repo …`,
            # or the repos/{owner}/{repo} path of an api call
            https://github.com/*) [ -z "$repo" ] && repo=$a;;
            repos/*/*) [ "$sub" = api ] && [ -z "$repo" ] && { repo=${a#repos/}; repo=${repo%%/*}/$(printf '%s' "${a#repos/*/}" | cut -d/ -f1); };;
            */*) [ "$sub" = repo ] && [ -z "$repo" ] && case "$a" in -*|*/*/*) ;; *) repo=$a;; esac;;
          esac
        done
        # an api write that names no repository targets the account or an org: never allowed
        [ "$sub" = api ] && [ -z "$repo" ] && deny "gh api write that names no repos/{owner}/{repo} path (account- or org-level change)"
        if [ -n "$repo" ]; then
          printf '%s' "$repo" | grep -qE "$ALLOW_GH_REPO_RE" ||
            deny "gh $sub $act on $repo — GitHub writes are allowed only on NamHT4Devlop/* repositories"
        else
          dir=$(resolve_dir "")
          url=$(git -C "$dir" remote get-url origin 2>/dev/null)
          printf '%s' "$url" | grep -qE "$ALLOW_OWNER_RE" ||
            deny "gh $sub $act against $(redact "${url:-a repo with no resolvable origin}") — GitHub writes are allowed only on NamHT4Devlop/* repositories"
        fi
      fi
    fi
  fi

  # ── git ──
  gi=-1; i=0
  while [ $i -lt $n ]; do
    t=$(unq "${toks[$i]}")
    case "$t" in git|*/git|\$git) gi=$i; break;; esac
    i=$((i+1))
  done
  [ $gi -lt 0 ] && continue

  # subcommand = first non-option token after git and its global options
  sub=""; cdir=""; redirected=0
  i=$((gi+1))
  while [ $i -lt $n ]; do
    t=$(unq "${toks[$i]}")
    case "$t" in
      -c|--config-env)
        i=$((i+1)); kv=$(unq "${toks[$i]:-}")
        config_key_ok "${kv%%=*}" || deny "git -c ${kv%%=*} (only harmless config keys may be set on the command line)";;
      -c*=*|--config-env=*)
        kv=${t#-c}; kv=${kv#--config-env=}
        config_key_ok "${kv%%=*}" || deny "git -c ${kv%%=*} (only harmless config keys may be set on the command line)";;
      # --git-dir/--work-tree point git at another repo; both the space and = forms
      --git-dir|--work-tree) redirected=1; i=$((i+1));;
      --git-dir=*|--work-tree=*) redirected=1;;
      -C) i=$((i+1)); [ $i -lt $n ] && cdir=$(unq "${toks[$i]}");;
      --namespace|--super-prefix|--exec-path) i=$((i+1));;
      -*) ;;
      *) sub=$t; break;;
    esac
    i=$((i+1))
  done
  [ -z "$sub" ] && continue

  # Is `git` actually in command position (segment start, after env assignments/wrappers)? Prose that
  # merely mentions git — a commit message, a doc string — must not be classified as an invocation.
  cmdpos=1; k=0
  while [ $k -lt $gi ]; do
    case "$(unq "${toks[$k]}")" in
      ''|*=*|sudo|env|command|nohup|time|exec|xargs|nice|ionice|timeout|stdbuf|'!'|then|do|else|elif|'$(') ;;
      *) cmdpos=0; break;;
    esac
    k=$((k+1))
  done

  # Unknown subcommand ⇒ an alias ⇒ possibly `!<shell>`. Refuse — but only for a real invocation.
  if [ "$cmdpos" -eq 1 ]; then
    case " ${GIT_SUBCOMMANDS//[$'\n\t']/ } " in
      *" $sub "*) ;;
      *) deny "unknown git subcommand '$sub' — it may be an alias running an arbitrary shell command";;
    esac
  fi

  # quote-stripped arguments after the subcommand
  args=()
  j=$((i+1))
  while [ $j -lt $n ]; do args+=("$(unq "${toks[$j]}")"); j=$((j+1)); done

  # ── PUSH → whitelist by target remote owner (resolved from THIS segment) ────
  if [ "$sub" = push ]; then
    [ "$redirected" -eq 1 ] &&
      deny "git push with --git-dir/--work-tree (the real push target cannot be verified)"

    # The remote is the FIRST non-option token after `push` — never scan every argument
    # (a whitelisted URL inside a trailing comment or --push-option must not authorize a push).
    target=""
    for a in "${args[@]}"; do
      case "$a" in
        \#*) break;;
        -*) continue;;
        *) target=$a; break;;
      esac
    done
    # `git push --repo=<repository>` names the target with no positional argument.
    if [ -z "$target" ]; then
      k=0
      while [ $k -lt ${#args[@]} ]; do
        case "${args[$k]}" in
          \#*) break;;
          --repo=*) target=${args[$k]#--repo=}; break;;
          --repo)   k=$((k+1)); target=${args[$k]:-}; break;;
        esac
        k=$((k+1))
      done
    fi

    url=""
    case "$target" in
      https://*|ssh://*|git@*|http://*|ftp*://*|file://*) url=$target;;
      *)
        dir=$(resolve_dir "$cdir")
        remote=${target:-origin}
        url=$(git -C "$dir" remote get-url "$remote" 2>/dev/null);;
    esac

    printf '%s' "$url" | grep -qE "$ALLOW_OWNER_RE" ||
      deny "git push to a remote NOT in the personal whitelist ($(redact "${url:-could not resolve remote}")) — only NamHT4Devlop/* may be pushed"
    continue
  fi

  case "$sub" in
    # ── other REMOTE-affecting → forbidden ────────────────────────────────────
    remote)
      case "${args[0]:-}" in
        add|remove|rm|rename|set-url|set-head|set-branches|prune) deny "git remote ${args[0]} changes the remote config";;
      esac;;
    send-email) deny "git send-email";;
    svn) [ "${args[0]:-}" = dcommit ] && deny "git svn dcommit";;
    p4)  [ "${args[0]:-}" = submit ]  && deny "git p4 submit";;
    config)
      # Reads are always fine. A write may only touch an allowlisted key; unset/edit/section
      # operations and any other key are refused (remote.*, url.*.insteadOf, branch.*.pushRemote,
      # alias.*, core.sshCommand, include.path, credential.helper … all retarget or run things).
      isread=0; key=""
      for a in "${args[@]}"; do
        case "$a" in
          --get|--get-all|--get-regexp|--get-urlmatch|-l|--list|--show-origin|--show-scope|--get-color|--get-colorbool|--name-only|--type=*|--bool|--int|--path|-z|--null) isread=1;;
          get|list) [ -z "$key" ] && isread=1;;
          --edit|-e|--unset|--unset-all|--remove-section|--rename-section|--replace-all|unset|edit|remove-section|rename-section)
            deny "git config $a (edits configuration that may retarget git)";;
          --global|--system|--local|--worktree|-f|--file|--blob|set|--add|--fixed-value) ;;
          -*) ;;
          *) [ -z "$key" ] && key=$a;;
        esac
      done
      if [ "$isread" -eq 0 ] && [ -n "$key" ]; then
        # `git config key` with no value is a read; with a value it is a write.
        nvals=0; for a in "${args[@]}"; do case "$a" in -*|get|set|list|add) ;; *) nvals=$((nvals+1));; esac; done
        if [ "$nvals" -ge 2 ]; then
          config_key_ok "$key" || deny "git config $key (only harmless config keys may be set; this one can retarget git or run a command)"
        fi
      fi;;

    # ── destructive LOCAL → forbidden ─────────────────────────────────────────
    reset)
      for a in "${args[@]}"; do [ "$a" = --hard ] && deny "git reset --hard (loses changes)"; done;;
    clean)
      for a in "${args[@]}"; do
        [ "$a" = --force ] && deny "git clean --force (deletes untracked files)"
        [[ $a =~ $CLEAN_F_RE ]] && deny "git clean -f (deletes untracked files)"
      done;;
    worktree)
      case "${args[0]:-}" in
        remove|prune) deny "git worktree ${args[0]} (deletes a worktree and its uncommitted work)";;
      esac;;
    checkout)
      for a in "${args[@]}"; do
        case "$a" in .|--|-f|--force) deny "git checkout that discards changes";; esac
      done;;
    restore)
      # `restore --staged` only moves changes out of the index; the worktree keeps them.
      staged=0; worktree=0
      for a in "${args[@]}"; do
        case "$a" in --staged|-S) staged=1;; --worktree|-W) worktree=1;; -[A-Za-z]*S*) staged=1;; esac
      done
      { [ "$staged" -eq 1 ] && [ "$worktree" -eq 0 ]; } || deny "git restore of the working tree (loses changes; --staged alone is allowed)";;
    switch)
      for a in "${args[@]}"; do
        case "$a" in
          --discard-changes|--force) deny "git switch --force/--discard-changes (discards changes)";;
          --*) ;;
          -*[Cf]*) deny "git switch -C/-f (discards changes)";;
        esac
      done;;
    stash)
      case "${args[0]:-}" in drop|clear) deny "git stash drop/clear (deletes stashed work)";; esac;;
    branch)
      del=0; force=0
      for a in "${args[@]}"; do
        case "$a" in
          --delete) del=1;;
          --force)  force=1;;
          --*) ;;
          -*D*) deny "git branch -D (deletes a branch, loses commits)";;
          -*)
            case "$a" in *d*) del=1;; esac
            case "$a" in *f*) force=1;; esac;;
        esac
      done
      [ "$del" -eq 1 ] && [ "$force" -eq 1 ] && deny "git branch -d -f (force-deletes a branch, loses commits)";;
    commit)
      for a in "${args[@]}"; do [ "$a" = --amend ] && deny "git commit --amend (rewrites history)"; done;;
    rebase) deny "git rebase (rewrites history)";;
    filter-branch|filter-repo) deny "git filter-branch/filter-repo";;
    reflog) [ "${args[0]:-}" = expire ] && deny "git reflog expire";;
    gc)
      for a in "${args[@]}"; do case "$a" in --prune*) deny "git gc --prune";; esac; done;;
    update-ref)
      for a in "${args[@]}"; do [ "$a" = -d ] && deny "git update-ref -d"; done;;
  esac
done

exit 0
