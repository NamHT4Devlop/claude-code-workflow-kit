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
node skills/namht-map/references/build-map.cjs "$TMP/proj" "$TMP/map.html" all >/dev/null 2>&1
if grep -q 'id="graph-data"' "$TMP/map.html" && grep -q '"nodes"' "$TMP/map.html"; then echo "  ✓ build-map produced graph HTML"; else echo "  ✗ build-map failed"; fail=1; fi

# The map is drawn from a resolved call graph when a .codelens/ index is there and from a regex
# scan when it is not. Those edges are not worth the same, so every graph must name its source —
# an unlabelled one silently invites a reader to trust an import line as if it were a call.
# This fixture has no index, so it must take the fallback AND say so.
if grep -q '"source"' "$TMP/map.html" && grep -q 'static import/inheritance scan' "$TMP/map.html"; then
  echo "  ✓ build-map labelled its graph source (fallback path)"
else
  echo "  ✗ build-map produced a graph with no source label"; fail=1
fi

echo "smoke: codelens-graph.cjs degrades without an index"
why=$(node -e '
  const { buildFromCodelens, uncoveredLanguages } = require("./skills/namht-map/references/codelens-graph.cjs");
  const r = buildFromCodelens(process.argv[1]);
  if (r.ok) { console.log("UNEXPECTED-OK"); process.exit(0); }
  console.log(r.why);
' "$TMP/proj" 2>&1)
case "$why" in
  *".codelens"*|*"not on PATH"*) echo "  ✓ reports why, does not throw: $why";;
  *) echo "  ✗ expected a graceful reason, got: $why"; fail=1;;
esac

echo "smoke: codelens-graph.cjs exposes what the index holds"
# indexedLanguages() is how the adapter notices it drew a neighbourhood rather than a repository.
# Without an index it must return an empty list, not throw and not invent one.
held=$(node -e '
  const { indexedLanguages } = require("./skills/namht-map/references/codelens-graph.cjs");
  const r = indexedLanguages(process.argv[1]);
  console.log(Array.isArray(r) ? `array:${r.length}` : typeof r);
' "$TMP/proj" 2>&1)
if [ "$held" = "array:0" ]; then echo "  ✓ empty list without an index"; else echo "  ✗ expected array:0, got: $held"; fail=1; fi

echo "smoke: codelens-graph.cjs names a language it cannot cover"
printf 'def handler():\n    return 1\n' > "$TMP/proj/worker.py"
langs=$(node -e '
  const { uncoveredLanguages } = require("./skills/namht-map/references/codelens-graph.cjs");
  console.log(uncoveredLanguages(process.argv[1]).join(","));
' "$TMP/proj" 2>&1)
if [ "$langs" = "Python" ]; then echo "  ✓ Python reported as uncovered"; else echo "  ✗ expected Python, got: $langs"; fail=1; fi

echo "smoke: $([ "$fail" -eq 0 ] && echo PASS || echo FAIL)"
[ "$fail" -eq 0 ]
