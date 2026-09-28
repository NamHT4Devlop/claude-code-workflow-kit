#!/usr/bin/env bash
# Smoke tests for the bundled Node tools: render-html (md→HTML) and build-map (code→graph HTML).
set -uo pipefail
cd "$(dirname "$0")/.."
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fail=0

echo "smoke: render-html.cjs"
printf '# Title\n\nhello **world** and a list:\n- one\n- two\n' > "$TMP/a.md"
node resources/render-html.cjs "$TMP/a.md" "$TMP/a.html" "Smoke" >/dev/null 2>&1
if grep -q "<html" "$TMP/a.html" && grep -q "hello" "$TMP/a.html"; then echo "  ✓ render-html produced HTML"; else echo "  ✗ render-html failed"; fail=1; fi

echo "smoke: build-map.cjs"
mkdir -p "$TMP/proj/src"
printf "import { b } from './b';\nexport function a() { return b(); }\n" > "$TMP/proj/src/a.ts"
printf "export function b() { return 1; }\n" > "$TMP/proj/src/b.ts"
node skills/cwk-map/references/build-map.cjs "$TMP/proj" "$TMP/map.html" all >/dev/null 2>&1
if grep -q 'id="graph-data"' "$TMP/map.html" && grep -q '"nodes"' "$TMP/map.html"; then echo "  ✓ build-map produced graph HTML"; else echo "  ✗ build-map failed"; fail=1; fi

# The map is drawn from a resolved call graph when a .provenlens/ index is there and from a regex
# scan when it is not. Those edges are not worth the same, so every graph must name its source —
# an unlabelled one silently invites a reader to trust an import line as if it were a call.
# This fixture has no index, so it must take the fallback AND say so.
if grep -q '"source"' "$TMP/map.html" && grep -q 'static import/inheritance scan' "$TMP/map.html"; then
  echo "  ✓ build-map labelled its graph source (fallback path)"
else
  echo "  ✗ build-map produced a graph with no source label"; fail=1
fi

echo "smoke: provenlens-graph.cjs degrades without an index"
why=$(node -e '
  const { buildFromProvenlens, uncoveredLanguages } = require("./skills/cwk-map/references/provenlens-graph.cjs");
  const r = buildFromProvenlens(process.argv[1]);
  if (r.ok) { console.log("UNEXPECTED-OK"); process.exit(0); }
  console.log(r.why);
' "$TMP/proj" 2>&1)
case "$why" in
  *".provenlens"*|*"not on PATH"*) echo "  ✓ reports why, does not throw: $why";;
  *) echo "  ✗ expected a graceful reason, got: $why"; fail=1;;
esac

