#!/usr/bin/env bash
# kb-export.sh — collect the knowledge-base/ of several repos into ONE hub repo, namespaced by
# project, so a team can pull the hub and drop a project's KB into their own checkout.
#
#   scripts/kb-export.sh <hub-dir> <repo> [repo...]
#   scripts/kb-export.sh --dry-run ~/kb-hub ~/work/taskflow ~/work/billing
#
# Layout it writes:
#   <hub>/projects/<project>/knowledge-base/…   the KB, verbatim
#   <hub>/projects/<project>/runbook/…          the repo's cwk-sessions/runbook/, when it has one
#   <hub>/projects/<project>/_meta.yml          identity: repo, branch, commit, date, counts
#   <hub>/README.md                             an index table of every project in the hub
#
# ⚠️ READ THIS BEFORE POINTING IT AT A COMPANY REPO
# A Knowledge Base is a distilled description of your source: business rules, data model, auth model,
# endpoints. It is DERIVED FROM the code and is often more sensitive per page than the code itself,
# because it is the readable version. The hub repo must be **private** and shared only with people
# who already have access to those repos. This script checks GitHub visibility when it can, refuses
# to write into a repo it can see is public, and NEVER pushes — you review and push yourself.
set -euo pipefail

DRY=0; args=()
for a in "$@"; do
  case "$a" in
    --dry-run|-n) DRY=1 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) args+=("$a") ;;
  esac
done
set -- "${args[@]:-}"

die() { echo "✗ $*" >&2; exit 1; }
run() { if [ "$DRY" = 1 ]; then echo "   would: $*"; else "$@"; fi; }

