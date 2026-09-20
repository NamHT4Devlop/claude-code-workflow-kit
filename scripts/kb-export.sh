#!/usr/bin/env bash
# kb-export.sh — collect the knowledge-base/ of several repos into ONE hub repo, namespaced by
# project, so a team can pull the hub and drop a project's KB into their own checkout.
#
#   scripts/kb-export.sh [--dry-run] [--with-source] [--allow-secrets] <hub-dir> <repo> [repo...]
#   scripts/kb-export.sh --dry-run ~/kb-hub ~/work/taskflow ~/work/billing
#
# Before a project is copied its KB (and runbook) Markdown is scanned for secret-looking strings
# (AWS keys, GitHub/Slack/OpenAI tokens, private keys, user:password@ URLs). A hit prints file:line
# (masked), skips that project and makes the run exit non-zero; --allow-secrets exports it anyway.
# Credentials inside the origin URL (https://user:token@host/…) are stripped before it is recorded.
#
# Layout it writes:
#   <hub>/projects/<project>/knowledge-base/…   the KB, verbatim
#   <hub>/projects/<project>/runbook/…          the repo's cwk-sessions/runbook/, when it has one
#   <hub>/projects/<project>/code-graph.html    the newest /cwk-map page, with its embedded SOURCE
#                                               TEXT STRIPPED (symbols, edges, call-site lines stay)
#   <hub>/projects/<project>/_meta.yml          identity: repo, branch, commit, date, counts,
#                                               code_graph: stripped | with-source | none
#   <hub>/README.md                             an index table of every project in the hub
#
# --with-source copies the code-graph page raw. A full-index /cwk-map page embeds the text of every
# indexed file so the explorer works offline; a hub is pushed and emailed, so by default that text
# is removed (scripts/strip-map-source.cjs) and the hub carries the graph, never the code.
#
# ⚠️ READ THIS BEFORE POINTING IT AT A COMPANY REPO
# A Knowledge Base is a distilled description of your source: business rules, data model, auth model,
# endpoints. It is DERIVED FROM the code and is often more sensitive per page than the code itself,
# because it is the readable version. The hub repo must be **private** and shared only with people
# who already have access to those repos. This script checks GitHub visibility when it can, refuses
# to write into a repo it can see is public, and NEVER pushes — you review and push yourself.
set -euo pipefail

DRY=0; WITH_SOURCE=0; ALLOW_SECRETS=0; args=()
for a in "$@"; do
  case "$a" in
    --dry-run|-n) DRY=1 ;;
    --with-source) WITH_SOURCE=1 ;;
    --allow-secrets) ALLOW_SECRETS=1 ;;
    -h|--help) sed -n '2,31p' "$0"; exit 0 ;;
    *) args+=("$a") ;;
  esac
done
set -- "${args[@]:-}"

die() { echo "✗ $*" >&2; exit 1; }
run() { if [ "$DRY" = 1 ]; then echo "   would: $*"; else "$@"; fi; }

# A remote URL can carry credentials (https://user:token@host/…). It is written into _meta.yml, the
# hub README and the hub page — three places a token must never land. Drop everything between the
# scheme and the '@'; ssh://git@host and git@host: forms carry no secret and pass through untouched.
redact_url() { printf '%s' "$1" | sed -E 's#(https?://)[^/@]+@#\1#'; }

# Secret patterns a KB page must not carry into a hub. A KB is prose distilled from code, and a scan
# that quoted a config file quotes its token too. Matched text is printed masked to 6 characters.
SECRET_RE='AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{20,}|gh[ousr]_[A-Za-z0-9]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY|xox[baprs]-|sk-[A-Za-z0-9]{20,}|https?://[^/@[:space:]]+:[^/@[:space:]]+@'
scan_secrets() { # <dir>... — prints masked file:line hits to stderr; returns 1 when any were found
  local hits=0 line loc rest no m
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    hits=$((hits+1))
    loc="${line%%:*}"; rest="${line#*:}"; no="${rest%%:*}"; m="${rest#*:}"   # file:lineno:match
    echo "   secret: $loc:$no: ${m:0:6}…" >&2
  done < <(grep -rnoE --include='*.md' "$SECRET_RE" "$@" 2>/dev/null || true)
  [ "$hits" -eq 0 ]
}

