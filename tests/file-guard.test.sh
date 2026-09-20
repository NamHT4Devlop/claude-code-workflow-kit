#!/usr/bin/env bash
# Regression tests for hooks/file-guard.sh — the hook that keeps the agent from rewriting the
# policy files (settings.json, the hooks) and the credential stores beside them.
set -uo pipefail
cd "$(dirname "$0")/.."
GUARD=hooks/git-guard.sh; FG=hooks/file-guard.sh
pass=0; fail=0
export CWK_AUDIT_LOG=off

# Every case runs against a fake HOME so nothing real is touched or read.
FAKE=$(mktemp -d "${TMPDIR:-/tmp}/file-guard.XXXXXX")
export HOME="$FAKE/home"
mkdir -p "$HOME/.claude/hooks" "$HOME/.ssh" "$FAKE/proj/src" "$FAKE/proj/.claude" "$FAKE/proj/.git/hooks"
echo '{}' > "$HOME/.claude/settings.json"

runf()  { jq -cn --arg t "$1" --arg f "$2" --arg d "$3" '{tool_name:$t,tool_input:{file_path:$f},cwd:$d}' | bash "$FG"; }
runb()  { jq -cn --arg c "$1" --arg d "$2" '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' | bash "$FG"; }
denyf()  { if runf "$1" "$2" "$3" | grep -q '"deny"'; then pass=$((pass+1)); else echo "  ✗ expected BLOCK: $1 $2"; fail=$((fail+1)); fi; }
allowf() { local o; o=$(runf "$1" "$2" "$3"); if [ -z "$o" ]; then pass=$((pass+1)); else echo "  ✗ expected ALLOW: $1 $2"; fail=$((fail+1)); fi; }
denyb()  { if runb "$1" "$2" | grep -q '"deny"'; then pass=$((pass+1)); else echo "  ✗ expected BLOCK: $1"; fail=$((fail+1)); fi; }
allowb() { local o; o=$(runb "$1" "$2"); if [ -z "$o" ]; then pass=$((pass+1)); else echo "  ✗ expected ALLOW: $1"; fail=$((fail+1)); fi; }
P=$FAKE/proj

echo "file-guard: file tools on policy and credential files are blocked"
denyf Write "$HOME/.claude/settings.json" "$P"
denyf Edit  "~/.claude/settings.local.json" "$P"
denyf Edit  "$HOME/.claude/hooks/cwk-git-guard.sh" "$P"
denyf Write "$HOME/.claude/hooks/new-hook.sh" "$P"
denyf Edit  "hooks/git-guard.sh" "$PWD"                      # the kit's own hooks dir, relative path
denyf Write "$PWD/hooks/file-guard.sh" "$P"
denyf Edit  ".claude/settings.json" "$P"                     # project-level settings
denyf Write "$P/.claude/settings.local.json" "$P"
denyf Edit  "$HOME/.gitconfig" "$P"
denyf Edit  ".git/config" "$P"
denyf Write ".git/hooks/pre-commit" "$P"
denyf Write "$HOME/.ssh/config" "$P"
denyf Write "$HOME/.aws/credentials" "$P"
denyf Edit  "$HOME/.config/gh/hosts.yml" "$P"
denyf Write "$HOME/.claude/cwk-audit.jsonl" "$P"
denyf Edit  "src/../.claude/settings.json" "$P"               # normalised before matching
denyf NotebookEdit "$HOME/.claude/hooks/x.ipynb" "$P"

echo "file-guard: ordinary files are not its business"
allowf Edit  "src/app.js" "$P"
allowf Write "$P/README.md" "$P"
allowf Edit  "$HOME/.claude/CLAUDE.md" "$P"                  # memory file, not policy
allowf Write "$P/.claude/skills/x/SKILL.md" "$P"
allowf Edit  "$P/settings.json" "$P"                          # an app's own settings.json
allowf Write "$P/docs/hooks/README.md" "$P"                   # a docs folder that happens to be named hooks

echo "file-guard: shell writes to those files are blocked, reads are not"
denyb 'echo "{}" > ~/.claude/settings.json' "$P"
denyb 'cat patch.json >> "$HOME/.claude/settings.json"' "$P"
denyb 'sed -i "" "s/deny/allow/" ~/.claude/hooks/cwk-git-guard.sh' "$P"
denyb 'rm -f ~/.claude/hooks/cwk-git-guard.sh' "$P"
denyb 'mv ~/.claude/hooks/cwk-git-guard.sh /tmp/x' "$P"
denyb 'cp /tmp/x ~/.ssh/config' "$P"
denyb 'chmod -x ~/.claude/hooks/cwk-git-guard.sh' "$P"
denyb 'python3 patch.py ~/.claude/settings.json' "$P"
denyb 'jq ".hooks={}" ~/.claude/settings.json > ~/.claude/settings.json' "$P"
denyb 'tee ~/.gitconfig < x' "$P"
denyb 'cat x | tee .git/config' "$P"
denyb 'ls x && truncate -s 0 ~/.claude/settings.json' "$P"
denyb 'find ~/.claude/hooks -name "*.sh" -delete' "$P"
denyb 'ln -sf /tmp/evil.sh ~/.claude/hooks/cwk-git-guard.sh' "$P"
denyb "cd $PWD && cp /tmp/x hooks/git-guard.sh" "$P"
allowb 'cat ~/.claude/settings.json' "$P"
allowb 'jq .hooks ~/.claude/settings.json' "$P"
allowb 'grep -n deny ~/.claude/hooks/cwk-git-guard.sh' "$P"
allowb 'ls -la ~/.claude/hooks/' "$P"
allowb 'diff hooks/git-guard.sh ~/.claude/hooks/cwk-git-guard.sh' "$PWD"
allowb 'sed -n 1,20p ~/.claude/hooks/cwk-git-guard.sh' "$P"
allowb 'bash tests/run.sh' "$PWD"
allowb 'echo "settings.json is at ~/.claude/settings.json"' "$P"
allowb 'git config --global user.name me' "$P"                # git's writes are the git-guard's business
allowb 'echo hi > src/out.txt' "$P"

echo "file-guard: without jq it refuses rather than waves through"
SHIM=$(mktemp -d); for tool in cat grep sed awk tr head printf; do b=$(command -v "$tool" 2>/dev/null); [ -n "$b" ] && ln -s "$b" "$SHIM/$tool"; done
BASH_ABS=$(command -v bash)
o=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$HOME/.claude/settings.json" | PATH="$SHIM" "$BASH_ABS" "$FG" 2>/dev/null)
if printf '%s' "$o" | grep -q '"deny"' && printf '%s' "$o" | grep -q 'jq'; then pass=$((pass+1)); else echo "  ✗ expected DENY naming jq"; fail=$((fail+1)); fi
rm -rf "$SHIM"

echo "file-guard: a deny is written to the audit log, without the command text"
LOG=$FAKE/audit.jsonl
o=$(jq -cn --arg c 'echo SECRET_VALUE_123 > ~/.claude/settings.json' --arg d "$P" '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' | CWK_AUDIT_LOG="$LOG" bash "$FG")
if [ -f "$LOG" ] && grep -q '"decision":"deny"' "$LOG" && ! grep -q 'SECRET_VALUE_123' "$LOG"; then pass=$((pass+1)); else echo "  ✗ audit line missing or leaks the command"; fail=$((fail+1)); fi

rm -rf "$FAKE"
echo "file-guard: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