hub=${1:-}; shift || true
[ -n "$hub" ] || die "usage: kb-export.sh [--dry-run] <hub-dir> <repo> [repo...]"
[ $# -gt 0 ] || die "give me at least one repo to export"
mkdir -p "$hub"
hub=$(cd "$hub" && pwd)

# --- refuse to write into a repo we can see is public -----------------------------
if [ -d "$hub/.git" ] && command -v gh >/dev/null 2>&1; then
  vis=$(cd "$hub" && gh repo view --json visibility -q .visibility 2>/dev/null || true)
  if [ "$vis" = "PUBLIC" ]; then
    die "the hub repo is PUBLIC. A KB describes your source in readable form — make it private first
    (gh repo edit --visibility private), or export to a different location."
  fi
  [ -n "$vis" ] && echo "· hub visibility: $vis"
fi

ok=0; skipped=0
for repo in "$@"; do
  [ -d "$repo" ] || { echo "✗ $repo — not a directory"; skipped=$((skipped+1)); continue; }
  repo=$(cd "$repo" && pwd)
  kb="$repo/knowledge-base"
  if [ ! -d "$kb" ]; then
    echo "· $(basename "$repo") — no knowledge-base/ (run /cwk-scan there first)"; skipped=$((skipped+1)); continue
  fi

  project=$(basename "$repo")
  dest="$hub/projects/$project"
  files=$(find "$kb" -type f | wc -l | tr -d ' ')

  # identity: prefer the KB's own _meta.yml, else synthesise it from git (KBs predate that file)
  branch=$(git -C "$repo" branch --show-current 2>/dev/null || echo "(unknown)")
  commit=$(git -C "$repo" rev-parse --short HEAD 2>/dev/null || echo "(no git)")
  origin=$(git -C "$repo" config --get remote.origin.url 2>/dev/null || echo "(no remote)")
  today=$(date +%F)

  # Two repos can share a folder name (~/clientA/api and ~/clientB/api). Namespacing by basename
  # alone would silently replace one client's business rules with another's, under a name that still
  # looks right — and the export is what the team then reads. Refuse instead.
  if [ -f "$dest/_meta.yml" ]; then
    prev=$(grep -m1 '^exported_from:' "$dest/_meta.yml" 2>/dev/null | cut -d: -f2- | sed 's/^ *//')
    if [ -n "$prev" ] && [ "$prev" != "$repo" ]; then
      echo "✗ $project — this hub already holds an export of a DIFFERENT repo under that name:" >&2
      echo "    existing: $prev" >&2
      echo "    incoming: $repo" >&2
      echo "    Rename one of the folders, or export it to a separate hub." >&2
      skipped=$((skipped+1)); continue
    fi
  fi

  echo "→ $project — $files KB files @ $branch/$commit"
  run mkdir -p "$dest"
  run rm -rf "$dest/knowledge-base"
  run cp -R "$kb" "$dest/knowledge-base"

  # Runbooks are the operational half of the same picture, and kb-site.cjs renders them beside the
  # KB in one searchable page. They live under cwk-sessions/, which is gitignored, so a hub is the
  # only place a teammate can read one. Absence is normal, not an error.
  rb="$repo/cwk-sessions/runbook"
  if [ -d "$rb" ]; then
    echo "   + $(find "$rb" -name '*.md' | wc -l | tr -d ' ') runbook page(s)"
    run rm -rf "$dest/runbook"
    run cp -R "$rb" "$dest/runbook"
  fi

  # The newest /cwk-map output, if there is one. It is a self-contained page with its own per-node
  # search, so it travels as a sibling file and kb-site.cjs links to it rather than inlining it --
  # a few hundred KB per project inside one page would make the page the thing nobody opens.
  graph=$(ls -t "$repo"/cwk-sessions/maps/*.html 2>/dev/null | head -1 || true)
  if [ -n "$graph" ]; then
    echo "   + code graph ($(basename "$graph"))"
    run cp "$graph" "$dest/code-graph.html"
  fi

  if [ "$DRY" = 0 ]; then
    if [ -f "$kb/_meta.yml" ]; then
      cp "$kb/_meta.yml" "$dest/_meta.yml"
      # the export stamp is added even when the KB carries its own meta
      printf 'exported: %s\nexported_from: %s\n' "$today" "$repo" >> "$dest/_meta.yml"
    else
      cat > "$dest/_meta.yml" <<EOF
# Synthesised at export time — this KB predates cwk-scan writing its own _meta.yml.
# Rerun /cwk-scan or /cwk-rescan in the source repo to get a richer one.
project: $project
repo: $origin
branch: $branch
commit: $commit
generated: (unknown — KB has no _meta.yml)
exported: $today
exported_from: $repo
files: $files
EOF
    fi
  fi
  ok=$((ok+1))
done

# --- index ------------------------------------------------------------------------
if [ "$DRY" = 0 ] && [ "$ok" -gt 0 ]; then
  {
    echo "# Knowledge Base hub"
    echo
    echo "Generated Knowledge Bases for several repos, collected by \`scripts/kb-export.sh\`."
    echo "**Each folder is a snapshot** of one repo's \`knowledge-base/\` at the commit named below —"
    echo "it does not update itself. Re-export after a \`/cwk-rescan\`."
    echo
    echo "To use one in your own checkout:"
    echo '```bash'
    echo "scripts/kb-import.sh <this-hub> <project> <your-local-repo>"
    echo '```'
    echo
    echo "| Project | Branch | Commit | Exported | Files |"
    echo "|---|---|---|---|---|"
    for d in "$hub"/projects/*/; do
      [ -d "$d" ] || continue
      n=$(basename "$d"); m="$d/_meta.yml"
      g() { grep -m1 "^$1:" "$m" 2>/dev/null | cut -d: -f2- | sed 's/^ *//' || true; }
      echo "| [$n](projects/$n/knowledge-base/) | $(g branch) | $(g commit) | $(g exported) | $(find "$d/knowledge-base" -type f 2>/dev/null | wc -l | tr -d ' ') |"
    done
    echo
    echo "> A KB is a readable distillation of source code — business rules, data model, auth model."
    echo "> Keep this repository **private** and share it only with people who already have access to"
    echo "> the repos above."
  } > "$hub/README.md"
fi

# --- browsable page ------------------------------------------------------------------
# A hub is otherwise a folder of Markdown nobody opens. Build the one-page site so the export is
# immediately readable by someone who will never run a terminal.
if [ "$DRY" = 0 ] && [ "$ok" -gt 0 ] && command -v node >/dev/null 2>&1; then
  here=$(cd "$(dirname "$0")" && pwd)
  if [ -f "$here/kb-site.cjs" ]; then
    node "$here/kb-site.cjs" "$hub" >/dev/null 2>&1 && echo "· built $hub/index.html (open it in a browser)"
  fi
fi

echo
echo "✔ exported $ok project(s), skipped $skipped → $hub"
[ "$DRY" = 1 ] && echo "(dry run — nothing written)"
if [ "$DRY" = 0 ] && [ -d "$hub/.git" ]; then
  echo "Review and commit it yourself — this script deliberately does not commit or push:"
  echo "  cd $hub && git status"
fi
exit 0
