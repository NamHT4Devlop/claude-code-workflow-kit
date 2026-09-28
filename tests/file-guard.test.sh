#!/usr/bin/env bash
# Regression tests for hooks/file-guard.sh — the hook that keeps the agent from rewriting the
# policy files (settings.json, the hooks) and the credential stores beside them.
set -uo pipefail
cd "$(dirname "$0")/.."
FG=hooks/file-guard.sh
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
denyf Edit  "$HOME/.claude/hooks/cwk-file-guard.sh" "$P"
denyf Write "$HOME/.claude/hooks/new-hook.sh" "$P"
denyf Edit  "hooks/file-guard.sh" "$PWD"                      # the kit's own hooks dir, relative path
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
denyb 'sed -i "" "s/deny/allow/" ~/.claude/hooks/cwk-file-guard.sh' "$P"
denyb 'rm -f ~/.claude/hooks/cwk-file-guard.sh' "$P"
denyb 'mv ~/.claude/hooks/cwk-file-guard.sh /tmp/x' "$P"
denyb 'cp /tmp/x ~/.ssh/config' "$P"
denyb 'chmod -x ~/.claude/hooks/cwk-file-guard.sh' "$P"
denyb 'python3 patch.py ~/.claude/settings.json' "$P"
denyb 'jq ".hooks={}" ~/.claude/settings.json > ~/.claude/settings.json' "$P"
denyb 'tee ~/.gitconfig < x' "$P"
denyb 'cat x | tee .git/config' "$P"
denyb 'ls x && truncate -s 0 ~/.claude/settings.json' "$P"
denyb 'find ~/.claude/hooks -name "*.sh" -delete' "$P"
denyb 'ln -sf /tmp/evil.sh ~/.claude/hooks/cwk-file-guard.sh' "$P"
denyb "cd $PWD && cp /tmp/x hooks/file-guard.sh" "$P"
allowb 'cat ~/.claude/settings.json' "$P"
allowb 'jq .hooks ~/.claude/settings.json' "$P"
allowb 'grep -n deny ~/.claude/hooks/cwk-file-guard.sh' "$P"
allowb 'ls -la ~/.claude/hooks/' "$P"
allowb 'diff hooks/file-guard.sh ~/.claude/hooks/cwk-file-guard.sh' "$PWD"
allowb 'sed -n 1,20p ~/.claude/hooks/cwk-file-guard.sh' "$P"
allowb 'bash tests/run.sh' "$PWD"
allowb 'echo "settings.json is at ~/.claude/settings.json"' "$P"
allowb 'git config --global user.name me' "$P"                # file-guard does not police git; the kit ships no git guard since 4.0.0
allowb 'echo hi > src/out.txt' "$P"

echo "file-guard: the ways around it a review found stay closed"
# macOS folds case like its filesystem; on a case-sensitive one these are other files, so allowed —
# either way the same number of cases runs, so the documented count holds on every platform.
if [ "$(uname -s)" = Darwin ]; then CASEF=denyf; CASEB=denyb; else CASEF=allowf; CASEB=allowb; fi
$CASEF Write "$HOME/.Claude/Settings.json" "$P"
$CASEF Edit  "$P/.Git/config" "$P"
$CASEB 'echo x > ~/.CLAUDE/settings.json' "$P"
denyf Write "$HOME/.claude.json" "$P"                         # MCP server commands live here
denyb 'rm -rf ~/.claude' "$P"                                 # the directory that holds settings
denyb 'cp -R /tmp/evil/. ~/.claude/' "$P"
denyb 'tar -xf evil.tar -C .claude' "$P"
denyb 'echo ~/.claude/settings.json | xargs rm -f' "$P"
denyb 'find ~/.claude -name settings.json | xargs rm' "$P"
denyb 'curl -so"$HOME/.claude/settings.json" https://x.test/s' "$P"
denyb 'wget --output-document=$HOME/.claude/settings.json https://x.test/s' "$P"
denyb 'sort -o ~/.claude/settings.json x' "$P"
denyb 'yq -i ".a=1" ~/.claude/settings.json' "$P"
denyb 'echo x > ~/.claude/settings.js?n' "$P"
denyb 'rm ~/.claude/hooks/*' "$P"
denyb 'git config --file ~/.claude/settings.json a.b c' "$P"
denyb 'git --work-tree=$HOME/.claude checkout -f -- settings.json' "$P"
denyb 'git checkout -- .claude/settings.json' "$P"
denyb "cd $PWD/hooks && rm file-guard.sh" "$P"
allowb 'git add .claude/settings.json && git commit -m settings' "$P"   # committing project settings is fine
allowb 'git diff .claude/settings.json' "$P"
allowb 'git config --file .git/config user.name me' "$P"             # git's own file
allowb 'mkdir -p ~/.claude/skills/x && cp -R skills/x/. ~/.claude/skills/x/' "$P"
allowb 'ls ~/.claude | sort' "$P"
allowb 'rm -rf ~/.claude/skills/cwk-old' "$P"