echo "smoke: provenlens-graph.cjs exposes what the index holds"
# indexedLanguages() is how the adapter notices it drew a neighbourhood rather than a repository.
# Without an index it must return an empty list, not throw and not invent one.
held=$(node -e '
  const { indexedLanguages } = require("./skills/cwk-map/references/provenlens-graph.cjs");
  const r = indexedLanguages(process.argv[1]);
  console.log(Array.isArray(r) ? `array:${r.length}` : typeof r);
' "$TMP/proj" 2>&1)
if [ "$held" = "array:0" ]; then echo "  ✓ empty list without an index"; else echo "  ✗ expected array:0, got: $held"; fail=1; fi

echo "smoke: provenlens-graph.cjs names a language it cannot cover"
printf 'def handler():\n    return 1\n' > "$TMP/proj/worker.py"
langs=$(node -e '
  const { uncoveredLanguages } = require("./skills/cwk-map/references/provenlens-graph.cjs");
  console.log(uncoveredLanguages(process.argv[1]).join(","));
' "$TMP/proj" 2>&1)
if [ "$langs" = "Python" ]; then echo "  ✓ Python reported as uncovered"; else echo "  ✗ expected Python, got: $langs"; fail=1; fi

echo "smoke: provenlens-full.cjs degrades without an index"
# The explorer reads provenlens's private index; without one it must say why and let build-map
# fall back, never throw.
why=$(node --no-warnings -e '
  const { buildFullIndex } = require("./skills/cwk-map/references/provenlens-full.cjs");
  const r = buildFullIndex(process.argv[1]);
  console.log(r.ok ? "UNEXPECTED-OK" : r.why);
' "$TMP/proj" 2>&1)
case "$why" in
  *"index.db"*|*"node:sqlite"*) echo "  ✓ reports why, does not throw: $why";;
  *) echo "  ✗ expected a graceful reason, got: $why"; fail=1;;
esac

echo "smoke: explorer-template.html has every placeholder build-map fills"
for ph in __PROJECT__ __LAYERS__ __GRAPH_DATA__; do
  if grep -q "$ph" skills/cwk-map/references/explorer-template.html; then echo "  ✓ $ph"; else echo "  ✗ $ph missing"; fail=1; fi
done

echo "smoke: a click on the map lights a node up in place — it never redraws"
# The whole-index explorer redrew the canvas around whatever was clicked, so nothing stayed where it
# was and the picture of the system was gone after one click. The Map view is the old viewer's
# manners on the whole index; this pins what makes it that: nothing on the click path removes an
# element, adding neighbours locks every node already placed, and only a Trace click moves the camera.
why=$(node -e '
  const s = require("fs").readFileSync("skills/cwk-map/references/explorer-template.html", "utf8");
  const body = name => {
    const i = s.indexOf("function " + name + "("); if (i < 0) return null;
    let d = 0; const j = s.indexOf("{", i);
    for (let k = j; k < s.length; k++) { if (s[k] === "{") d++; else if (s[k] === "}" && --d === 0) return s.slice(j, k + 1); }
    return null;
  };
  const bad = [];
  for (const f of ["mapSelect", "mapExpand", "mapAdd", "settle"]) {
    const b = body(f);
    if (!b) bad.push(f + "() is gone"); else if (/\.remove\(/.test(b)) bad.push(f + "() removes elements");
  }
  if (!/old\.lock\(\)/.test(body("settle") || "")) bad.push("settle() does not lock the nodes already placed");
  if (!/id="vmap"/.test(s) || !/id="vtrace"/.test(s)) bad.push("the Map / Trace buttons are gone");
  if (!s.includes("cy.on(\x27tap\x27, \x27node\x27, e => focus(+e.target.id(), true, false));")) bad.push("a node click moves the camera");
  process.stdout.write(bad.join("; "));
' 2>&1)
if [ -z "$why" ]; then echo "  ✓ select, expand and add never remove an element; settle locks what is placed; a click keeps the camera"
else echo "  ✗ $why"; fail=1; fi

echo "smoke: markdown renderer keeps wrapped prose and numbered steps whole"
# Docs are wrapped at ~100 columns. Rendering each line as its own <p> cut sentences in half, and a
# code block inside a numbered step restarted the numbering at 1.
got=$(node -e '
  const { markdownToHtml } = require("./resources/html-builder.js");
  process.stdout.write(markdownToHtml("One\ntwo.\n\n1. A\n   wraps.\n   ```sql\n   SELECT 1;\n   ```\n   after\n2. B\n"));
')
case "$got" in
  *"<p>One two.</p>"*) echo "  ✓ wrapped lines join into one paragraph";;
  *) echo "  ✗ wrapped lines split: $got"; fail=1;;
esac
if [ "$(printf '%s' "$got" | grep -c '<ol')" = "1" ] && printf '%s' "$got" | grep -q '<li>A wraps.<pre><code>SELECT 1;</code></pre><p>after</p></li>'; then
  echo "  ✓ a code block stays inside its numbered step"
else echo "  ✗ numbered list broken: $got"; fail=1; fi

echo "smoke: check-mermaid.cjs tells a good diagram from a broken one"
# The KB is judged by its diagrams; this is the check the scan runs before it reports done. A
# `<` inside a label used to hang it (DOMPurify on a fake DOM), and two colons on a state
# transition is the mistake the spec itself once made.
mkdir -p "$TMP/mm"
printf '```mermaid\nflowchart TD\n  A{"a <= b"} --> B["ok"]\n```\n\n1. step\n   ```mermaid\n   sequenceDiagram\n     A->>B: x < y\n   ```\n' > "$TMP/mm/good.md"
printf '```mermaid\nstateDiagram-v2\n  [*] --> A : who : guard\n```\n' > "$TMP/mm/bad.md"
if node scripts/check-mermaid.cjs "$TMP/mm/good.md" >/dev/null 2>&1; then echo "  ✓ valid diagrams pass, including < in a label and a block inside a list"; else echo "  ✗ valid diagrams were rejected"; fail=1; fi
out=$(node scripts/check-mermaid.cjs "$TMP/mm/bad.md" 2>&1); code=$?
if [ "$code" -eq 1 ] && printf '%s' "$out" | grep -q 'bad.md:1'; then echo "  ✓ a broken diagram fails with its file:line"; else echo "  ✗ expected exit 1 and bad.md:1, got $code: $out"; fail=1; fi

echo "smoke: build-map CSP runs only nonced scripts, never 'unsafe-inline' or an inline handler"
# Everything in the graph is text from the scanned repository. A per-build nonce means no string
# that repository contributes can ever become a script, whatever escaping slip comes later.
for t in viewer-template.html explorer-template.html; do
  if grep -q "script-src 'nonce-__NONCE__'" "skills/cwk-map/references/$t" && ! grep -q "<script>" "skills/cwk-map/references/$t"; then
    echo "  ✓ $t: nonce placeholder in CSP and on every <script>"
  else echo "  ✗ $t: script-src without nonce, or a bare <script>"; fail=1; fi
done
nonce=$(grep -o "'nonce-[^']*'" "$TMP/map.html" | head -1 | sed "s/'nonce-//;s/'$//")
tags=$(grep -o '<script\b' "$TMP/map.html" | wc -l | tr -d ' ')
nonced=$(grep -o "<script nonce=\"$nonce\"" "$TMP/map.html" | wc -l | tr -d ' ')
if [ -n "$nonce" ] && [ "$tags" -gt 0 ] && [ "$tags" = "$nonced" ] && ! grep -o "script-src[^;]*" "$TMP/map.html" | grep -q "unsafe-inline" && ! grep -q '__NONCE__' "$TMP/map.html"; then
  echo "  ✓ built map: $nonced/$tags <script> tags carry the nonce, script-src has no 'unsafe-inline'"
else echo "  ✗ built map: nonce='$nonce' tags=$tags nonced=$nonced"; fail=1; fi
# Attribute position only (leading whitespace): the inlined Cytoscape source contains `position="…"`.
if ! grep -qE '[[:space:]]on[a-z]+="' "$TMP/map.html"; then echo "  ✓ built map: no inline event handler"; else echo "  ✗ built map has an inline event handler"; fail=1; fi

echo "smoke: a vendored bundle is only used from the kit root and only when its hash matches"
# A skill copied next to a scanned repository must never pick up THAT repository's vendor/, and a
# bundle that differs from vendor/SHA256SUMS must never be require()d (check-mermaid) or inlined
# into a page (build-map). Fixture: a fake kit root with a one-byte-different copy of each bundle.
if [ -f vendor/mermaid.min.js ] && [ -f vendor/cytoscape.min.js ]; then
  FK="$TMP/fakekit"; mkdir -p "$FK/.claude-plugin" "$FK/vendor" "$FK/resources" "$FK/skills/cwk-map"
  echo '{"name":"fake"}' > "$FK/.claude-plugin/plugin.json"; cp vendor/SHA256SUMS "$FK/vendor/"
  for lib in mermaid cytoscape; do
    cp "vendor/$lib.min.js" "$FK/vendor/$lib.min.js"
    printf '\000' | dd of="$FK/vendor/$lib.min.js" bs=1 seek=100 conv=notrunc 2>/dev/null
  done
  cp resources/check-mermaid.cjs "$FK/resources/"; cp -R skills/cwk-map/references "$FK/skills/cwk-map/references"
  out=$(node "$FK/resources/check-mermaid.cjs" "$TMP/mm/good.md" 2>&1); code=$?
  # The message carries the REAL path (realpathSync), which on macOS is /private/var/… for a /var/… tmp dir.
  if [ "$code" -eq 2 ] && printf '%s' "$out" | grep -q "refusing to load .*/fakekit/vendor/mermaid.min.js" && ! printf '%s' "$out" | grep -q 'diagram(s) parse'; then
    echo "  ✓ check-mermaid exits 2 and names the tampered bundle without loading it"
  else echo "  ✗ check-mermaid: expected exit 2 + refusal, got $code: $out"; fail=1; fi
  err=$(PROVENLENS=0 node "$FK/skills/cwk-map/references/build-map.cjs" "$TMP/proj" "$FK/map.html" all 2>&1 >/dev/null)
  if [ "$(printf '%s\n' "$err" | grep -c '⚠ not inlining')" = "1" ] && printf '%s' "$err" | grep -q "/fakekit/vendor/cytoscape.min.js" \
     && grep -q 'src="https://cdnjs.cloudflare.com/ajax/libs/cytoscape' "$FK/map.html" && ! grep -q 'vendored cytoscape' "$FK/map.html"; then
    echo "  ✓ build-map warns once, names the file, and falls back to the CDN <script src>"
  else echo "  ✗ build-map with a tampered bundle: $err"; fail=1; fi
  cp resources/render-html.cjs resources/html-builder.js "$FK/resources/"
  err=$(node "$FK/resources/render-html.cjs" "$TMP/mm/good.md" "$FK/doc.html" 2>&1 >/dev/null)
  if [ "$(printf '%s\n' "$err" | grep -c '⚠ not inlining')" = "1" ] && printf '%s' "$err" | grep -q "/fakekit/vendor/mermaid.min.js" \
     && grep -q 'src="https://cdnjs.cloudflare.com/ajax/libs/mermaid' "$FK/doc.html" && ! grep -q 'vendored mermaid' "$FK/doc.html"; then
    echo "  ✓ render-html warns once, names the file, and keeps the CDN <script src>"
  else echo "  ✗ render-html with a tampered bundle: $err"; fail=1; fi
  node resources/render-html.cjs "$TMP/mm/good.md" "$TMP/doc.html" >/dev/null 2>&1
  if grep -q 'vendored mermaid' "$TMP/doc.html" && ! grep -q 'src="https://cdnjs' "$TMP/doc.html"; then
    echo "  ✓ render-html inlines the kit's verified mermaid bundle"
  else echo "  ✗ render-html did not inline the verified bundle"; fail=1; fi
  # The real kit's bundle passes the same check and is inlined.
  if grep -q 'vendored cytoscape' "$TMP/map.html" && ! grep -q 'src="https://cdnjs' "$TMP/map.html"; then
    echo "  ✓ the kit's own verified bundle is still inlined"
  else echo "  ✗ the kit's verified bundle was not inlined"; fail=1; fi
else
  echo "  – skipped (vendor/ not fetched)"
fi

echo "smoke: check-mermaid.cjs warns on a diagram too big to read, without failing it"
mkdir -p "$TMP/mm"
{ printf '```mermaid\nflowchart LR\n'; for i in $(seq 1 14); do printf '  N%s["step %s"] --> N%s["step %s"]\n' "$i" "$i" "$((i+1))" "$((i+1))"; done; printf '```\n'; } > "$TMP/mm/wide.md"
out=$(node scripts/check-mermaid.cjs "$TMP/mm/wide.md" 2>&1); code=$?
if [ "$code" -eq 0 ] && printf '%s' "$out" | grep -q 'oversized' && printf '%s' "$out" | grep -q 'wide.md:1'; then echo "  ✓ a 15-node LR flowchart parses but is flagged with its file:line"; else echo "  ✗ expected exit 0 with an oversized warning, got $code: $out"; fail=1; fi

# check-mermaid under a watchdog, printing "<exit code> <output>": a regression back to a parser that
# never answers must fail this suite, not stall it.
mmcheck() { node -e '
  const r = require("child_process").spawnSync(process.execPath, ["scripts/check-mermaid.cjs", process.argv[1]],
    { encoding: "utf8", timeout: 30000, env: { ...process.env, MM_TIMEOUT_MS: process.argv[2] } });
  process.stdout.write(`${r.signal ? "KILLED" : r.status} ${r.stdout}${r.stderr}`);
' "$1" "$2"; }

echo "smoke: check-mermaid.cjs parses an unquoted < in a node label, an edge label or a class member"
# Each of these hung the checker with no output until it was killed (DOMPurify parsing the label as
# HTML on the do-nothing DOM). Label and member text is now neutralised the way quoted text was.
printf '```mermaid\nflowchart TD\n  A[Line one<br/>line two] --> B{a < b?}\n  B -->|x < y| C([p<q]) --> D>r < s]\n```\n\n```mermaid\nclassDiagram\n  class Order {\n    <<entity>>\n    +List<Item> items\n  }\n  Order : +Map<String, Item> index\n  Order <|-- Big : is<T>\n```\n' > "$TMP/mm/lt.md"
out=$(mmcheck "$TMP/mm/lt.md" 8000)
case "$out" in
  "0 2/2 mermaid diagram(s) parse"*) echo "  ✓ both diagrams parse, nothing hangs";;
  *) echo "  ✗ expected exit 0 and 2/2, got: $out"; fail=1;;
esac

echo "smoke: check-mermaid.cjs reports a diagram the parser never finishes, and exits"
# The edge-text form still sends the parser into that loop. The per-diagram deadline must turn it
# into a report that names the file and line — never a silent hang.
printf '```mermaid\nflowchart TD\n  A -- a < b --> B\n```\n' > "$TMP/mm/hang.md"
out=$(mmcheck "$TMP/mm/hang.md" 1500)
case "$out" in
  "2 "*"timeout parsing "*"hang.md:1"*) echo "  ✓ exit 2 with 'timeout parsing …hang.md:1'";;
  *) echo "  ✗ expected exit 2 and a timeout report, got: $out"; fail=1;;
