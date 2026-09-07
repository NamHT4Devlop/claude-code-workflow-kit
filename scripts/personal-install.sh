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
  for h in cwk-git-guard.sh namht-git-guard.sh; do   # the 2.x name too
    [ -L "$DEST/hooks/$h" ] && rm -f "$DEST/hooks/$h" && echo "   - removed hooks/$h"
  done
  echo "✔  Done. Removed our symlinks from $DEST — your repos were never touched."
  echo "   NOTE: the git-guard hook+deny entries in $DEST/settings.json are left as-is — remove them by hand if you want."
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

# ── git-guard hook (read/sync-in git only; block remote-affecting + destructive) ──
mkdir -p "$DEST/hooks"
ln -sfn "$SRC/hooks/git-guard.sh" "$DEST/hooks/cwk-git-guard.sh"
echo "   ✅ linked hooks/cwk-git-guard.sh"
# A 2.x install armed settings.json with hooks/namht-git-guard.sh. Removing that link would not
# disarm anything visibly — a hook whose file is gone just stops running — so keep the old name
# alive as an alias until settings.json names the new one.
if [ -L "$DEST/hooks/namht-git-guard.sh" ]; then
  ln -sfn "$SRC/hooks/git-guard.sh" "$DEST/hooks/namht-git-guard.sh"
  echo "   ⚠  kept the 2.x alias hooks/namht-git-guard.sh — point settings.json at hooks/cwk-git-guard.sh, then uninstall/install once to drop it"
fi
echo "   ⚠  To ARM the git guard, add this to $DEST/settings.json (one time):"
echo '        hooks.PreToolUse += { "matcher":"Bash", "hooks":[{"type":"command",'
echo "          \"command\":\"$DEST/hooks/cwk-git-guard.sh\",\"timeout\":10}] }"
echo '        permissions.deny += "Bash(git push:*)", "Bash(git reset --hard:*)", … (see SECURITY.md)'

echo "✔  Done. Open Claude Code in any project and use /cwk-build, /cwk-ask, /cwk-review, …"
echo "   Upgrading from 2.x? Rename each repo's namht-sessions/ with scripts/migrate-sessions.sh and add cwk-sessions/ to ~/.gitignore_global."
echo "   (Skills also auto-activate from plain English — slash commands are optional.)"