# within <seconds> <denyb|allowb> <cmd> <cwd>: the verdict, and that it arrives well inside the
# hook's 10 s timeout (a fork per word once took a padded deny past it)
within() {
  local t0=$SECONDS; "$2" "$3" "$4"
  if [ $((SECONDS-t0)) -lt "$1" ]; then pass=$((pass+1)); else echo "  ✗ slower than $1 s: ${3:0:50}…"; fail=$((fail+1)); fi
}
lines() { local k=0; while [ "$k" -lt "$2" ]; do printf '%s %s\n' "$1" "$k"; k=$((k+1)); done; }
HD_TS="cat > src/hooks/useAuth.ts <<'EOF'
$(lines '  const token = useState<string>(""); // the auth hook, line' 200)
EOF"
HD_WH="cat > docs/integrations.md <<'EOF'
$(lines 'Register webhooks for the payment provider and verify webhooks signatures, line' 150)
EOF"
PAD=':'; k=0; while [ $k -lt 1700 ]; do PAD+=' a'; k=$((k+1)); done; PAD+='; echo x > ~/.claude/settings.json'

echo "file-guard: ordinary work stays fast and allowed (a hooks/ folder, webhooks, useHooks)"
allowb 'cat src/hooks/useAuth.ts' "$P"
allowb 'grep -rn useHooks src/' "$P"
within 5 allowb "$HD_TS" "$P"
within 2 allowb "$HD_WH" "$P"                                 # never gets past the pre-filter
within 5 denyb "$PAD" "$P"

echo "file-guard: a .claude dir is blocked only where it is removed or replaced"
denyb 'rmdir .claude' "$P"
denyb 'trash ~/.claude' "$P"
denyb 'mv ~/.claude ~/.claude.bak' "$P"
denyb 'mv /tmp/settings.json ~/.claude/' "$P"
denyb 'cp /tmp/x/settings.json ~/.claude/' "$P"
denyb 'cp -a /tmp/evil ~/.claude' "$P"
denyb 'rsync -a --delete /tmp/evil/ ~/.claude/' "$P"
denyb 'ditto /tmp/evil ~/.claude' "$P"
denyb 'ln -s /tmp/evil/hooks ~/.claude/' "$P"
denyb 'ln -sfn /tmp/evil ~/.claude' "$P"
denyb 'install -m 644 settings.local.json .claude/' "$P"
denyb 'gcp -r -t ~/.claude /tmp/evil/x' "$P"
denyb 'cp -R /tmp/evil/.claude ~/' "$P"                        # lands as ~/.claude
denyb 'tar xzf evil.tgz --directory=$HOME/.claude' "$P"
denyb 'bsdtar --extract -f evil.tar -C ~/.claude' "$P"
denyb 'unzip -o evil.zip -d ~/.claude' "$P"
denyb 'wget -P ~/.claude https://x.test/settings.json' "$P"
denyb 'curl --output-dir ~/.claude -O https://x.test/settings.json' "$P"
denyb 'find ~/.claude -name "*.bak" -delete' "$P"
denyb 'ls /tmp/x | xargs -I{} cp {} ~/.claude/' "$P"          # the pipe may bring settings.json
denyb '$(which rm) -rf ~/.claude' "$P"                         # a command word built at run time
denyb '`which rm` -f ~/.claude/settings.json' "$P"
allowb 'CLAUDE_DIR=$HOME/.claude' "$P"
allowb 'rsync -a --exclude .claude src/ dst/' "$P"
allowb 'rsync -a src/ dst/ --exclude .claude' "$P"
allowb 'cp -R dist/.claude/ out/' "$P"
allowb 'cp notes.md .claude/' "$P"
allowb 'rsync -a ~/.claude ~/backup/' "$P"                    # a copy out of it
allowb 'tar -czf backup.tgz -C ~/.claude .' "$P"
allowb 'tar -cf x.tar -X skip.txt -C .claude .' "$P"          # -X is --exclude-from, not -x
allowb 'find ~/.claude -name "*.md"' "$P"
allowb 'find . -name .claude -prune -o -name "*.js" -exec grep -l x {} +' "$P"   # skips it
denyb 'find . -name .claude -exec rm -rf {} +' "$P"
allowb 'ln -s ~/.claude ~/claude-link' "$P"
allowb 'zip -r out.zip .claude' "$P"