esac

echo "smoke: check-mermaid.cjs checks every fence the page draws as a diagram, whatever its case"
# html-builder lowercases the language, so \`\`\`Mermaid renders as a diagram — and was never checked.
printf 'x\n\n```Mermaid\nstateDiagram-v2\n  [*] --> A : who : guard\n```\n' > "$TMP/mm/caps.md"
out=$(mmcheck "$TMP/mm/caps.md" 8000)
case "$out" in
  "1 "*"caps.md:3"*) echo "  ✓ a broken \`\`\`Mermaid block fails with its file:line";;
  *) echo "  ✗ expected exit 1 and caps.md:3, got: $out"; fail=1;;
esac

echo "smoke: check-mermaid.cjs leaves arrows alone beside quoted edge text and after a one-line class close"
# A bracket or pipe inside quoted edge text paired with a later one and the arrows between were swapped
# (--> became --›); a class body closed only on a bare `}` line, so `}` after the last member left every
# later relationship swapped (<|-- became ‹|--). Both turned valid diagrams into parse errors.
printf '```mermaid\nflowchart TD\n  A -- "a (b" --> B -- "c) d" --> C\n  C -- "x | y" --> D -- "z | w" --> E\n```\n\n```mermaid\nclassDiagram\n  class Order {\n    +int id\n    +List<Item> items }\n  Order <|-- Big\n  Order "1" --> "*" Item : has\n```\n' > "$TMP/mm/arrows.md"
out=$(mmcheck "$TMP/mm/arrows.md" 8000)
case "$out" in
  "0 2/2 mermaid diagram(s) parse"*) echo "  ✓ both diagrams parse";;
  *) echo "  ✗ expected exit 0 and 2/2, got: $out"; fail=1;;
