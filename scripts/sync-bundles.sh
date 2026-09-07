#!/usr/bin/env bash
# sync-bundles.sh — single source of truth for bundled files.
#
# Canonical copies live in resources/. Each skill that needs one carries its own copy under
# skills/<skill>/references/ (so a skill stays self-contained when copied standalone). This
# script regenerates those copies from resources/ — edit the file ONCE in resources/, run this,
# commit. Run `scripts/sync-bundles.sh --check` in CI to fail if any copy drifted.
#
# (Map-only files — graph-builder.js, build-map.cjs, viewer-template.html — live solely in
#  skills/namht-map/references and are not duplicated, so they're not managed here.)
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
SRC=resources
CHECK="${1:-}"

# canonical-file  ->  space-separated list of skills that bundle it
map_review="namht-build namht-review namht-scan namht-rescan namht-security-audit namht-pr"
map_kb="namht-scan namht-rescan"
map_html="namht-ask namht-document namht-plan namht-qa namht-system-map namht-pr namht-security-audit namht-plan-review namht-retro namht-qa-integration namht-design-review namht-pdf namht-user-story namht-rails-to-spring namht-drift namht-issues namht-runbook"  # html-builder.js + render-html.cjs
map_evidence="namht-ask namht-document namht-user-story namht-plan namht-runbook namht-fix-bug namht-build namht-review namht-qa"  # the reach-ledger + code-graph protocol (docs/provenlens.md)

emit() { # <canonical-file> <skill-list>
  local file="$1"; shift
  for sk in "$@"; do
    local dir="skills/$sk/references"
    if [ ! -d "skills/$sk" ]; then
      if [ "$CHECK" = "--check" ]; then echo "MISSING: skills/$sk (mapped for $file) does not exist"; DRIFT=1; fi
      continue
    fi
    if [ "$CHECK" = "--check" ]; then
      if ! cmp -s "$SRC/$file" "$dir/$file" 2>/dev/null; then echo "DRIFT: $dir/$file ≠ $SRC/$file"; DRIFT=1; fi
    else
      mkdir -p "$dir"; cp "$SRC/$file" "$dir/$file"
    fi
  done
}

sweep() { # <canonical-file> <skill-list> — reverse check: every on-disk copy must be mapped
  local file="$1"; shift
  local mapped=" $* "
  for f in skills/*/references/"$file"; do
    [ -f "$f" ] || continue
    local sk="${f#skills/}"; sk="${sk%%/*}"
    case "$mapped" in
      *" $sk "*) ;;
      *) echo "UNMAPPED: $f exists but $sk is not mapped for $file"; DRIFT=1;;
    esac
  done
}

DRIFT=0
emit review-skills-universal.md $map_review
emit kb-steps.md               $map_kb
emit html-builder.js           $map_html
emit render-html.cjs           $map_html
emit provenlens-evidence.md   $map_evidence

if [ "$CHECK" = "--check" ]; then
  sweep review-skills-universal.md $map_review
  sweep kb-steps.md               $map_kb
  sweep html-builder.js           $map_html
  sweep render-html.cjs           $map_html
  sweep provenlens-evidence.md   $map_evidence
  [ "$DRIFT" = 0 ] && { echo "✔ bundles in sync with resources/"; exit 0; } || { echo "✗ drift — run scripts/sync-bundles.sh to fix"; exit 1; }
fi
# render-html.cjs needs +x
for sk in $map_html; do [ -f "skills/$sk/references/render-html.cjs" ] && chmod +x "skills/$sk/references/render-html.cjs"; done
echo "✔ synced bundles from resources/ into skill references/"