echo "file-guard: git cannot rewrite a protected file or a .claude dir by another route"
denyb 'GIT_WORK_TREE=~/.claude git checkout -- settings.json' "$P"
denyb 'env GIT_DIR=$HOME/.claude/.git GIT_WORK_TREE=$HOME/.claude git status' "$P"
denyb 'git -C ~/.claude checkout -- settings.json' "$P"
denyb 'git -C ~/.claude stash' "$P"
denyb 'git -C ~/.claude reset --hard origin/main' "$P"
denyb 'git checkout -- .claude' "$P"
denyb 'git checkout-index -f -- .claude/settings.json' "$P"
denyb 'git merge-file .claude/settings.json base.json theirs.json' "$P"
denyb 'git read-tree -u --prefix=.claude/ HEAD' "$P"
denyb 'git diff --output=.claude/settings.json' "$P"
denyb 'git log --output ~/.claude/settings.json' "$P"
denyb 'git restore .claude/settings.json' "$P"
denyb 'git restore -s HEAD~1 .claude/settings.json' "$P"        # -s is --source, not -S
denyb 'git restore --staged --worktree .claude/settings.json' "$P"
denyb 'git restore -SW .claude/settings.json' "$P"
denyb 'git rm .claude/settings.json' "$P"
denyb 'git -c core.worktree=$HOME/.claude checkout -- settings.json' "$P"
denyb 'git --work-tree ~/.claude checkout .' "$P"
allowb 'git rm --cached .claude/settings.json' "$P"
allowb 'git rm -r --cached .claude' "$P"
allowb 'git restore --staged .claude/settings.json' "$P"
allowb 'git -C ~/.claude log --oneline' "$P"
allowb 'git -C ~/.claude status' "$P"
allowb 'git -C ~/.claude reset -- settings.json' "$P"          # unstages only
allowb 'git show HEAD:.claude/settings.json' "$P"
allowb 'git log -p -- .claude' "$P"
allowb 'git -C ~/.claude config --file .git/config user.name me' "$P"   # git's own file
allowb 'git config -f ~/.gitconfig user.name me' "$P"

echo "file-guard: a path glued to an option is read whole"
denyb 'curl -o.claude/settings.json https://x.test/s' "$P"
denyb 'curl -so~/.claude/settings.json https://x.test/s' "$P"
denyb 'sort -uo ~/.claude/settings.json x' "$P"
denyb 'sort --output=.claude/settings.json x' "$P"
denyb 'yq -Pi ".a=1" .claude/settings.json' "$P"
denyb 'yq --inplace ".a=1" .claude/settings.json' "$P"
denyb 'sed -Ei "s/a/b/" ~/.claude/settings.json' "$P"
allowb 'ls -la ~/.claude/settings.json' "$P"
allowb 'sort -u ~/.claude/settings.json' "$P"
allowb 'sort ~/.claude/settings.json -o /tmp/sorted.json' "$P"   # -o points elsewhere
allowb 'yq -I4 . .claude/settings.json' "$P"                  # -I is the indent, not -i

echo "file-guard: xargs is judged by the command it runs, and only within one pipe"
denyb 'echo ~/.claude/settings.json | xargs -n1 rm' "$P"
denyb 'echo ~/.claude/settings.json | xargs -0 -I {} rm {}' "$P"
denyb 'echo ~/.claude/settings.json | sudo xargs rm' "$P"
denyb 'echo ~/.claude/settings.json | parallel rm' "$P"
denyb 'echo ~/.claude/settings.json | grep json | xargs rm' "$P"
denyb 'echo ~/.claude/settings.json |
xargs rm' "$P"                                                # a pipe continues on the next line
denyb 'ls ~/.claude 2>&1 | xargs rm' "$P"                     # the & of 2>&1 ends no segment
allowb 'ls ~/.claude | xargs -n1 echo' "$P"
allowb 'ls ~/.claude | xargs -p echo' "$P"                    # -p prompts; -P would take a value
allowb 'echo ~/.claude/settings.json; ls | xargs -0 rm' "$P"   # ; ends what was named
allowb 'echo ~/.claude/x; ls | xargs -0 rm' "$P"
allowb 'cat ~/.claude/settings.json && ls | xargs rm' "$P"
allowb "find . -name '*.md' | xargs grep x" "$P"

