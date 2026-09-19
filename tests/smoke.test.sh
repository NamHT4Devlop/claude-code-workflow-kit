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

echo "smoke: $([ "$fail" -eq 0 ] && echo PASS || echo FAIL)"
[ "$fail" -eq 0 ]
