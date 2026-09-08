#!/usr/bin/env bash
# kb-pipeline.sh — run the whole documentation chain over one or more repos, then publish it as
# one searchable web page.
#
#   scripts/kb-pipeline.sh [options] <repo> [repo...]
#
# Per repo, in order, skipping whatever is already there:
#   1. provenlens init      — so the KB, the runbook and the graph rest on resolved calls, not grep
#   2. /cwk-scan <depth>    — the Knowledge Base (what the system means)
#   3. /cwk-runbook         — the operational half (what to do when it breaks)
#   4. /cwk-map             — the code graph, a page with its own per-node search
# Then, across all of them:
#   5. kb-export.sh + kb-site.cjs — one page: KB + runbook searchable, code graph one click away
#
# Options:
#   --depth quick|standard|deep   scan depth (default: standard)
#   --hub <dir>                   where to publish (default: ~/kb-hub)
#   --model <name>                passed to `claude --model`
#   --permission-mode <mode>      passed to `claude --permission-mode` (default: acceptEdits)
#   --force                       redo a step whose output already exists
#   --dry-run                     print every command, run nothing
#   --yes                         skip the confirmation
#
# It does NOT clone anything: point it at checkouts you already have. Steps 2-4 spend tokens
# through `claude -p`, and a scan is the most expensive thing in this kit — hence the estimate and
# the prompt before any of it runs.
#
# PERMISSIONS. A headless `claude -p` cannot answer an approval prompt, so with the CLI default it
# refuses to write and the scan produces nothing (verified: "Việc ghi file bị từ chối quyền").
# The default here is `acceptEdits`, which lets the skills write the Knowledge Base and the runbook.
# Steps that shell out — the HTML render, git reads, /cwk-map — still need Bash approval and will be
# skipped or degrade under it. `--permission-mode bypassPermissions` is what makes every step run,
# and is what the VS Code panel uses; it also permits ANY Bash command, writes outside the workspace
# and network calls, so it belongs in a workspace you trust. The git-guard hook still applies in
# either mode (PreToolUse runs before the permission check), but that is defence in depth, not a
# sandbox. Whichever mode is in effect is printed in the plan before you confirm.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPTH=standard; HUB="$HOME/kb-hub"; MODEL=""; PERM=acceptEdits; FORCE=0; DRY=0; YES=0; repos=()

while [ $# -gt 0 ]; do
  case "$1" in
    --depth) DEPTH="${2:-}"; shift 2;;
    --hub)   HUB="${2:-}";   shift 2;;
    --model) MODEL="${2:-}"; shift 2;;
    --permission-mode) PERM="${2:-}"; shift 2;;
    --force) FORCE=1; shift;;
    --dry-run|-n) DRY=1; shift;;
    --yes|-y) YES=1; shift;;
    -h|--help) sed -n '2,40p' "$0"; exit 0;;
    *) repos+=("$1"); shift;;
  esac
done

die() { echo "✗ $*" >&2; exit 1; }
[ ${#repos[@]} -gt 0 ] || die "give me at least one repo path (this script never clones — see --help)"
case "$DEPTH" in quick|standard|deep) ;; *) die "--depth must be quick, standard or deep (got '$DEPTH')";; esac
case "$PERM" in acceptEdits|bypassPermissions|auto|dontAsk|manual|plan) ;;
  *) die "--permission-mode must be one the CLI accepts (got '$PERM')";; esac

command -v claude >/dev/null 2>&1 || die "the 'claude' CLI is not on PATH — steps 2-4 run through it"
command -v node   >/dev/null 2>&1 || die "node is not on PATH — steps 4-5 need it"
HAVE_PL=0; command -v provenlens >/dev/null 2>&1 && HAVE_PL=1

run() { if [ "$DRY" = 1 ]; then echo "   would: $*"; else "$@"; fi; }