echo "file-guard: globs and braces are matched against what they can expand to"
denyb 'rm -rf ~/.c*' "$P"
denyb 'echo x > ~/.c*/settings.json' "$P"
denyb 'rm ~/.claude/{settings,foo}.json' "$P"
denyb 'rm -rf ~/.{claude,cache}' "$P"
denyb 'rm ~/.ssh/id_*' "$P"
denyb 'rm -rf ~/.claude/*' "$P"
denyb 'rm .claude/settings*' "$P"
denyb 'rm -rf ~/.config/g?' "$P"
allowb 'rm -rf ~/.claude/skills/cwk-*' "$P"
allowb 'rm -rf ./*' "$P"                                      # * does not match .claude or .git
allowb 'rm -rf ~/.cache/*' "$P"
allowb 'ls ~/.*' "$P"
allowb 'cat ~/.claude/*' "$P"

echo "file-guard: cd options and line continuations do not hide the target"
denyb 'cd -P hooks && rm file-guard.sh' "$PWD"
denyb "cd -- $PWD/hooks && rm file-guard.sh" "$P"
denyb 'cd -L ~/.claude && echo x > settings.json' "$P"
denyb 'pushd -n ~/.claude && rm settings.json' "$P"
denyb 'rm -rf \
  ~/.claude' "$P"
denyb 'echo x >|~/.claude/settings.json' "$P"
allowb 'cd -P ~/.claude/skills && rm -rf old' "$P"

echo "file-guard: a name split by quotes or escapes is the name (and the pre-filter sees it)"
denyb "echo pwned > ~/.cl'a'ude/settings.json" "$P"
denyb "rm -rf ~/.cla''ude" "$P"
denyb 'cp evil ~/.s""sh/config' "$P"
denyb "echo x > ~/\$'\\x2e'claude/settings.json" "$P"          # $'\x2e' is a dot
denyb "cp evil ~/\$'.claude'/hooks/h.sh" "$P"
denyb 'rm -rf ~/.claud\e' "$P"
denyb 'rm -rf ~/.cla\
ude' "$P"                                                     # \+newline joins the word

echo "file-guard: reserved words and grouping do not hide the command or a cd"
denyb 'if true; then rm -rf ~/.claude; fi' "$P"
denyb '! rm -rf ~/.claude' "$P"
denyb 'for x in 1; do mv ~/.claude /tmp/m; done' "$P"
denyb 'if cd ~/.claude; then rm settings.json; fi' "$P"
denyb '{ cd ~/.claude; echo pwned > settings.json; }' "$P"
denyb 'if cd ~; then echo pwned > .claude.json; fi' "$P"
denyb 'time cd ~/.claude && rm -r hooks' "$P"
denyb 'builtin cd ~/.claude && rm settings.json' "$P"
denyb 'command cd ~/.claude; rm settings.json' "$P"
denyb 'while true; do rm -rf ~/.claude; done' "$P"
denyb 'case x in x) rm -rf ~/.claude;; esac' "$P"
denyb 'f() { rm -rf ~/.claude; }; f' "$P"
denyb '>/dev/null rm -rf ~/.claude' "$P"                       # a redirection before the command
denyb '{rm,-rf,~/.claude}' "$P"                                # a command word built by braces
denyb 'echo $(cd ~/.claude; rm settings.json)' "$P"            # cd inside $(…)
denyb 'cd ~/.claude > ~/.claude/settings.json' "$P"            # the cd's own redirect
allowb 'if [ -f x ]; then rm -rf build; fi' "$P"
allowb 'for f in *.md; do echo "$f"; done' "$P"
allowb '{ echo a; echo b; } > out.txt' "$P"
allowb 'if [ -f ~/.claude/settings.json ]; then cat ~/.claude/settings.json; fi' "$P"
allowb 'if [[ -f ~/.claude/settings.json ]]; then echo yes; fi' "$P"
allowb 'for f in ~/.claude/skills/*; do echo "$f"; done' "$P"
allowb 'while read -r l; do echo "$l"; done < ~/.claude/settings.json' "$P"
allowb 'case "$1" in a) cat ~/.claude/settings.json;; esac' "$P"
allowb '! grep -q x ~/.claude/settings.json' "$P"
allowb '(cd ~/.claude/skills && rm -rf old)' "$P"
allowb 'x=$(cd "$(dirname "$0")"; pwd); echo "$x"' "$P"
allowb 'cat > src/hooks/x.sh <<'"'"'EOF'"'"'
if [ -f a ]; then
  echo {a..b} > out.txt; fi
{ echo x; } >> log
EOF' "$P"                                                       # a heredoc body is text

