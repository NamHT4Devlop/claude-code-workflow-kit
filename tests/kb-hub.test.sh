#!/usr/bin/env bash
# kb-hub.test.sh — kb-export.sh copies Knowledge Bases (a readable distillation of source code) out
# of repos, and kb-import.sh drops them into someone else's checkout. Both move real work around and
# neither may lose it, so every branch gets a fixture.
set -uo pipefail
cd "$(dirname "$0")/.."
EXPORT="$PWD/scripts/kb-export.sh"
IMPORT="$PWD/scripts/kb-import.sh"
pass=0; fail=0
ok()   { echo "  ✓ $1"; pass=$((pass+1)); }
bad()  { echo "  ✗ $1"; fail=$((fail+1)); }
check(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (want '$3', got '$2')"; fi; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

mk_repo() {  # <name> — a repo with a small KB
  local r="$TMP/$1"; mkdir -p "$r/knowledge-base/modules"
  printf '# 01 structure\n' > "$r/knowledge-base/01-project-structure.md"
  printf '# rules\n'        > "$r/knowledge-base/13-business-rules.md"
  printf '# auth module\n'  > "$r/knowledge-base/modules/auth.md"
  mkdir -p "$r/cwk-sessions/runbook"
  printf '# Runbook — alpha\n\nqueue depth climbing\n' > "$r/cwk-sessions/runbook/alpha-2026-09-08.md"
  echo "$r"
}

echo "kb-export: collects a KB under projects/<name>/"
a=$(mk_repo alpha)
"$EXPORT" "$TMP/hub" "$a" >/dev/null 2>&1
check "KB copied"                "$(cat "$TMP/hub/projects/alpha/knowledge-base/13-business-rules.md" 2>/dev/null)" "# rules"
check "nested module doc copied" "$(cat "$TMP/hub/projects/alpha/knowledge-base/modules/auth.md" 2>/dev/null)" "# auth module"
check "identity file written"    "$([ -f "$TMP/hub/projects/alpha/_meta.yml" ] && echo yes || echo no)" yes
check "meta names the project"   "$(grep -c '^project: alpha' "$TMP/hub/projects/alpha/_meta.yml" 2>/dev/null)" 1
check "index lists the project"  "$(grep -c 'projects/alpha' "$TMP/hub/README.md" 2>/dev/null)" 1
# A runbook lives in cwk-sessions/ (gitignored), so the hub is the only place a teammate reads one.
check "runbook carried into the hub" "$(cat "$TMP/hub/projects/alpha/runbook/alpha-2026-09-08.md" 2>/dev/null | head -1)" "# Runbook — alpha"

echo "kb-export: a repo with no KB is skipped, not failed"
mkdir -p "$TMP/empty-repo"
"$EXPORT" "$TMP/hub" "$TMP/empty-repo" >/dev/null 2>&1
check "exit 0"                    "$?" 0
check "no folder invented"        "$([ -e "$TMP/hub/projects/empty-repo" ] && echo yes || echo no)" no

echo "kb-export: --dry-run writes nothing"
b=$(mk_repo beta)
"$EXPORT" --dry-run "$TMP/hub" "$b" >/dev/null 2>&1
check "beta not created"          "$([ -e "$TMP/hub/projects/beta" ] && echo yes || echo no)" no

echo "kb-export: re-export replaces the snapshot instead of merging stale files"
printf '# gone next time\n' > "$a/knowledge-base/99-temp.md"
"$EXPORT" "$TMP/hub" "$a" >/dev/null 2>&1
check "new file present"          "$([ -f "$TMP/hub/projects/alpha/knowledge-base/99-temp.md" ] && echo yes || echo no)" yes
rm "$a/knowledge-base/99-temp.md"
"$EXPORT" "$TMP/hub" "$a" >/dev/null 2>&1
check "removed file is gone too"  "$([ -f "$TMP/hub/projects/alpha/knowledge-base/99-temp.md" ] && echo yes || echo no)" no

echo "kb-import: lands the KB in a target checkout"
mkdir -p "$TMP/mate"
"$IMPORT" "$TMP/hub" alpha "$TMP/mate" >/dev/null 2>&1
check "KB imported"               "$(cat "$TMP/mate/knowledge-base/13-business-rules.md" 2>/dev/null)" "# rules"
check "modules came along"        "$([ -f "$TMP/mate/knowledge-base/modules/auth.md" ] && echo yes || echo no)" yes

echo "kb-import: refuses to overwrite an existing KB"
printf '# MINE\n' > "$TMP/mate/knowledge-base/13-business-rules.md"
"$IMPORT" "$TMP/hub" alpha "$TMP/mate" >/dev/null 2>&1
check "exit non-zero"             "$([ $? -ne 0 ] && echo yes || echo no)" yes
check "existing content intact"   "$(cat "$TMP/mate/knowledge-base/13-business-rules.md")" "# MINE"

echo "kb-import: --force replaces but keeps a backup"
"$IMPORT" --force "$TMP/hub" alpha "$TMP/mate" >/dev/null 2>&1
check "replaced"                  "$(cat "$TMP/mate/knowledge-base/13-business-rules.md")" "# rules"
check "backup kept"               "$(ls -d "$TMP/mate"/knowledge-base.bak-* 2>/dev/null | wc -l | tr -d ' ')" 1

echo "kb-import: an unknown project is an error, not an empty import"
"$IMPORT" "$TMP/hub" nosuch "$TMP/mate" >/dev/null 2>&1
check "exit non-zero"             "$([ $? -ne 0 ] && echo yes || echo no)" yes

echo "kb-site: builds one self-contained page from a hub"
if command -v node >/dev/null 2>&1; then
  node "$PWD/scripts/kb-site.cjs" "$TMP/hub" "$TMP/site.html" >/dev/null 2>&1
  check "page written"                "$([ -f "$TMP/site.html" ] && echo yes || echo no)" yes
  check "every project embedded"      "$(grep -c '"name":"alpha"' "$TMP/site.html" 2>/dev/null)" 1
  check "no external script/style"    "$(grep -cE '(src|href)="https?://' "$TMP/site.html" 2>/dev/null)" 0
  # The runbook must be searchable beside the KB, and titled so a hit is recognisable as one.
  check "runbook page is in the site"  "$(grep -c 'runbook/alpha-2026-09-08.md' "$TMP/site.html" 2>/dev/null)" 1
  check "runbook titled as a runbook"  "$(grep -c 'runbook / alpha 2026 09 08' "$TMP/site.html" 2>/dev/null)" 1
  check "its text is searchable"       "$(grep -c 'queue depth climbing' "$TMP/site.html" 2>/dev/null)" 1
  # CSP: a nonce on style-src makes 'unsafe-inline' be ignored, which silently breaks every Mermaid
  # diagram (they are styled by an injected <style>). Read the real directive out of the meta tag —
  # not the file at large, which also contains a comment explaining this.
  csp=$(grep -o 'content="default-src[^"]*"' "$TMP/site.html" | head -1)
  check "style-src has no nonce"      "$(echo "$csp" | grep -o "style-src [^;]*" | grep -c nonce)" 0
  check "script-src keeps its nonce"  "$(echo "$csp" | grep -o "script-src [^;]*" | grep -c nonce)" 1
  # A '</script>' inside any KB document must not close the embedded data block early.
  printf '# x\n\n</script><img src=x onerror=alert(1)>\n' > "$TMP/alpha/knowledge-base/99-xss.md"
  "$EXPORT" "$TMP/hub" "$TMP/alpha" >/dev/null 2>&1
  node "$PWD/scripts/kb-site.cjs" "$TMP/hub" "$TMP/site2.html" >/dev/null 2>&1
  # Two layers catch it: the markdown renderer escapes the tags, then JSON-encoding escapes < and >.
  check "payload rendered as text"    "$(grep -c '&lt;/script&gt;' "$TMP/site2.html" 2>/dev/null)" 1
  check "payload not live markup"     "$(grep -c '<img src=x onerror' "$TMP/site2.html" 2>/dev/null)" 0
  check "no stray closing script tag" "$(grep -o '</script' "$TMP/site2.html" | wc -l | tr -d ' ')" "$(grep -o '<script' "$TMP/site2.html" | wc -l | tr -d ' ')"
else
  echo "  – skipped (node not installed)"
fi

echo "kb-site: the single-repo shape and the refusal path"
if command -v node >/dev/null 2>&1; then
  mkdir -p "$TMP/solo/knowledge-base"
  printf '# solo doc\n' > "$TMP/solo/knowledge-base/01-x.md"
  node "$PWD/scripts/kb-site.cjs" "$TMP/solo" "$TMP/solo.html" >/dev/null 2>&1
  check "single-repo page written"  "$([ -f "$TMP/solo.html" ] && echo yes || echo no)" yes
  check "project named after the dir" "$(grep -c '"name":"solo"' "$TMP/solo.html")" 1
  # Single-repo shape: the runbook sits at cwk-sessions/runbook/, not beside the KB.
  mkdir -p "$TMP/solo/cwk-sessions/runbook"
  printf '# Runbook — solo\n\nrestart the consumer\n' > "$TMP/solo/cwk-sessions/runbook/solo.md"
  node "$PWD/scripts/kb-site.cjs" "$TMP/solo" "$TMP/solo2.html" >/dev/null 2>&1
  check "runbook found in a single repo" "$(grep -c 'restart the consumer' "$TMP/solo2.html" 2>/dev/null)" 1
  mkdir -p "$TMP/nokb"
  node "$PWD/scripts/kb-site.cjs" "$TMP/nokb" "$TMP/nokb.html" >/dev/null 2>&1
  check "no-KB dir exits non-zero"  "$([ $? -ne 0 ] && echo yes || echo no)" yes
  check "and writes nothing"        "$([ -e "$TMP/nokb.html" ] && echo yes || echo no)" no

  # _meta.yml is rendered into the page chrome. It is safe today only because the client builds those
  # nodes with textContent — pin that, so a later switch to innerHTML cannot silently reintroduce XSS
  # into a page whose whole purpose is to be emailed around.
  printf 'project: alpha\nbranch: <img src=x onerror=alert(1)>\ncommit: "abc\n' >> "$TMP/hub/projects/alpha/_meta.yml"
  node "$PWD/scripts/kb-site.cjs" "$TMP/hub" "$TMP/site3.html" >/dev/null 2>&1
  check "meta payload escaped in the data blob" "$(grep -c 'u003cimg src=x' "$TMP/site3.html")" 1
  check "meta payload is not live markup"       "$(grep -c '<img src=x onerror' "$TMP/site3.html")" 0
else
  echo "  – skipped (node not installed)"
fi

echo "kb-export: refuses to overwrite a snapshot taken from a DIFFERENT repo"
mkdir -p "$TMP/clientA/api/knowledge-base" "$TMP/clientB/api/knowledge-base"
printf '# A\n' > "$TMP/clientA/api/knowledge-base/01-x.md"
printf '# B\n' > "$TMP/clientB/api/knowledge-base/01-x.md"
"$EXPORT" "$TMP/hub2" "$TMP/clientA/api" >/dev/null 2>&1
"$EXPORT" "$TMP/hub2" "$TMP/clientB/api" >/dev/null 2>&1
check "client A's KB was not replaced" "$(cat "$TMP/hub2/projects/api/knowledge-base/01-x.md")" "# A"

echo "kb-hub: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