hub=${1:-}; shift || true
[ -n "$hub" ] || die "usage: kb-export.sh [--dry-run] [--with-source] <hub-dir> <repo> [repo...]"
[ $# -gt 0 ] || die "give me at least one repo to export"
mkdir -p "$hub"
hub=$(cd "$hub" && pwd)
here=$(cd "$(dirname "$0")" && pwd)
STRIP="$here/strip-map-source.cjs"
if [ "$WITH_SOURCE" = 1 ]; then
  echo "⚠️  --with-source: the hub will contain the SOURCE TEXT of every indexed file inside code-graph.html — share it only where the code itself may go."
fi

# --- refuse to write into a repo we can see is public -----------------------------
if [ -d "$hub/.git" ] && command -v gh >/dev/null 2>&1; then
  vis=$(cd "$hub" && gh repo view --json visibility -q .visibility 2>/dev/null || true)
  if [ "$vis" = "PUBLIC" ]; then
    die "the hub repo is PUBLIC. A KB describes your source in readable form — make it private first
    (gh repo edit --visibility private), or export to a different location."
  fi
  [ -n "$vis" ] && echo "· hub visibility: $vis"
fi

ok=0; skipped=0; secrets_blocked=0
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
  origin=$(redact_url "$(git -C "$repo" config --get remote.origin.url 2>/dev/null || echo "(no remote)")")
  today=$(date +%F)

  # Secret scan before anything is copied: a hit skips the project and fails the run, because the
  # hub is what gets pushed and shared. --allow-secrets exports anyway (the hits are still printed).
  scan_dirs=("$kb"); [ -d "$repo/cwk-sessions/runbook" ] && scan_dirs+=("$repo/cwk-sessions/runbook")
  if ! scan_secrets "${scan_dirs[@]}"; then
    if [ "$ALLOW_SECRETS" = 1 ]; then
      echo "   ! $project — secret-looking strings found (listed above); exporting anyway (--allow-secrets)" >&2
    else
      echo "✗ $project — secret-looking strings found in its KB/runbook (listed above)." >&2
      echo "    Remove them at the source, or pass --allow-secrets if they are false positives." >&2
      skipped=$((skipped+1)); secrets_blocked=$((secrets_blocked+1)); continue
    fi
  fi

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
  # the KB's own _meta.yml travels inside the copy too — redact the remote URL there as well
  if [ "$DRY" = 0 ] && [ -f "$dest/knowledge-base/_meta.yml" ]; then
    sed -E 's#(https?://)[^/@]+@#\1#g' "$dest/knowledge-base/_meta.yml" > "$dest/knowledge-base/_meta.yml.tmp" \
      && mv "$dest/knowledge-base/_meta.yml.tmp" "$dest/knowledge-base/_meta.yml"
  fi

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
  # A full-index page also embeds the TEXT of every indexed file (so the explorer can show a symbol's
  # body offline). The hub is pushed and emailed, so that text is stripped on the way in unless the
  # caller said --with-source; symbols, edges and call-site lines are kept.
  graph=$(ls -t "$repo"/cwk-sessions/maps/*.html 2>/dev/null | head -1 || true)
  code_graph=none
  if [ -n "$graph" ]; then
    if [ "$WITH_SOURCE" = 1 ]; then
      echo "   + code graph ($(basename "$graph")) — WITH SOURCE"
      run cp "$graph" "$dest/code-graph.html"
      code_graph=with-source
    elif [ "$DRY" = 1 ]; then
      echo "   would: strip source from $(basename "$graph") → $dest/code-graph.html"
      code_graph=stripped
    elif command -v node >/dev/null 2>&1 && [ -f "$STRIP" ]; then
      rc=0; node "$STRIP" "$graph" "$dest/code-graph.html" >/dev/null 2>"$dest/.strip.err" || rc=$?
      if [ "$rc" = 0 ]; then
        echo "   + code graph ($(basename "$graph")) — source stripped"
        code_graph=stripped
      elif [ "$rc" = 2 ]; then
        # Not a full-index page (the older sampled viewer embeds no source): copy it as it is.
        echo "   + code graph ($(basename "$graph")) — not a full-index page, copied unchanged"
        cp "$graph" "$dest/code-graph.html"
        code_graph=stripped
      else
        echo "✗ $project — could not strip source from $(basename "$graph"); code graph NOT exported (use --with-source to copy it raw):" >&2
        sed 's/^/    /' "$dest/.strip.err" >&2
        rm -f "$dest/code-graph.html"
      fi
      rm -f "$dest/.strip.err"
    else
      echo "✗ $project — node (or $STRIP) is missing, so the code graph cannot be stripped; NOT exported (use --with-source to copy it raw)" >&2
      rm -f "$dest/code-graph.html"
    fi
  fi

  # Data classification travels with the KB (resources/kb-steps.md, _meta.yml). A KB that predates
  # the key, or one whose value is not one of the four, is `internal` — never silently `public`.
  classification=$(grep -m1 '^classification:' "$kb/_meta.yml" 2>/dev/null | cut -d: -f2- | tr -d ' \r' | tr 'A-Z' 'a-z' || true)
  case "$classification" in public|internal|confidential|restricted) ;; *) classification=internal ;; esac

  if [ "$DRY" = 0 ]; then
    if [ -f "$kb/_meta.yml" ]; then
      # same redaction as $origin: a scan that wrote the raw remote URL must not leak it via the hub;
      # the classification line is rewritten with the normalised value (an unknown word is `internal`)
      sed -E -e 's#(https?://)[^/@]+@#\1#g' -e '/^classification:/d' "$kb/_meta.yml" > "$dest/_meta.yml"
      # the export stamp is added even when the KB carries its own meta
      printf 'exported: %s\nexported_from: %s\ncode_graph: %s\nclassification: %s\n' "$today" "$repo" "$code_graph" "$classification" >> "$dest/_meta.yml"
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
code_graph: $code_graph
classification: $classification
files: $files
EOF
    fi
    # Audit trail: what left which repo, at which commit, to where, under which classification.
    [ -f "$here/audit-log.sh" ] && bash "$here/audit-log.sh" kb.export "repo=$origin" "commit=$commit" \
      "project=$project" "hub=$hub" "classification=$classification" "code_graph=$code_graph" || true
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
    echo "| Project | Classification | Branch | Commit | Exported | Files |"
    echo "|---|---|---|---|---|---|"
    for d in "$hub"/projects/*/; do
      [ -d "$d" ] || continue
      n=$(basename "$d"); m="$d/_meta.yml"
      g() { grep -m1 "^$1:" "$m" 2>/dev/null | cut -d: -f2- | sed 's/^ *//' || true; }
      c=$(g classification); c=${c:-internal}
      echo "| [$n](projects/$n/knowledge-base/) | $c | $(g branch) | $(g commit) | $(g exported) | $(find "$d/knowledge-base" -type f 2>/dev/null | wc -l | tr -d ' ') |"
    done
    echo
    echo "> A KB is a readable distillation of source code — business rules, data model, auth model."
    echo "> Keep this repository **private** and share it only with people who already have access to"
    echo "> the repos above. The **Classification** column is each KB's own \`_meta.yml\` value"
    echo "> (\`public | internal | confidential | restricted\`; \`internal\` when the KB did not say) —"
    echo "> \`confidential\` and \`restricted\` pages must not be emailed or pasted outside that circle."
  } > "$hub/README.md"
fi

# --- browsable page ------------------------------------------------------------------
# A hub is otherwise a folder of Markdown nobody opens. Build the one-page site so the export is
# immediately readable by someone who will never run a terminal.
if [ "$DRY" = 0 ] && [ "$ok" -gt 0 ] && command -v node >/dev/null 2>&1; then
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
if [ "$secrets_blocked" -gt 0 ]; then
  echo "✗ $secrets_blocked project(s) NOT exported because of secret-looking strings (see above)" >&2
  exit 2
fi
exit 0