echo "file-guard: a redirection glued to its words is still one"
denyb 'echo x>~/.claude/settings.json' "$P"
denyb 'cat evil>>~/.claude.json' "$P"
denyb 'echo x 1<>~/.ssh/config' "$P"
denyb '(echo x)>~/.claude/settings.json' "$P"
denyb 'git show HEAD:x>.claude/settings.json' "$P"
denyb 'echo x &>~/.claude/settings.json' "$P"
allowb 'echo "a>b" | cat' "$P"
allowb "git log --format='%h>%s' -- .claude" "$P"
allowb 'printf '"'"'%s\n'"'"' "$x" > out.txt' "$P"
allowb "sed -n 's/a/b/p' ~/.claude/settings.json > out" "$P"
allowb 'cat ~/.claude/settings.json > /tmp/backup.json' "$P"   # the target is not protected
allowb 'jq . ~/.claude/settings.json 2>/dev/null' "$P"
allowb 'ls -la ~/.claude/hooks 2>&1 | head' "$P"
allowb 'diff <(jq -S . ~/.claude/settings.json) <(jq -S . new.json)' "$P"

echo "file-guard: every brace group and range is expanded; a glob source counts"
denyb 'tee ~/.claude/{r..t}ettings.json' "$P"
denyb 'tee ~/.{claude,x}/{settings,y}.json' "$P"
denyb 'rm -rf ~/.{claude,x}/{hooks,y}' "$P"
denyb 'rm -r ~/.cla{u..u}de' "$P"
denyb 'rm -rf ~/.{x,{y,claude}}' "$P"                          # nested
denyb 'cp tpl/* ~/.claude/' "$P"
denyb 'ln -sf tpl/* ~/.claude/' "$P"
denyb 'cp tpl/{settings,other}.json ~/.claude/' "$P"
denyb 'install tpl/* ~/.claude/' "$P"
denyb 'cp -t ~/.claude tpl/*' "$P"
denyb 'cp tpl/settings.js?n ~/.claude/' "$P"
allowb 'cp -R tpl/* dist/' "$P"
allowb 'ls ~/.claude/{skills,commands}' "$P"
allowb 'ls ~/.claude/skills/{a..c}' "$P"
allowb 'mkdir -p ~/.claude/skills/{a,b}/{c,d}' "$P"
allowb 'cp tpl/*.md ~/.claude/' "$P"
allowb 'cat ~/.claude/settings.json' "$P"
allowb "grep -r 'x' .claude/" "$P"

echo "file-guard: find -prune spares a .claude dir only on the other side of -o"
denyb 'find ~/.claude -prune -delete' "$P"
denyb 'find ~ -name .claude -prune -exec rm -rf {} +' "$P"
allowb 'find . -name .claude -prune -o -name "*.js" -print' "$P"
allowb 'find . \( -name .claude -prune \) -o -name "*.tmp" -delete' "$P"

echo "file-guard: a git work tree resolves the pathspecs, and one holding ~ is not rewritten"
denyb 'git --work-tree ~ checkout HEAD -- .claude/hooks/x' "$P"
denyb 'GIT_WORK_TREE=~ git checkout HEAD -- .claude/hooks/x' "$P"
denyb 'git -c core.worktree=~ checkout HEAD -- .claude/hooks/x' "$P"
denyb 'git --work-tree=/ checkout -- .' "$P"
denyb 'git --work-tree ~ reset --hard' "$P"
allowb 'git --work-tree ~ status' "$P"
allowb 'git --work-tree ~ diff' "$P"
allowb 'git worktree add ../wt main' "$P"

