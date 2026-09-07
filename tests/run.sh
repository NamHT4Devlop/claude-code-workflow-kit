#!/usr/bin/env bash
# Run the full test suite. Used locally and by CI.
set -uo pipefail
cd "$(dirname "$0")/.."
rc=0
echo "== bundles in sync? =="; bash scripts/sync-bundles.sh --check || rc=1
echo; echo "== git-guard =="; bash tests/git-guard.test.sh || rc=1
echo; echo "== smoke =="; bash tests/smoke.test.sh || rc=1
echo; echo "== skill name == folder? =="
names_rc=0
for d in skills/*/; do d=${d%/}; n=$(grep -m1 '^name:' "$d/SKILL.md" | awk '{print $2}'); [ "$n" = "$(basename "$d")" ] || { echo "  ✗ $(basename "$d") != $n"; names_rc=1; }; done
[ "$names_rc" -eq 0 ] && echo "  ✓ skill names OK" || rc=1
echo; echo "== consistency =="; bash tests/consistency.test.sh || rc=1
echo; echo "== migrate-sessions (touches real user data) =="; bash tests/migrate-sessions.test.sh || rc=1
echo; echo "== schedule (edits the user's crontab) =="; bash tests/schedule.test.sh || rc=1
echo; echo "== personal-install (deletes links under ~/.claude) =="; bash tests/personal-install.test.sh || rc=1
echo; echo "== onboard-project (writes into other repos) =="; bash tests/onboard.test.sh || rc=1
echo; echo "== kb hub export/import (moves real Knowledge Bases) =="; bash tests/kb-hub.test.sh || rc=1
echo; echo "== kb pipeline (spends tokens over other people's repos) =="; bash tests/kb-pipeline.test.sh || rc=1
echo; echo "== webview markdown (renders untrusted model output) =="
if command -v node >/dev/null 2>&1; then node tests/webview-markdown.test.cjs || rc=1
else echo "  – skipped (node not installed)"; fi
echo; echo "== webview scripts parse (tsc only covers src/, never media/) =="
if command -v node >/dev/null 2>&1; then
  for f in vscode-extension/media/main.js vscode-extension/media/i18n.js; do
    node --check "$f" && echo "  ✓ $f" || rc=1
  done
else echo "  – skipped (node not installed)"; fi
echo; echo "== Vietnamese UI strings still match the UI =="
if command -v node >/dev/null 2>&1; then node tests/i18n.test.cjs || rc=1
else echo "  – skipped (node not installed)"; fi
echo; echo "== vendored libs unchanged? =="
if [ -f vendor/SHA256SUMS ]; then
  if (cd vendor && shasum -a 256 -c SHA256SUMS >/dev/null 2>&1); then
    echo "  ✓ vendor bundles match their pinned hashes"
  else
    echo "  ✗ a vendored library differs from vendor/SHA256SUMS — see vendor/README.md before trusting it"
    (cd vendor && shasum -a 256 -c SHA256SUMS 2>&1 | grep -v ': OK$' | sed 's/^/    /')
    rc=1
  fi
else
  echo "  ✗ vendor/SHA256SUMS missing"; rc=1
fi
echo; [ "$rc" -eq 0 ] && echo "✅ ALL TESTS PASSED" || echo "❌ TESTS FAILED"
exit $rc
