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
# The scripts under test append to the audit trail (scripts/audit-log.sh). A test run must never
# write into the real ~/.claude/cwk-audit.jsonl; the audit cases below point it at $TMP explicitly.
export CWK_AUDIT_LOG=off

mk_repo() {  # <name> — a repo with a small KB
  local r="$TMP/$1"; mkdir -p "$r/knowledge-base/modules"
  printf '# 01 structure\n' > "$r/knowledge-base/01-project-structure.md"
  printf '# rules\n'        > "$r/knowledge-base/13-business-rules.md"
  printf '# auth module\n'  > "$r/knowledge-base/modules/auth.md"
  mkdir -p "$r/cwk-sessions/runbook"
  printf '# Runbook — alpha\n\nqueue depth climbing\n' > "$r/cwk-sessions/runbook/alpha-2026-09-08.md"
  mkdir -p "$r/cwk-sessions/maps"
  printf '<html><body>graph</body></html>\n' > "$r/cwk-sessions/maps/alpha-old.html"
  sleep 1
  printf '<html><body>NEWEST graph</body></html>\n' > "$r/cwk-sessions/maps/alpha-new.html"
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
# /cwk-map writes one file per run; the NEWEST is the one describing the current tree.
check "newest code graph carried"    "$(grep -c 'NEWEST graph' "$TMP/hub/projects/alpha/code-graph.html" 2>/dev/null)" 1
# That fixture is not a full-index page (no graph-data block), so it is copied as it is and the
# export still records what the hub got.
check "meta records the code graph"  "$(grep -c '^code_graph: stripped' "$TMP/hub/projects/alpha/_meta.yml" 2>/dev/null)" 1

echo "strip-map-source: a hub's code graph carries the graph, never the source text"
# A full-index /cwk-map page embeds the TEXT of every indexed file (gzip+base64 inside
# <script id="graph-data">) so the explorer can show a symbol's body offline. A hub is pushed and
# emailed, so kb-export.sh must remove that text by default and keep it only under --with-source.
if command -v node >/dev/null 2>&1; then
  STRIPPER="$PWD/scripts/strip-map-source.cjs"
  # Pack exactly the way provenlens-full.cjs pack() does: gzip level 9, then base64.
  node -e '
    const zlib = require("zlib"), fs = require("fs");
    const data = {files:[["a.js","javascript",0]],kinds:["function"],syms:[["f","f",0,0,1,3,""]],edges:[],unresolved:[],source:{"0":"SECRET_TOKEN_XYZ()"},stats:{}};
    const b64 = zlib.gzipSync(Buffer.from(JSON.stringify(data), "utf8"), { level: 9 }).toString("base64");
    fs.writeFileSync(process.argv[1], `<!DOCTYPE html><html><body><script nonce="n" id="graph-data" type="application/octet-stream">${b64}</script><script>x()</script></body></html>\n`);
  ' "$TMP/full.html"
  # unpack <page> — prints the JSON inside the graph-data block, or "" when there is none
  unpack() { node -e '
    const zlib = require("zlib"), fs = require("fs");
    const h = fs.readFileSync(process.argv[1], "utf8");
    const m = /<script\b[^>]*\bid="graph-data"[^>]*>/.exec(h); if (!m) { process.stdout.write(""); process.exit(0); }
    const b = h.slice(m.index + m[0].length, h.indexOf("</script>", m.index)).trim();
    process.stdout.write(zlib.gunzipSync(Buffer.from(b, "base64")).toString("utf8"));
  ' "$1" 2>/dev/null; }
  check "fixture really carries the token (packed)" "$(unpack "$TMP/full.html" | grep -c SECRET_TOKEN_XYZ)" 1
  node "$STRIPPER" "$TMP/full.html" "$TMP/full-stripped.html" >/dev/null 2>&1
  check "stripper exit 0"                   "$?" 0
  check "token gone after unpacking"        "$(unpack "$TMP/full-stripped.html" | grep -c SECRET_TOKEN_XYZ)" 0
  check "token not in the page as text"     "$(grep -c SECRET_TOKEN_XYZ "$TMP/full-stripped.html")" 0
  check "graph-data block still there"      "$(grep -c 'id="graph-data"' "$TMP/full-stripped.html")" 1
  check "symbols kept"                      "$(unpack "$TMP/full-stripped.html" | grep -c '"syms":\[\["f","f",0,0,1,3,""\]\]')" 1
  check "files kept"                        "$(unpack "$TMP/full-stripped.html" | grep -c '"files":\[\["a.js","javascript",0\]\]')" 1
  check "source emptied, not deleted"       "$(unpack "$TMP/full-stripped.html" | grep -c '"source":{}')" 1
  check "page says the source is stripped"  "$(unpack "$TMP/full-stripped.html" | grep -c '"sourceStripped":true')" 1
  check "rest of the page untouched"        "$(grep -c '<script>x()</script>' "$TMP/full-stripped.html")" 1
  check "no temp file left behind"          "$(ls "$TMP"/.full-stripped.html.* 2>/dev/null | wc -l | tr -d ' ')" 0
  # Not a full-index page: no block at all, and the older sampled viewer's plain-JSON block. Exit 2,
  # nothing written — the caller decides to copy it raw (the sampled viewer embeds no source).
  printf '<html><body>no graph here</body></html>\n' > "$TMP/plain.html"
  node "$STRIPPER" "$TMP/plain.html" "$TMP/plain-out.html" >/dev/null 2>&1
  check "no graph-data block → exit 2"      "$?" 2
  check "and nothing written"               "$([ -e "$TMP/plain-out.html" ] && echo yes || echo no)" no
  printf '<html><body><script id="graph-data" type="application/json">{"nodes":[],"edges":[]}</script></body></html>\n' > "$TMP/sampled.html"
  node "$STRIPPER" "$TMP/sampled.html" "$TMP/sampled-out.html" >/dev/null 2>&1
  check "plain-JSON (sampled) block → exit 2" "$?" 2
  check "and nothing written"               "$([ -e "$TMP/sampled-out.html" ] && echo yes || echo no)" no

  # Through kb-export.sh: default strips, --with-source keeps and warns, _meta.yml says which.
  mkdir -p "$TMP/gamma/knowledge-base" "$TMP/gamma/cwk-sessions/maps"
  printf '# gamma\n' > "$TMP/gamma/knowledge-base/01-x.md"
  cp "$TMP/full.html" "$TMP/gamma/cwk-sessions/maps/gamma-2026-09-20.html"
  out=$("$EXPORT" "$TMP/hub5" "$TMP/gamma" 2>&1)
  check "default export succeeds"           "$?" 0
  check "hub graph has no token"            "$(unpack "$TMP/hub5/projects/gamma/code-graph.html" | grep -c SECRET_TOKEN_XYZ)" 0
  check "hub graph still a graph"           "$(unpack "$TMP/hub5/projects/gamma/code-graph.html" | grep -c '"sourceStripped":true')" 1
  check "meta: code_graph stripped"         "$(grep -c '^code_graph: stripped' "$TMP/hub5/projects/gamma/_meta.yml")" 1
  check "output says source stripped"       "$(echo "$out" | grep -c 'source stripped')" 1
  check "no --with-source warning"          "$(echo "$out" | grep -c 'with-source')" 0
  out=$("$EXPORT" --with-source "$TMP/hub6" "$TMP/gamma" 2>&1)
  check "--with-source export succeeds"     "$?" 0
  check "hub graph carries the token"       "$(unpack "$TMP/hub6/projects/gamma/code-graph.html" | grep -c SECRET_TOKEN_XYZ)" 1
  check "meta: code_graph with-source"      "$(grep -c '^code_graph: with-source' "$TMP/hub6/projects/gamma/_meta.yml")" 1
  check "warned that the hub has source"    "$(echo "$out" | grep -c 'SOURCE TEXT')" 1
  # A scan-written _meta.yml is copied and gets the same stamp.
  printf 'project: gamma\nbranch: main\n' > "$TMP/gamma/knowledge-base/_meta.yml"
  "$EXPORT" "$TMP/hub5" "$TMP/gamma" >/dev/null 2>&1
  check "scan-written meta stamped too"     "$(grep -c '^code_graph: stripped' "$TMP/hub5/projects/gamma/_meta.yml")" 1
  mkdir -p "$TMP/delta/knowledge-base"; printf '# delta\n' > "$TMP/delta/knowledge-base/01-x.md"
  "$EXPORT" "$TMP/hub5" "$TMP/delta" >/dev/null 2>&1
  check "a repo with no map says none"      "$(grep -c '^code_graph: none' "$TMP/hub5/projects/delta/_meta.yml" 2>/dev/null)" 1
else
  echo "  – skipped (node not installed)"
fi

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
  # The graph is linked, not inlined: a few hundred KB per project would make the page unopenable.
  check "graph page not inlined"            "$(grep -c 'NEWEST graph' "$TMP/site.html" 2>/dev/null)" 0
  # The href is relative to the PAGE, not to the hub: written into the hub it is projects/<n>/…,
  # written elsewhere it has to climb. Getting this wrong gives a dead link that looks fine.
  check "href relative to a page beside the hub" "$(grep -c '"graph":"hub/projects/alpha/code-graph.html"' "$TMP/site.html" 2>/dev/null)" 1
  node "$PWD/scripts/kb-site.cjs" "$TMP/hub" >/dev/null 2>&1
  check "href relative to a page inside the hub" "$(grep -c '"graph":"projects/alpha/code-graph.html"' "$TMP/hub/index.html" 2>/dev/null)" 1
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
  # With no output path, a single repo's page goes inside knowledge-base/, never over the repo's own
  # index.html, and a file kb-site did not write is never overwritten.
  printf '<!DOCTYPE html><title>Landing</title>\n' > "$TMP/solo/index.html"
  node "$PWD/scripts/kb-site.cjs" "$TMP/solo" >/dev/null 2>&1
  check "single-repo default lands in knowledge-base/" "$([ -f "$TMP/solo/knowledge-base/index.html" ] && echo yes || echo no)" yes
  check "the repo's own index.html is untouched" "$(grep -c Landing "$TMP/solo/index.html")" 1
  node "$PWD/scripts/kb-site.cjs" "$TMP/solo" "$TMP/solo/index.html" >/dev/null 2>&1
  check "refuses to overwrite a foreign file" "$([ $? -ne 0 ] && echo yes || echo no)" yes
  check "and leaves it as it was" "$(grep -c Landing "$TMP/solo/index.html")" 1
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

echo "kb-export: credentials in the origin URL never reach the hub"
# A remote of the form https://user:token@host/… is what a CI checkout or a hurried `git clone` leaves
# behind. _meta.yml, README.md and index.html all carry the repo field — the token must be in none.
mkdir -p "$TMP/cred/knowledge-base"
printf '# cred doc\n' > "$TMP/cred/knowledge-base/01-x.md"
( cd "$TMP/cred" && git init -q && git remote add origin 'https://u:tok@example.com/x.git' ) 2>/dev/null
"$EXPORT" "$TMP/hub3" "$TMP/cred" >/dev/null 2>&1
check "export succeeded"                 "$?" 0
check "repo field kept, host intact"     "$(grep -c '^repo: https://example.com/x.git' "$TMP/hub3/projects/cred/_meta.yml" 2>/dev/null)" 1
check "token nowhere in the hub"         "$(grep -rl 'tok@' "$TMP/hub3" 2>/dev/null | wc -l | tr -d ' ')" 0
# The KB's own _meta.yml (written by a scan) is redacted the same way when it is copied.
printf 'project: cred\nrepo: https://u:tok@example.com/x.git\nbranch: main\n' > "$TMP/cred/knowledge-base/_meta.yml"
"$EXPORT" "$TMP/hub3" "$TMP/cred" >/dev/null 2>&1
check "scan-written meta redacted too"   "$(grep -rl 'tok@' "$TMP/hub3" 2>/dev/null | wc -l | tr -d ' ')" 0
check "ssh form left as is"              "$(printf 'x' | sed -E 's#(https?://)[^/@]+@#\1#' >/dev/null; echo 'ssh://git@example.com/x.git' | sed -E 's#(https?://)[^/@]+@#\1#')" "ssh://git@example.com/x.git"

echo "kb-export: a KB page carrying a secret is not exported"
mkdir -p "$TMP/leaky/knowledge-base"
printf '# ok doc\n' > "$TMP/leaky/knowledge-base/01-x.md"
printf '# config\n\ntoken: ghp_abcdefghijklmnopqrstuvwxyz0123456789\n' > "$TMP/leaky/knowledge-base/14-integrations.md"
out=$("$EXPORT" "$TMP/hub4" "$TMP/leaky" 2>&1); rc=$?
check "exit non-zero"                    "$([ "$rc" -ne 0 ] && echo yes || echo no)" yes
check "project not written"              "$([ -e "$TMP/hub4/projects/leaky" ] && echo yes || echo no)" no
check "hit names file:line"              "$(echo "$out" | grep -c '14-integrations.md:3:')" 1
check "hit is masked to 6 chars"         "$(echo "$out" | grep -c 'ghp_ab…')" 1
check "full token never printed"         "$(echo "$out" | grep -c 'ghp_abcdefghij')" 0
# Every pattern the scan promises: one fixture each, all must block.
for s in 'AKIAABCDEFGHIJKLMNOP' 'gho_abcdefghijklmnopqrstuvwxyz' '-----BEGIN RSA PRIVATE KEY-----' 'xoxb-1234' 'sk-abcdefghijklmnopqrstuvwxyz' 'https://user:pass@example.com/repo.git'; do
  mkdir -p "$TMP/pat/knowledge-base"; printf '# doc\n\n%s\n' "$s" > "$TMP/pat/knowledge-base/01-x.md"
  "$EXPORT" "$TMP/hub-pat" "$TMP/pat" >/dev/null 2>&1
  check "blocks ${s:0:6}…"               "$([ $? -ne 0 ] && [ ! -e "$TMP/hub-pat/projects/pat" ] && echo yes || echo no)" yes
done
# A clean KB is unaffected, and --allow-secrets is the explicit override.
"$EXPORT" --allow-secrets "$TMP/hub4" "$TMP/leaky" >/dev/null 2>&1
check "--allow-secrets exports, exit 0"  "$?" 0
check "project written on override"     "$([ -f "$TMP/hub4/projects/leaky/knowledge-base/01-x.md" ] && echo yes || echo no)" yes

echo "kb-export: data classification travels with the KB, and defaults to internal"
# A KB records permission matrices, unpatched defects and env var names; the hub copies it, so every
# reader must see what they are holding. resources/kb-steps.md defines the key; absent → internal.
mkdir -p "$TMP/rho/knowledge-base" "$TMP/sigma/knowledge-base"
printf '# rho\n' > "$TMP/rho/knowledge-base/01-x.md"
printf 'project: rho\nrepo: https://github.com/acme/rho.git\nclassification: restricted\n' > "$TMP/rho/knowledge-base/_meta.yml"
printf '# sigma\n' > "$TMP/sigma/knowledge-base/01-x.md"     # no _meta.yml at all
"$EXPORT" "$TMP/hub7" "$TMP/rho" "$TMP/sigma" >/dev/null 2>&1
check "restricted carried into hub meta"   "$(grep -c '^classification: restricted' "$TMP/hub7/projects/rho/_meta.yml" 2>/dev/null)" 1
check "absent → internal in hub meta"      "$(grep -c '^classification: internal' "$TMP/hub7/projects/sigma/_meta.yml" 2>/dev/null)" 1
check "README table has the column"        "$(grep -c '^| Project | Classification |' "$TMP/hub7/README.md" 2>/dev/null)" 1
check "README row says restricted"         "$(grep -c '^| \[rho\].* | restricted |' "$TMP/hub7/README.md" 2>/dev/null)" 1
check "README row says internal"           "$(grep -c '^| \[sigma\].* | internal |' "$TMP/hub7/README.md" 2>/dev/null)" 1
# A scan-written meta with the key present is copied, not duplicated.
check "key not duplicated when present"    "$(grep -c '^classification:' "$TMP/hub7/projects/rho/_meta.yml" 2>/dev/null)" 1
# An unknown word is not trusted as a level — and is never read as public.
printf 'project: tau\nclassification: Top Secret\n' > "$TMP/sigma/knowledge-base/_meta.yml"
"$EXPORT" "$TMP/hub7" "$TMP/sigma" >/dev/null 2>&1
check "unknown value → internal in README" "$(grep -c '^| \[sigma\].* | internal |' "$TMP/hub7/README.md" 2>/dev/null)" 1
check "unknown value → internal in hub meta" "$(grep -c '^classification: internal' "$TMP/hub7/projects/sigma/_meta.yml" 2>/dev/null)" 1
check "raw unknown value not carried"      "$(grep -c 'Top Secret' "$TMP/hub7/projects/sigma/_meta.yml" 2>/dev/null)" 0
if command -v node >/dev/null 2>&1; then
  node "$PWD/scripts/kb-site.cjs" "$TMP/hub7" "$TMP/site7.html" >/dev/null 2>&1
  # The page normalises the value server-side (it doubles as a CSS class) and renders a badge on the
  # project card plus a banner over the document. The top-level key is what the client reads.
  check "restricted badge data in the page"  "$(grep -c '"classification":"restricted","graph"' "$TMP/site7.html" 2>/dev/null)" 1
  check "sigma defaults to internal"         "$(grep -c '"name":"sigma".*"classification":"internal","graph"' "$TMP/site7.html" 2>/dev/null)" 1
  check "badge + banner styles present"      "$(grep -c 'cls-restricted' "$TMP/site7.html" 2>/dev/null)" 2
  check "banner element present"             "$(grep -c '<div id="cls"></div>' "$TMP/site7.html" 2>/dev/null)" 1
  check "an unknown value never becomes a class" "$(grep -c 'cls-top' "$TMP/site7.html" 2>/dev/null)" 0
  # Single-repo shape, no key anywhere → internal.
  mkdir -p "$TMP/solo7/knowledge-base"; printf '# s\n' > "$TMP/solo7/knowledge-base/01-x.md"
  node "$PWD/scripts/kb-site.cjs" "$TMP/solo7" "$TMP/solo7.html" >/dev/null 2>&1
  check "single repo without meta → internal" "$(grep -c '"classification":"internal","graph"' "$TMP/solo7.html" 2>/dev/null)" 1
fi

echo "audit-log: an export leaves one JSON line per project, or nothing when switched off"
# Nothing recorded what was exported, by whom, on which commit. scripts/audit-log.sh does, into
# ${CWK_AUDIT_LOG:-~/.claude/cwk-audit.jsonl}; CWK_AUDIT_LOG=off disables it; it never fails a caller.
AUD="$TMP/audit/cwk-audit.jsonl"                     # the directory does not exist yet — it must be created
CWK_AUDIT_LOG="$AUD" "$EXPORT" "$TMP/hub8" "$TMP/rho" "$TMP/cred" >/dev/null 2>&1
check "export still exits 0"              "$?" 0
check "one line per exported project"     "$(grep -c '"action":"kb.export"' "$AUD" 2>/dev/null)" 2
check "line carries the classification"   "$(grep -c '"project":"rho".*"classification":"restricted"' "$AUD" 2>/dev/null)" 1
check "line carries the code_graph field" "$(grep -c '"code_graph":"none"' "$AUD" 2>/dev/null)" 2
check "line carries hub, commit, cwd"     "$(grep -c '"commit":.*"hub":"'"$TMP"'/hub8"' "$AUD" 2>/dev/null)" 2
check "required fields present"           "$(head -1 "$AUD" | grep -c '"ts":"[0-9-]*T[0-9:]*Z".*"user":.*"host":.*"action":.*"cwd":')" 1
# The cred fixture's origin is https://u:tok@example.com — the token must not reach the audit line either.
check "credential redacted in the log"    "$(grep -c 'tok@' "$AUD" 2>/dev/null)" 0
check "host kept"                         "$(grep -c '"repo":"https://example.com/x.git"' "$AUD" 2>/dev/null)" 1
check "file is 0600"                      "$(ls -l "$AUD" | cut -c1-10)" "-rw-------"
if command -v jq >/dev/null 2>&1; then
  check "every line is valid JSON"        "$(jq -c . "$AUD" >/dev/null 2>&1 && echo yes || echo no)" yes
fi
CWK_AUDIT_LOG="$AUD" "$IMPORT" --force "$TMP/hub8" rho "$TMP/mate" >/dev/null 2>&1
check "import logs kb.import"             "$(grep -c '"action":"kb.import".*"project":"rho"' "$AUD" 2>/dev/null)" 1
CWK_AUDIT_LOG="$AUD" "$EXPORT" --dry-run "$TMP/hub8" "$TMP/rho" >/dev/null 2>&1
check "a dry run logs nothing"            "$(grep -c '"action":"kb.export"' "$AUD" 2>/dev/null)" 2
rm -f "$AUD"
CWK_AUDIT_LOG=off "$EXPORT" "$TMP/hub8" "$TMP/rho" >/dev/null 2>&1
check "off: export still exits 0"         "$?" 0
check "off: nothing written"              "$([ -e "$AUD" ] && echo yes || echo no)" no
# A destination that cannot be written must not break the export.
CWK_AUDIT_LOG="/dev/null/nope/audit.jsonl" "$EXPORT" "$TMP/hub8" "$TMP/rho" >/dev/null 2>&1
check "unwritable log never fails the caller" "$?" 0
# Direct call: no jq on PATH → the fallback escaper still writes valid JSON.
mkdir -p "$TMP/nojq"
for b in bash sed tr awk date hostname id pwd mkdir chmod dirname; do p=$(command -v "$b" 2>/dev/null) && ln -sf "$p" "$TMP/nojq/$b"; done
PATH="$TMP/nojq" CWK_AUDIT_LOG="$TMP/nojq.jsonl" bash "$PWD/scripts/audit-log.sh" test.fallback 'v=a "quoted" back\slash' repo=https://u:p@h/x >/dev/null 2>&1
check "fallback: line written"            "$(grep -c '"action":"test.fallback"' "$TMP/nojq.jsonl" 2>/dev/null)" 1
check "fallback: quotes and backslash escaped" "$(grep -cF '"v":"a \"quoted\" back\\slash"' "$TMP/nojq.jsonl" 2>/dev/null)" 1
check "fallback: credential redacted"     "$(grep -c 'u:p@' "$TMP/nojq.jsonl" 2>/dev/null)" 0
if command -v jq >/dev/null 2>&1; then
  check "fallback: valid JSON"            "$(jq -c . "$TMP/nojq.jsonl" >/dev/null 2>&1 && echo yes || echo no)" yes
fi

echo "kb-hub: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