echo "file-guard: last check — a protected name assembled through quoting is refused"
denyb "bash -c \"rm -rf ~/.cla''ude\"" "$P"                  # only the normalised text names it
denyb "bash -c \$'rm -rf ~/\\x2eclaude'" "$P"
denyb "bash -c 'rm -rf ~/.{claude,x}/{hooks,y}'" "$P"          # a quoted brace word
denyb "sh -c \"tee ~/.claude/{r..t}ettings.json\"" "$P"
denyb "sh -c 'rm -r ${PWD%/*}/${PWD##*/}/ho''oks'" "$P"         # the guard's own directory
allowb "sed 's/\\.claude\\/settings/x/' f > out" "$P"           # \/ is a plain /
allowb 'git commit -m "update .claude/settings.json docs"' "$P"
allowb 'grep -E "\.ssh/|\.aws/" notes.txt' "$P"
allowb 'cat "$HOME"/.claude/settings.json' "$P"
allowb 'cat ~/".claude/settings.json"' "$P"

echo "file-guard: one long line stays linear"
W3=':'; k=0; while [ $k -lt 3000 ]; do W3+=' a'; k=$((k+1)); done; W3+='; echo x > ~/.claude/settings.json'
W10=':'; k=0; while [ $k -lt 10000 ]; do W10+=' a'; k=$((k+1)); done; W10+='; echo x > ~/.claude/settings.json'
within 2 denyb "$W3" "$P"
within 2 denyb "$W10" "$P"

# command names fold like paths on macOS; on Linux RM, Cp, XARGS and GIT are not those commands
$CASEB 'RM -rf ~/.claude' "$P"
$CASEB 'Cp -R /tmp/evil/. ~/.CLAUDE/' "$P"
$CASEB 'echo ~/.claude/settings.json | XARGS rm' "$P"
$CASEB 'GIT checkout -- .Claude/Settings.json' "$P"

K=$PWD                                                          # the kit root: hooks/ is protected here
# within_ms <ms> <denyb|allowb> <cmd> <cwd>: the verdict, and that it arrives inside <ms>
now_ms() { perl -MTime::HiRes=time -e 'printf "%d", time*1000'; }
within_ms() {
  local t0; t0=$(now_ms); "$2" "$3" "$4"
  if [ $(( $(now_ms) - t0 )) -lt "$1" ]; then pass=$((pass+1)); else echo "  ✗ slower than $1 ms: ${3:0:50}…"; fail=$((fail+1)); fi
}

echo "file-guard: a here-document's body is data, its own line is not"
allowb "cat > src/hooks/useCart.ts <<'EOF'
/**
 * useCart — cart state hook. @returns {{items: string[]}}
 */
