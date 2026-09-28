#!/usr/bin/env bash
# personal-install.sh — install for YOUR user only (zero footprint in any repo).
#
# Symlinks this repo's skills/agents/commands into ~/.claude so they're available in every
# project but live only in your home dir — never inside (or committed to) a project repo.
# Skills/agents are named `cwk-*`. Command files are unprefixed in the repo (so the plugin
# form is clean: /cwk:build); this installer symlinks them WITH a `cwk-` prefix, so the
# personal form is /cwk-build, /cwk-ask, … (won't shadow built-ins like /help).
# Symlinks mean `git pull` here instantly updates you.
#
# Usage:
#   scripts/personal-install.sh            # install / refresh (idempotent)
#   scripts/personal-install.sh uninstall  # remove only the symlinks pointing back here
#
# Pick ONE install method — if you use this, do NOT also `/plugin install` the same plugin.

set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # repo root
# Overridable so the install/uninstall logic can be exercised against a throwaway directory.
# This is the only script in the kit that DELETES files under ~/.claude, and it was previously
# untestable for exactly that reason — a regression widening unlink_ours would have shipped blind.
DEST="${CWK_CLAUDE_DIR:-$HOME/.claude}"

# Remove any symlink under $DEST/{skills,commands,agents} that resolves back into $SRC.
unlink_ours() {
  for sub in skills commands agents; do
    local dir="$DEST/$sub"
    [ -d "$dir" ] || continue
    for entry in "$dir"/*; do
      [ -L "$entry" ] || continue
      local target; target="$(readlink "$entry" || true)"
      case "$target" in
        "$SRC"/*) rm -f "$entry"; echo "   - removed $sub/$(basename "$entry")";;
      esac
    done
  done
}

if [ "${1:-install}" = "uninstall" ]; then
  echo "▶  Uninstalling (personal)…"
  unlink_ours
  # links to hooks this kit no longer ships (git-guard removed in 4.0.0, file-guard in 6.0.0)
  for h in cwk-file-guard.sh cwk-git-guard.sh namht-git-guard.sh; do
    [ -L "$DEST/hooks/$h" ] && rm -f "$DEST/hooks/$h" && echo "   - removed hooks/$h"
  done
  echo "✔  Done. Removed our symlinks from $DEST — your repos were never touched."
  echo "   NOTE: any hook or permissions entries in $DEST/settings.json are left as-is — remove them by hand if you want."
  exit 0
fi

echo "▶  Installing for this user only"
echo "   source: $SRC"
echo "   dest:   $DEST  (symlinks)"
mkdir -p "$DEST/skills" "$DEST/agents" "$DEST/commands"
unlink_ours   # clean any stale links first (e.g. after a rename), then relink fresh

n_s=0; n_a=0; n_c=0
for d in "$SRC"/skills/*/;     do [ -d "$d" ] && ln -sfn "${d%/}" "$DEST/skills/$(basename "$d")"   && n_s=$((n_s+1)); done
for f in "$SRC"/agents/*.md;   do [ -f "$f" ] && ln -sfn "$f"     "$DEST/agents/$(basename "$f")"   && n_a=$((n_a+1)); done
for f in "$SRC"/commands/*.md; do [ -f "$f" ] && ln -sfn "$f"     "$DEST/commands/cwk-$(basename "$f")" && n_c=$((n_c+1)); done

echo "   ✅ linked $n_s skills, $n_a agents, $n_c commands"

# The kit ships no hooks: git-guard was removed in 4.0.0, file-guard in 6.0.0. Their old links now
# point at nothing; drop them, and say so if settings.json still names one — a registered hook whose
# file is gone fails on every call it matches.
for h in cwk-file-guard.sh cwk-git-guard.sh namht-git-guard.sh; do
  [ -L "$DEST/hooks/$h" ] && rm -f "$DEST/hooks/$h" && echo "   - removed the retired link hooks/$h"
done
if [ -f "$DEST/settings.json" ] && grep -Eq 'file-guard|git-guard' "$DEST/settings.json"; then
  echo "   ⚠  $DEST/settings.json still registers a retired cwk hook (file-guard or git-guard). Remove it:"
  echo "        jq '.hooks.PreToolUse |= map(select(any(.hooks[]; .command | test(\"file-guard|git-guard\")) | not))' \\"
  echo "          $DEST/settings.json > /tmp/s.json && mv /tmp/s.json $DEST/settings.json"
fi

echo "✔  Done. Open Claude Code in any project and use /cwk-build, /cwk-ask, /cwk-review, …"
echo "   Upgrading from 2.x? Rename each repo's namht-sessions/ with scripts/migrate-sessions.sh and add cwk-sessions/ to ~/.gitignore_global."
echo "   (Skills also auto-activate from plain English — slash commands are optional.)"
