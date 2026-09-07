#!/usr/bin/env bash
# kb-import.sh — the other half of kb-export.sh: drop a project's KB from the hub into a local
# checkout, so a teammate gets the same Knowledge Base the commands read.
#
#   scripts/kb-import.sh <hub-dir> <project> [target-repo]     (target defaults to the current dir)
#   scripts/kb-import.sh --dry-run ~/kb-hub taskflow ~/work/taskflow
#   scripts/kb-import.sh --force   ~/kb-hub taskflow           (replace an existing KB)
#
# Safety: it never silently replaces an existing knowledge-base/. Without --force it stops and shows
# you what differs. It also warns when the snapshot was taken from a commit your checkout does not
# have — a KB describing code you are not on is worse than no KB, because it reads as current.
set -euo pipefail

DRY=0; FORCE=0; args=()
for a in "$@"; do
  case "$a" in
    --dry-run|-n) DRY=1 ;;
    --force|-f) FORCE=1 ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *) args+=("$a") ;;
  esac
done
set -- "${args[@]:-}"

die() { echo "✗ $*" >&2; exit 1; }
run() { if [ "$DRY" = 1 ]; then echo "   would: $*"; else "$@"; fi; }

hub=${1:-}; project=${2:-}; target=${3:-.}
[ -n "$hub" ] && [ -n "$project" ] || die "usage: kb-import.sh <hub-dir> <project> [target-repo]"
[ -d "$hub" ] || die "no such hub: $hub"
hub=$(cd "$hub" && pwd)
src="$hub/projects/$project/knowledge-base"
meta="$hub/projects/$project/_meta.yml"

if [ ! -d "$src" ]; then
  echo "✗ '$project' is not in this hub. Available:" >&2
  ls "$hub/projects" 2>/dev/null | sed 's/^/    /' >&2 || echo "    (none)" >&2
  exit 1
fi
[ -d "$target" ] || die "no such target directory: $target"
target=$(cd "$target" && pwd)

g() { grep -m1 "^$1:" "$meta" 2>/dev/null | cut -d: -f2- | sed 's/^ *//' || true; }
snap_commit=$(g commit); snap_branch=$(g branch); snap_when=$(g exported)
files=$(find "$src" -type f | wc -l | tr -d ' ')

echo "Importing '$project' → $target/knowledge-base"
echo "  snapshot: branch ${snap_branch:-?} · commit ${snap_commit:-?} · exported ${snap_when:-?} · $files files"

# Does the target actually contain the code this KB describes?
if [ -n "$snap_commit" ] && [ "$snap_commit" != "(no git)" ] && git -C "$target" rev-parse --git-dir >/dev/null 2>&1; then
  if git -C "$target" cat-file -e "${snap_commit}^{commit}" 2>/dev/null; then
    here=$(git -C "$target" rev-parse --short HEAD 2>/dev/null || echo "?")
    if [ "$here" != "$snap_commit" ]; then
      behind=$(git -C "$target" rev-list --count "${snap_commit}..HEAD" 2>/dev/null || echo "?")
      echo "  ⚠ your HEAD ($here) is $behind commit(s) past the snapshot — the KB may already be stale here."
    fi
  else
    echo "  ⚠ commit $snap_commit is not in this checkout (different repo, or you need to fetch)."
    echo "    Check you are importing into the right repository."
  fi
fi

dest="$target/knowledge-base"
if [ -d "$dest" ] && [ "$FORCE" != 1 ]; then
  echo
  echo "✗ $dest already exists — not replacing it."
  if command -v diff >/dev/null 2>&1; then
    echo "  Differences (< existing, > incoming):"
    diff -rq "$dest" "$src" 2>/dev/null | sed 's/^/    /' | head -20 || true
  fi
  echo
  echo "  Re-run with --force to replace it (your current KB is NOT backed up by git —"
  echo "  knowledge-base/ is normally gitignored, so copy it aside first if you want it)."
  exit 1
fi

if [ -d "$dest" ] && [ "$FORCE" = 1 ] && [ "$DRY" = 0 ]; then
  bak="$target/knowledge-base.bak-$(date +%Y%m%d-%H%M%S)"
  mv "$dest" "$bak"
  echo "  previous KB moved to $(basename "$bak")"
fi

run mkdir -p "$dest"
run cp -R "$src/." "$dest/"
[ "$DRY" = 1 ] && { echo "(dry run — nothing written)"; exit 0; }

echo "✔ imported. The cwk-* commands in that repo now read this KB."
echo "  It is a snapshot: after the code moves on, run /cwk-rescan there (or re-import a fresh export)."