esac
# Infinity, a value past setTimeout's 2^31-1 ms or a negative one became a 1 ms timer: every diagram "timed out".
for v in Infinity 99999999999 -5; do
  out=$(mmcheck "$TMP/mm/arrows.md" "$v")
  case "$out" in
    "0 2/2 mermaid diagram(s) parse"*) echo "  ✓ MM_TIMEOUT_MS=$v falls back to a usable deadline";;
    *) echo "  ✗ MM_TIMEOUT_MS=$v: expected exit 0 and 2/2, got: $out"; fail=1;;
  esac
done

echo "smoke: markdown emphasis never reaches into code spans, URLs or identifiers"
got=$(node -e '
  const { markdownToHtml } = require("./resources/html-builder.js");
  process.stdout.write(markdownToHtml([
    "Use `order_line_item_id` and `SELECT * FROM t WHERE a*2 > b*3`.", "",
    "See [docs](https://example.com/a_b_c) and ![d](https://example.com/x_y_z.png).", "",
    "snake_case_name stays, _this_ is emphasis, [**bold** link](https://e.com/p*q*r).",
  ].join("\n")));
')
bad=""
for want in '<code>order_line_item_id</code>' '<code>SELECT * FROM t WHERE a*2 &gt; b*3</code>' \
  'href="https://example.com/a_b_c"' 'src="https://example.com/x_y_z.png"' 'snake_case_name stays, <em>this</em> is emphasis' \
  '<a href="https://e.com/p*q*r" rel="noopener noreferrer" target="_blank"><strong>bold</strong> link</a>'; do
  printf '%s' "$got" | grep -qF -- "$want" || bad="$bad [$want]"
done
[ "$(printf '%s' "$got" | grep -o '<em>' | wc -l | tr -d ' ')" = "1" ] || bad="$bad [exactly one <em>]"
if [ -z "$bad" ]; then echo "  ✓ code spans, link and image URLs and snake_case stay literal; _this_ and **bold** still format"
else echo "  ✗ missing:$bad — got: $got"; fail=1; fi

echo "smoke: a link or image URL never carries markup into an attribute"
# Code spans and images are held as placeholders while emphasis runs. A URL that took one in had it
# restored inside href="…": the image's own <img src="…"> closed the attribute and the URL added its own.
why=$(node -e '
  const { markdownToHtml } = require("./resources/html-builder.js");
  const bad = [];
  const check = (md, want) => {
    const got = markdownToHtml(md);
    // Every tag must be one the builder emits, with exactly its attributes, and no quote or > outside one.
    const TAG = /<\/?(?:p|code|strong|em|del)>|<\/a>|<a href="https?:\/\/[^"<>\s]*" rel="noopener noreferrer" target="_blank">|<img src="[^"<>\s]*" alt="[^"<>]*">/y;
    for (let i = 0; i < got.length; i++) {
      if (got[i] === "<") { TAG.lastIndex = i; const m = TAG.exec(got); if (!m) { bad.push(`foreign markup in ${got}`); return; } i += m[0].length - 1; }
      else if (got[i] === ">" || got[i] === "\"") { bad.push(`bare ${got[i]} in ${got}`); return; }
    }
    if (/<[^>]*\s(?:style|on[a-z]+|autofocus)\b/i.test(got)) bad.push(`injected attribute in ${got}`);
    if (want && !got.includes(want)) bad.push(`missing ${want} in ${got}`);
  };
  check("[x](https://e.com/![a](https://q/style=position:fixed;inset:0))");
  check("[x](https://e.com/![a](https://q/x\"onfocus=alert(1)autofocus=\"))");
  check("![i](https://e.com/![a](https://q/\"onerror=alert(1)\"))");
  check("[x](https://e.com/`\"onmouseover=alert(1)`)");
  check("![`a\"b`](x.png)", "<img src=\"x.png\" alt=\"a&quot;b\">");
  check("[![CI](https://g.com/b.svg)](https://g.com/a_b)",
    "<a href=\"https://g.com/a_b\" rel=\"noopener noreferrer\" target=\"_blank\"><img src=\"https://g.com/b.svg\" alt=\"CI\"></a>");
  check("[`x`](https://e.com/a_b)", "<a href=\"https://e.com/a_b\" rel=\"noopener noreferrer\" target=\"_blank\"><code>x</code></a>");
  process.stdout.write(bad.join("\n    "));
' 2>&1)
if [ -z "$why" ]; then echo "  ✓ no style/on*/autofocus attribute and no quote out of href; a badge link and a code-span link still link"
else echo "  ✗ $why"; fail=1; fi

echo "smoke: a code span closes on a backtick run of its own length"
# Spans paired by single backticks only: `` $` `` closed at the inner backtick and held the rest raw.
got=$(node -e '
  const { markdownToHtml } = require("./resources/html-builder.js");
  process.stdout.write(markdownToHtml("Use `` $` `` or ``a`b``, then `x_y` and ` a ` and `*p*` here."));
')
if [ "$got" = '<p>Use <code>$`</code> or <code>a`b</code>, then <code>x_y</code> and <code> a </code> and <code>*p*</code> here.</p>' ]; then
  echo "  ✓ double-backtick spans hold a backtick; single-backtick spans are unchanged"
else echo "  ✗ got: $got"; fail=1; fi

echo "smoke: a code fence opens whatever its language is written as"
# \`\`\`(\w*) refused c#, c++, objective-c, shell-session and 'js title=x', and the rest of the
# document then rendered inside one <pre>.
got=$(node -e '
  const { markdownToHtml } = require("./resources/html-builder.js");
  process.stdout.write(markdownToHtml("```c#\nvar a;\n```\n\nafter c#\n\n```c++\nint b;\n```\n\n```objective-c\n@x\n```\n\n```shell-session\n$ ls\n```\n\n```js title=x\nlet y;\n```\n\n```Mermaid\nflowchart TD\n  A-->B\n```\n\nend\n"));
')
if [ "$(printf '%s' "$got" | grep -o '<pre><code>' | wc -l | tr -d ' ')" = "5" ] && printf '%s' "$got" | grep -qF '<p>after c#</p>' \
   && printf '%s' "$got" | grep -qF '<p>end</p>' && printf '%s' "$got" | grep -qF '<div class="mermaid">flowchart TD'; then
  echo "  ✓ five code blocks close where they should, and \`\`\`Mermaid is a diagram"
else echo "  ✗ fences mis-parsed: $got"; fail=1; fi

echo "smoke: generated pages keep their text and their browser regexes intact"
printf '# CDN\n\nWe load jQuery from https://cdnjs.cloudflare.com/ajax/libs/jquery/3.7.1/jquery.min.js today.\n\n```mermaid\nflowchart TD\n  A --> B\n```\n' > "$TMP/cdn.md"
node resources/render-html.cjs "$TMP/cdn.md" "$TMP/cdn.html" >/dev/null 2>&1
# The CDN-allowlist cleanup ran over the whole page and cut the URL out of the text ("from/ajax/…").
if grep -qF 'from https://cdnjs.cloudflare.com/ajax/libs/jquery/3.7.1/jquery.min.js today' "$TMP/cdn.html" \
   && { ! grep -q 'vendored mermaid' "$TMP/cdn.html" || ! grep -o '<meta http-equiv="Content-Security-Policy" content="[^"]*"' "$TMP/cdn.html" | grep -q cdnjs; }; then
  echo "  ✓ render-html: a cdnjs URL in the text survives; the CSP drops cdnjs when the bundle is inlined"
else echo "  ✗ render-html: the text lost its URL, or the CSP kept cdnjs"; fail=1; fi
mkdir -p "$TMP/cdnproj/src"
printf '/**\n * Loads jQuery from https://cdnjs.cloudflare.com/ajax/libs/jquery/3.7.1/jquery.min.js at runtime.\n */\nexport class Loader {\n  run() { return 1; }\n}\n' > "$TMP/cdnproj/src/loader.ts"
PROVENLENS=0 node skills/cwk-map/references/build-map.cjs "$TMP/cdnproj" "$TMP/cdnmap.html" all >/dev/null 2>&1
if grep -qF 'jQuery from https://cdnjs.cloudflare.com/ajax/libs/jquery' "$TMP/cdnmap.html"; then echo "  ✓ build-map: a cdnjs URL in a doc comment survives"
else echo "  ✗ build-map: the URL was cut out of the graph text"; fail=1; fi
# A `\s` in a template literal reaches the browser as `s`: /LS-([^\s]+)/ became /LS-([^s]+)/.
if grep -qF 'LS-([^\s]+)' "$TMP/cdn.html" && ! grep -qF 'LS-([^s]+)' "$TMP/cdn.html"; then echo "  ✓ render-html: the edge-colouring regex arrives with its \\s"
else echo "  ✗ render-html: the browser receives LS-([^s]+)"; fail=1; fi

echo "smoke: kb-site treats a repo with its own projects/ folder as one repo"
# An Angular workspace or a monorepo has a top-level projects/; that alone made it a "hub" with no KB.
mkdir -p "$TMP/ng/projects/app/src" "$TMP/ng/knowledge-base"
printf '# Overview\n\nThe app.\n' > "$TMP/ng/knowledge-base/01-overview.md"
out=$(node scripts/kb-site.cjs "$TMP/ng" 2>&1); code=$?
if [ "$code" -eq 0 ] && [ -f "$TMP/ng/knowledge-base/index.html" ] && [ ! -e "$TMP/ng/index.html" ]; then echo "  ✓ built from knowledge-base/, written inside it"
else echo "  ✗ expected knowledge-base/index.html, got $code: $out"; fail=1; fi
if grep -qF 'LS-([^\s]+)' "$TMP/ng/knowledge-base/index.html" && ! grep -qF 'LS-([^s]+)' "$TMP/ng/knowledge-base/index.html"; then echo "  ✓ kb-site: the edge-colouring regex arrives with its \\s"
else echo "  ✗ kb-site: the browser receives LS-([^s]+)"; fail=1; fi

echo "smoke: strip-map-source.cjs removes the source excerpts a sampled map embeds"
# provenlens-graph.cjs gives every node of the sampled viewer a 25-line `source` excerpt; the plain-JSON
# block used to be copied into the hub untouched. Fixture: the map built above, with excerpts added.
node -e '
  const fs = require("fs"); const h = fs.readFileSync(process.argv[1], "utf8");
  const m = /<script\b[^>]*\bid="graph-data"[^>]*>/.exec(h); const s = m.index + m[0].length, e = h.indexOf("</script>", s);
  const g = JSON.parse(h.slice(s, e));
  g.nodes.forEach((n) => { n.source = "SECRET_SRC() { return \"</script><b>\"; }"; });
  fs.writeFileSync(process.argv[2], h.slice(0, s) + JSON.stringify(g).replace(/</g, "\\u003c").replace(/>/g, "\\u003e") + h.slice(e));
' "$TMP/map.html" "$TMP/map-src.html"
node scripts/strip-map-source.cjs "$TMP/map-src.html" "$TMP/map-stripped.html" >/dev/null 2>&1; code=$?
why=$(node -e '
  const fs = require("fs");
  const block = (f) => { const h = fs.readFileSync(f, "utf8"); const m = /<script\b[^>]*\bid="graph-data"[^>]*>/.exec(h);
    const s = m.index + m[0].length; return h.slice(s, h.indexOf("</script>", s)); };
  const before = JSON.parse(block(process.argv[1])), raw = block(process.argv[2]), after = JSON.parse(raw), bad = [];
  if (!before.nodes.length || !before.nodes.every((n) => n.source)) bad.push("fixture carries no excerpt");
  if (fs.readFileSync(process.argv[2], "utf8").includes("SECRET_SRC")) bad.push("excerpt still in the page");
  if (after.nodes.length !== before.nodes.length || after.edges.length !== before.edges.length) bad.push("nodes or edges changed");
  if (after.metadata.source !== before.metadata.source || after.metadata.sourceStripped !== true) bad.push("metadata not kept/marked");
  if (/[<>]/.test(raw)) bad.push("< or > unescaped in the block");
  process.stdout.write(bad.join("; "));
' "$TMP/map-src.html" "$TMP/map-stripped.html" 2>&1)
if [ "$code" -eq 0 ] && [ -z "$why" ]; then echo "  ✓ exit 0: excerpts gone, nodes/edges/labels kept, block re-escaped"
else echo "  ✗ exit $code: $why"; fail=1; fi
node scripts/strip-map-source.cjs "$TMP/map.html" "$TMP/map-nosrc.html" >/dev/null 2>&1; code=$?
if [ "$code" -eq 2 ] && [ ! -e "$TMP/map-nosrc.html" ]; then echo "  ✓ a sampled map with no excerpt: exit 2, nothing written"
else echo "  ✗ expected exit 2 and no output for a map with nothing to strip, got $code"; fail=1; fi

echo "smoke: provenlens-full.cjs degrades on an empty or corrupt index"
# The schema-version query sat outside any try: /cwk-map crashed on "no such table: meta".
mkdir -p "$TMP/pl0/.provenlens" "$TMP/pl1/.provenlens"
: > "$TMP/pl0/.provenlens/index.db"
printf 'not a database — just text long enough to stand where a sqlite header would be\n' > "$TMP/pl1/.provenlens/index.db"
for d in pl0 pl1; do
  why=$(node --no-warnings -e '
    try { const r = require("./skills/cwk-map/references/provenlens-full.cjs").buildFullIndex(process.argv[1]); console.log(r.ok ? "UNEXPECTED-OK" : r.why); }
    catch (e) { console.log("THREW: " + e.message); }
  ' "$TMP/$d" 2>&1)
  case "$why" in
    THREW*|UNEXPECTED-OK) echo "  ✗ $d: $why"; fail=1;;
    *"index"*|*"node:sqlite"*) echo "  ✓ $d: reports why, does not throw: $why";;
    *) echo "  ✗ $d: expected a graceful reason, got: $why"; fail=1;;
  esac
done

echo "smoke: html-to-pdf.sh never reports an old PDF, never deletes its input, and replaces the output only on success"
# Success was judged by the output being non-empty, so a PDF from an earlier run passed. Deleting the
# output up front, after a path-string compare, then deleted the INPUT when the output named it another
# way (./in.html, a symlink, a hard link) — even with no engine installed. Engines now write a fresh
# temp file that replaces the output only once it holds a PDF; the input is refused by identity (-ef).
# Hermetic: the /Applications browsers are masked in a copy and PATH holds one fake engine.
P="$TMP/pdf"; mkdir -p "$P/bin"
sed 's#"/Applications/#"/nonexistent/#g' skills/cwk-pdf/references/html-to-pdf.sh > "$P/html-to-pdf.sh"
for t in mkdir dirname rm mktemp mv; do ln -s "$(command -v "$t")" "$P/bin/$t"; done
printf '#!/bin/sh\nexit 1\n' > "$P/bin/google-chrome"; chmod +x "$P/bin/google-chrome"
printf '<html><body>x</body></html>\n' > "$P/in.html"; printf 'STALE' > "$P/in.pdf"
out=$(PATH="$P/bin" "$BASH" "$P/html-to-pdf.sh" "$P/in.html" 2>&1); code=$?
if [ "$code" -eq 2 ] && [ "$out" = "NO_PDF_TOOL" ] && [ "$(cat "$P/in.pdf")" = "STALE" ]; then echo "  ✓ every engine fails: exit 2, NO_PDF_TOOL, the old PDF neither reported nor touched"
else echo "  ✗ expected exit 2 and only NO_PDF_TOOL, got $code: $out"; fail=1; fi
ln -s in.html "$P/link.pdf"; ln "$P/in.html" "$P/hard.pdf"
bad=""
for o in ./in.html link.pdf hard.pdf; do
  out=$(cd "$P" && PATH="$P/bin" "$BASH" html-to-pdf.sh in.html "$o" 2>&1); code=$?
  { [ "$code" -eq 1 ] && printf '%s' "$out" | grep -q 'would overwrite the input'; } || bad="$bad [$o: $code $out]"
done
[ "$(cat "$P/in.html" 2>/dev/null)" = '<html><body>x</body></html>' ] || bad="$bad [the input was changed or deleted]"
if [ -z "$bad" ]; then echo "  ✓ ./in.html, a symlink and a hard link to the input are refused; the input is intact"
else echo "  ✗$bad"; fail=1; fi
printf '#!/bin/sh\nfor a in "$@"; do case "$a" in --print-to-pdf=*) printf "%%%%PDF-new" > "${a#--print-to-pdf=}"; exit 0;; esac; done\nexit 1\n' > "$P/bin/google-chrome"
out=$(PATH="$P/bin" "$BASH" "$P/html-to-pdf.sh" "$P/in.html" 2>&1); code=$?
if [ "$code" -eq 0 ] && [ "$out" = "$P/in.pdf" ] && [ "$(cat "$P/in.pdf")" = "%PDF-new" ] && [ -z "$(find "$P" -name '.cwk-pdf.*')" ]; then
  echo "  ✓ an engine that succeeds replaces the old PDF and leaves no temp file behind"
else echo "  ✗ expected exit 0, $P/in.pdf holding the new PDF and no .cwk-pdf.* left, got $code: $out"; fail=1; fi

echo "smoke: print-fix.cjs PDF_LIGHT=1 turns round every colour the kit's dark page sets"
# The light palette overrode only html, body, a and .mermaid: headings, table cells, code and the
# diagrams kept their near-white text on the now-white page. html-builder pins its diagram colours
# with !important, which only a later !important rule on the same selector can beat.
node resources/render-html.cjs "$TMP/mm/good.md" "$TMP/dark.html" >/dev/null 2>&1
PDF_LIGHT=1 node skills/cwk-pdf/references/print-fix.cjs "$TMP/dark.html" "$TMP/light.html"
why=$(node -e '
  const page = require("fs").readFileSync(process.argv[1], "utf8");
  const at = page.indexOf("<style id=\"cwk-print-css\">");
  const kit = (/<style>\s*\*,\*::before[\s\S]*?<\/style>/.exec(page) || [""])[0];
  const rules = (css) => [...css.replace(/\/\*[\s\S]*?\*\//g, "").matchAll(/([^{}]+)\{([^{}]*)\}/g)]
    .map((m) => ({ sel: m[1].split(",").map((s) => s.trim()), body: m[2] }));
  const pins = (r) => /(^|;)\s*(color|fill|background)[^;]*!important/.test(r.body);
  const light = at < 0 ? "" : page.slice(at);
  const covered = new Set(rules(light).filter(pins).flatMap((r) => r.sel));
  const miss = new Set();
  if (!kit || !light) miss.add("stylesheet not found");
  for (const r of rules(kit)) if (pins(r)) r.sel.forEach((s) => covered.has(s) || miss.add(s));
  for (const s of ["h1", "h2", "h3", "h4", "th", "td", "code", "pre", "blockquote"]) if (!covered.has(s)) miss.add(s);
  if (!/@page\{background:#fff\}/.test(light)) miss.add("@page background");
  process.stdout.write([...miss].join(" | "));
' "$TMP/light.html" 2>&1)
if [ -z "$why" ]; then echo "  ✓ headings, tables, code, quotes, every pinned diagram colour and @page are re-pinned for paper"
else echo "  ✗ not turned round for paper: $why"; fail=1; fi

echo "smoke: shadow-parity.cjs tells integers past 2^53 apart, and still ignores decimal scale"
# JSON.parse rounds 9007199254740993 to 9007199254740992, so two different 64-bit ids compared equal.
out=$(node -e '
  const http = require("http"), { execFile } = require("child_process"), fs = require("fs");
  const [script, cases] = process.argv.slice(1);
  const serve = (body) => new Promise((ok) => { const s = http.createServer((q, r) => { r.setHeader("content-type", "application/json"); r.end(body); }).listen(0, "127.0.0.1", () => ok(s)); });
  (async () => {
    const a = await serve(`{"id":9007199254740993,"amount":10.50,"s":"q\\"9007199254740993","n":-9007199254740993}`);
    const b = await serve(`{"id":9007199254740992,"amount":10.5,"s":"q\\"9007199254740993","n":-9007199254740993}`);
    fs.writeFileSync(cases, JSON.stringify({ cases: [{ name: "ids", type: "rest", rest: { method: "GET", path: "/" } }] }));
    execFile(process.execPath, [script, cases, "--source", `http://127.0.0.1:${a.address().port}`, "--target", `http://127.0.0.1:${b.address().port}`],
      (err, stdout) => { process.stdout.write(`${err ? err.code : 0}\n${stdout}`); a.close(); b.close(); });
  })();
' skills/cwk-rails-to-spring/references/shadow-parity.cjs "$TMP/parity-cases.json" 2>&1)
if [ "$(printf '%s\n' "$out" | head -1)" = "1" ] && printf '%s' "$out" | grep -qF 'Δ id:  source=<int:9007199254740993>  target=<int:9007199254740992>' \
   && printf '%s' "$out" | grep -qF '1 field diff(s)'; then
  echo "  ✓ the ids differ digit for digit; 10.50 vs 10.5, a quoted number and an equal big int do not"
else echo "  ✗ expected exactly one diff, on id: $out"; fail=1; fi

echo "smoke: shadow-parity.cjs holds back every GraphQL mutation, and a per-case header removal removes it"
# A mutation counted only when the document STARTED with `mutation`: one opening with a fragment, or a
# multi-operation document whose operationName picks the mutation, went to both services — a double
# write on a shared database. Header layers merged case-sensitively, so a per-case "authorization": ""
# left the global "Authorization" (credential and all) on the request.
why=$(node -e '
  const http = require("http"), { execFile } = require("child_process"), fs = require("fs");
  const [script, cases] = process.argv.slice(1);
  const seen = [];
  const serve = () => new Promise((ok) => { const s = http.createServer((q, r) => {
    let b = ""; q.on("data", (d) => { b += d; });
    q.on("end", () => { seen.push({ url: q.url, auth: q.headers.authorization, body: b }); r.setHeader("content-type", "application/json"); r.end("{\"data\":{}}"); });
  }).listen(0, "127.0.0.1", () => ok(s)); });
  (async () => {
    const a = await serve(), b = await serve();
    fs.writeFileSync(cases, JSON.stringify({ headers: { both: { Authorization: "Bearer global-secret" } }, cases: [
      { name: "fragment-first", type: "graphql", graphql: { query: "fragment F on Order { id }\nmutation Pay { pay(id: 1) { ...F } }" } },
      { name: "multi-op", type: "graphql", graphql: { query: "query Get { order(id: 1) { id } }\nmutation Pay { pay(id: 1) { id } }", operationName: "Pay" } },
      { name: "read", type: "graphql", graphql: { query: "# a mutation, in a comment\nquery Q { note(text: \"} mutation {\") { id } }" } },
      { name: "no-auth", type: "rest", rest: { method: "GET", path: "/no-auth" }, headers: { both: { authorization: "" } } },
      { name: "auth", type: "rest", rest: { method: "GET", path: "/auth" } },
    ] }));
    execFile(process.execPath, [script, cases, "--source", `http://127.0.0.1:${a.address().port}`, "--target", `http://127.0.0.1:${b.address().port}`],
      { env: { ...process.env, SOURCE_TOKEN: "tok-src", TARGET_TOKEN: "tok-tgt" } }, (err, stdout) => {
      a.close(); b.close();
      const bad = [];
      if (!err || err.code !== 1) bad.push(`exit ${err ? err.code : 0}`);
      for (const n of ["fragment-first", "multi-op"]) if (!new RegExp(`FAIL  ${n}\\n\\s+- not run: write case`).test(stdout)) bad.push(`${n} not held back`);
      for (const n of ["read", "no-auth", "auth"]) if (!stdout.includes(`PASS  ${n}\n`)) bad.push(`${n} did not pass`);
      if (seen.some((x) => /pay\(/.test(x.body))) bad.push("a mutation reached a server");
      if (seen.filter((x) => x.url === "/no-auth").length !== 2 || seen.some((x) => x.url === "/no-auth" && x.auth !== undefined)) bad.push("Authorization reached /no-auth");
      if (seen.filter((x) => x.url === "/auth" && x.auth === "Bearer global-secret").length !== 2) bad.push("the global Authorization did not reach /auth");
      process.stdout.write(bad.length ? `${bad.join("; ")}\n${stdout}` : "");
    });
  })();
' skills/cwk-rails-to-spring/references/shadow-parity.cjs "$TMP/parity-writes.json" 2>&1)
if [ -z "$why" ]; then echo "  ✓ fragment-first and multi-operation mutations are \"not run\"; no Authorization reaches a case that removes it"
else echo "  ✗ $why"; fail=1; fi

echo "smoke: $([ "$fail" -eq 0 ] && echo PASS || echo FAIL)"
[ "$fail" -eq 0 ]