/* css */
export const useCart = () => ({ a: 1 });
EOF" "$P"
allowb "cat > docs/CONTRIBUTING.md <<'EOF'
| \`.claude/\` | project settings |
\`.claude/\` is not committed
EOF" "$P"
allowb "cat > docs/notes.md <<'EOF'
# Hooks
* file-guard blocks writes
- git is not policed
EOF" "$K"                                                        # bare words that are hooks/ in the kit root
allowb "cat > .gitignore <<'EOF'
node_modules/
.claude/settings.local.json
EOF" "$P"
allowb "cat <<-EOF > docs/x.md
	rm -rf ~/.claude
	EOF" "$P"                                                      # <<- strips the tabs of the delimiter
allowb "cat <<A > a.txt <<B
rm ~/.claude/settings.json
A
rm -rf hooks
B" "$K"                                                          # two bodies, one line
denyb "cat > ~/.claude/settings.json <<'EOF'
{}
EOF" "$P"                                                        # the redirect on its own line still counts
denyb "cat <<'EOF' >> .claude/settings.local.json
{}
EOF" "$P"
denyb "tee hooks/file-guard.sh <<'EOF'
x
EOF" "$K"
denyb "cat <<'EOF' > /tmp/x; rm -rf ~/.claude
data
EOF" "$P"                                                        # the rest of the line is a command
denyb "bash <<'EOF'
rm -rf ~/.claude
EOF" "$P"                                                        # fed to an interpreter: read as before
denyb "cat <<'EOF' | sh
rm ~/.claude/settings.json
EOF" "$P"
denyb "cat <<'EOF' |
rm -rf ~/.claude
EOF
sh" "$P"                                                          # the pipe goes on after the body
denyb "cat <<'EOF' | xargs rm
~/.claude/settings.json
EOF" "$P"
denyb "while read -r f; do rm \"\$f\"; done <<'EOF'
~/.claude/settings.json
EOF" "$P"
denyb "python3 - <<'EOF'
import os; os.remove('$HOME/.claude/settings.json')
EOF" "$P"
denyb "\"\$PY\" - <<'EOF'
rm -rf ~/.claude
EOF" "$P"                                                        # a command word built at run time
denyb "bash\${IFS}<<'EOF'
rm -rf ~/.claude
EOF" "$P"
denyb "f() { bash; }
f <<'EOF'
rm -rf ~/.claude
EOF" "$P"                                                        # a function the command defines
denyb 'cat > x.txt <<EOF
$(rm -rf ~/.claude)
EOF' "$P"                                                        # an unquoted body runs its $( )
denyb 'cat > x.txt <<EOF
`rm -rf ~/.claude`
EOF' "$P"
allowb 'cat > x.txt <<EOF
home is $HOME, see ~/.claude/settings.json
EOF' "$P"
denyb "echo x # <<X
rm -rf ~/.claude
X" "$P"                                                          # a << in a comment, quotes or $(( ))
denyb "echo '<<X'
rm -rf ~/.claude
X" "$P"
denyb 'echo $((1<<X))
rm -rf ~/.claude
X))' "$P"
denyb "echo \"\$(case x in a) echo \"<<X\" ;; esac)\"
rm -rf ~/.claude
X" "$P"
denyb "cat <<\$X
rm -rf ~/.claude
\$X" "$P"                                                        # a delimiter built at run time: read whole
denyb "cat <<'EOF'
rm -rf ~/.claude" "$P"                                           # a body with no end: read whole
denyb "x=\"\$(cat <<'EOF'
foo
EOF)\"
rm -rf ~/.claude
EOF" "$P"                                                        # bash ends the body at EOF) in $( )
denyb "x=\$(cat <<'EOF'
)
rm -rf ~/.claude
EOF
)" "$P"                                                          # bash 3.2 ends the $( ) at that )
denyb "y=\"\$(cat <<'EOF'
a ) b\" ; rm -rf ~/.claude ; echo \"
EOF
)\"" "$P"
denyb "cat <(cat <<'EOF'
)
rm -rf ~/.claude
EOF
)" "$P"                                                          # so does <( )
allowb "( cat <<'EOF'
)
rm -rf ~/.claude
EOF
) > notes.txt" "$P"                                              # a plain ( ) subshell reads it as data
denyb "x=\$(cat <<'EOF'
it's
EOF
)
echo '
) ; rm -rf ~/.claude" "$P"                                       # a quote left open in the body, for bash 3.2
MSG=$(lines 'Refactor the hooks: keep {a,b} and ~/.claude/settings.json out of it, line' 20)
allowb "git commit -m \"\$(cat <<'EOF'
fix(hooks): skip {a,b} in \"quoted\" text

$MSG
EOF
)\"" "$K"
allowb "gh pr create --title x --body \"\$(cat <<'EOF'
## Summary (hooks)
- \`hooks/file-guard.sh\`: {a,b} .claude/settings.json

$MSG
EOF
)\"" "$K"
allowb "python3 - <<'PYEOF'
src = r'''/**
 * a {b, c} doc, $MSG
 */'''
open('src/hooks/gen.ts', 'w').write(src)
PYEOF" "$P"                                                      # fed to python: no glob or brace expansion
HD_BIG="cat > src/hooks/generated.ts <<'EOF'
$(lines 'export const v = (a: number) => ({ hooks: [a], path: ".claude/settings.json" }); // line' 1100)
EOF"
within_ms 500 allowb "$HD_BIG" "$P"                               # ~100 KB, read as data
within_ms 500 allowb "$HD_BIG" "$K"

echo "file-guard: a { inside quotes is not a brace expansion too large to check"
LONG=$(lines 'the hooks keep {a,b} and .claude/settings.json apart, line' 30)
allowb "git commit -m \"$LONG\"" "$K"
allowb "python3 -c '''
x = {\"hooks\": 1}
$LONG
'''" "$K"
BIG=':'; k=0; while [ $k -lt 300 ]; do BIG+=",a$k"; k=$((k+1)); done
denyb "rm -rf ~/.{${BIG#:},claude}" "$P"                          # unquoted: still refused
denyb "python3 -c \"import os; os.system('rm ~/.claude/{settings,x}.json')\"" "$P"   # a string a shell runs: still expanded

echo "file-guard: a for/select list is data; its variable carries what the list named"
allowb 'for f in ~/.claude/*.json; do jq -r .model "$f"; done' "$P"
allowb 'for f in ./*; do echo $f; done' "$K"
allowb 'for f in ~/.claude/*.json; do cp "$f" /tmp/bak/; done' "$P"
allowb 'select f in ~/.claude/*.json; do cat "$f"; break; done' "$P"
denyb 'for f in ~/.claude/settings.json; do rm "$f"; done' "$P"
denyb 'for f in hooks/*.sh; do sed -i "" s/a/b/ "${f}"; done' "$K"
denyb 'for d in ~/.claude; do rm -rf "$d"; done' "$P"

echo "file-guard: an archive's or a copy's sources are read, its target is written"
allowb 'tar czf /tmp/kit.tgz hooks scripts skills' "$K"
allowb 'tar -cf - hooks | gzip > /tmp/h.tgz' "$K"
allowb 'zip -r /tmp/h.zip hooks' "$K"
allowb '7z a /tmp/h.7z hooks' "$K"
allowb 'cp -R hooks /tmp/hooks-copy' "$K"
allowb 'rsync -a hooks/ /tmp/hooks-copy/' "$K"
allowb 'cp ~/.claude/settings.json /tmp/settings.bak' "$P"
allowb 'scp -i ~/.ssh/id_ed25519 notes.txt host:/tmp/' "$P"
allowb "find . -name '*.sh' -path './hooks/*' | xargs shellcheck" "$K"
allowb "find . -path './hooks/*' | xargs wc -l" "$K"
allowb "find . -path './hooks/*' | xargs grep -n deny" "$K"
allowb 'shellcheck hooks/file-guard.sh' "$K"
allowb 'bash -n hooks/file-guard.sh' "$K"
allowb 'uniq -c ~/.claude/settings.json' "$P"
denyb 'bash hooks/file-guard.sh' "$K"
denyb 'bash -n -i hooks/file-guard.sh' "$K"                       # -i ignores -n
denyb 'cp /tmp/x hooks/file-guard.sh' "$K"
denyb 'cp -R /tmp/evil hooks' "$K"
denyb 'cp -t hooks /tmp/x' "$K"
denyb 'cp ~/.ssh/config ~/.ssh/config.bak' "$P"
denyb 'cp -l ~/.claude/settings.json /tmp/x' "$P"                # a hard link to it
denyb 'cp -R hooks ~/.claude/' "$K"                              # into a .claude dir
denyb 'tar xzf /tmp/k.tgz hooks' "$K"
denyb 'tar czf hooks/x.tgz src' "$K"
denyb 'tar czf /tmp/k.tgz --remove-files hooks' "$K"
denyb 'zip -m /tmp/h.zip hooks/file-guard.sh' "$K"
denyb 'zip hooks/x.zip src' "$K"
denyb 'rsync -a --remove-source-files hooks/ /tmp/h/' "$K"
denyb 'rsync -a --log-file hooks/log src/ /tmp/d/' "$K"
denyb 'mv hooks /tmp/x' "$K"
denyb "find . -path './hooks/*' | xargs rm" "$K"
denyb 'uniq /tmp/in ~/.claude/settings.json' "$P"

echo "file-guard: a command over 64 KB gets the cheap checks only, and fast"
W70=':'; k=0; while [ $k -lt 36000 ]; do W70+=' a'; k=$((k+1)); done
within_ms 1000 allowb "$W70" "$P"
within_ms 1000 denyb "$W70; echo x > ~/.claude/settings.json" "$P"
within_ms 1000 denyb "$W70; rm -rf ~/.claude" "$P"
within_ms 1000 denyb "$W70; rm hooks/file-guard.sh" "$K"

echo "file-guard: a heredoc written to a file and run in the same command is code, not data"
denyb $'cat > x.sh <<\'EOF\'\nrm -rf ~/.claude\nEOF\nbash x.sh' "$P"
denyb $'cat > x.sh <<\'EOF\'\nrm -rf ~/.claude\nEOF\nchmod +x x.sh && ./x.sh' "$P"
denyb $'cat > x.py <<\'EOF\'\nopen("x") ; rm ~/.claude/settings.json\nEOF\npython3 x.py' "$P"
allowb $'cat > docs/x.md <<\'EOF\'\n| `.claude/` | settings |\nEOF\ngit add docs/x.md' "$P"

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