# ── resolve and classify every repo BEFORE anything runs, so the plan is the whole truth ──
plan=(); skipped=0
for r in "${repos[@]}"; do
  if [ ! -d "$r" ]; then echo "✗ $r — not a directory"; skipped=$((skipped+1)); continue; fi
  abs=$(cd "$r" && pwd)
  name=$(basename "$abs")
  todo=""
  [ "$HAVE_PL" = 1 ] && { [ -d "$abs/.provenlens" ] && [ "$FORCE" = 0 ] || todo="$todo index"; }
  { [ -d "$abs/knowledge-base" ] && [ "$FORCE" = 0 ]; } || todo="$todo scan"
  { ls "$abs"/cwk-sessions/runbook/*.md >/dev/null 2>&1 && [ "$FORCE" = 0 ]; } || todo="$todo runbook"
  { ls "$abs"/cwk-sessions/maps/*.html  >/dev/null 2>&1 && [ "$FORCE" = 0 ]; } || todo="$todo map"
  src=$(find "$abs" -type f \( -name '*.java' -o -name '*.rb' -o -name '*.ts' -o -name '*.tsx' \
        -o -name '*.js' -o -name '*.jsx' -o -name '*.cjs' -o -name '*.mjs' \) \
        -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null | wc -l | tr -d ' ')
  plan+=("$abs|$name|${todo:- (nothing to do)}|$src")
done
[ ${#plan[@]} -gt 0 ] || die "nothing to do"

echo "Plan — depth '$DEPTH', permission-mode '$PERM', publishing to $HUB"
echo
printf '  %-26s %-34s %s\n' REPO "STEPS" "SOURCE FILES"
for row in "${plan[@]}"; do
  IFS='|' read -r _abs name todo src <<< "$row"
  printf '  %-26s %-34s %s\n' "$name" "$todo" "$src"
done
[ "$HAVE_PL" = 0 ] && echo "
  ⚠ provenlens is not on PATH: the KB, runbook and graph will be grep-depth and will say so."
cat <<TXT

  A scan is the most expensive thing in this kit — 'deep' reads every file with no sampling.
  Each step runs 'claude -p' and spends tokens. Steps already done are skipped (--force redoes them).
TXT
if [ "$PERM" != bypassPermissions ]; then cat <<TXT
  Permission mode '$PERM' lets the skills WRITE, but anything shelling out (HTML render, git,
  /cwk-map) still needs approval a headless run cannot give, and will degrade or be skipped.
  Use --permission-mode bypassPermissions for a complete run, in a workspace you trust.
TXT
fi
if [ "$DRY" = 0 ] && [ "$YES" != 1 ]; then
  printf 'Run this? [y/N] '; read -r a; [ "$a" = y ] || [ "$a" = Y ] || die "aborted"
fi

CL=(claude --permission-mode "$PERM"); [ -n "$MODEL" ] && CL+=(--model "$MODEL")
did=(); failed=0

for row in "${plan[@]}"; do
  IFS='|' read -r abs name todo _src <<< "$row"
  echo; echo "▶ $name"
  cd "$abs" || { echo "  ✗ cannot enter $abs"; failed=$((failed+1)); continue; }

  case "$todo" in *index*)
    echo "  · provenlens init"; run provenlens init . || echo "  ⚠ index failed — continuing at grep depth";;
  esac
  case "$todo" in *scan*)
    echo "  · /cwk-scan $DEPTH"; run "${CL[@]}" -p "/cwk-scan $DEPTH" || { echo "  ✗ scan failed"; failed=$((failed+1)); continue; };;
  esac
  case "$todo" in *runbook*)
    echo "  · /cwk-runbook";     run "${CL[@]}" -p "/cwk-runbook" || echo "  ⚠ runbook failed — continuing";;
  esac
  case "$todo" in *map*)
    echo "  · /cwk-map";         run node "$HERE/../skills/cwk-map/references/build-map.cjs" . || echo "  ⚠ map failed — continuing";;
  esac
  did+=("$abs")
done

echo
if [ ${#did[@]} -eq 0 ]; then echo "Nothing was processed."; exit 1; fi
echo "▶ publishing $HUB"
run bash "$HERE/kb-export.sh" "$HUB" "${did[@]}" || die "export failed"
run node "$HERE/kb-site.cjs" "$HUB" || die "site build failed"
echo
if [ "$failed" -gt 0 ]; then echo "✔ done — but $failed repo(s) had a failing step, see above"
else echo "✔ done"; fi
echo "  open: $HUB/index.html    (search covers every KB page and runbook; each project links its code graph)"
