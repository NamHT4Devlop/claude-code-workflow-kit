#!/usr/bin/env bash
# fetch-vendor.sh — obtain the vendored render libraries instead of copying 3.6 MB by hand.
#
# Why they exist: generated HTML reports inline Mermaid/Cytoscape so a diagram renders with NO
# network call at view time. Without vendor/ the HTML falls back to a cdnjs <script> — fine on a
# machine with open internet, broken behind a proxy that blocks CDNs.
#
# Order of preference (most policy-friendly first):
#   1. npm  — respects the registry in your .npmrc, so on a company machine this pulls from the
#             internal mirror/Artifactory your org already vets. Verified byte-identical to cdnjs.
#   2. curl — direct from cdnjs, for machines without npm.
# Whatever the source, every file is checked against vendor/SHA256SUMS before it is installed:
# a mismatch aborts rather than silently trusting the download.
#
# Usage:
#   scripts/fetch-vendor.sh            # fetch what's missing, verify, install
#   scripts/fetch-vendor.sh --check    # verify what's already there, change nothing
#   scripts/fetch-vendor.sh --force    # re-fetch even if present
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
VENDOR="vendor"
MODE="${1:-}"

# name:version:path-inside-npm-package:cdnjs-path   (keep versions in step with vendor/README.md)
LIBS=(
  "mermaid:10.9.8:package/dist/mermaid.min.js:mermaid/10.9.8/mermaid.min.js"
  "cytoscape:3.30.2:package/dist/cytoscape.min.js:cytoscape/3.30.2/cytoscape.min.js"
)

sha() { shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'; }
want() { awk -v f="$1" '$2==f {print $1}' "$VENDOR/SHA256SUMS" 2>/dev/null; }

verify_all() {
  [ -f "$VENDOR/SHA256SUMS" ] || { echo "✖ $VENDOR/SHA256SUMS missing — cannot verify"; return 1; }
  ( cd "$VENDOR" && shasum -a 256 -c SHA256SUMS )
}

if [ "$MODE" = "--check" ]; then
  echo "▶ verifying $VENDOR against SHA256SUMS"
  verify_all && echo "✔ vendored libraries match their pinned hashes"
  exit $?
fi

mkdir -p "$VENDOR"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
missing=0

for spec in "${LIBS[@]}"; do
  IFS=: read -r name ver inpkg cdnpath <<<"$spec"
  file="$name.min.js"; dest="$VENDOR/$file"; expect="$(want "$file")"

  if [ -f "$dest" ] && [ "$MODE" != "--force" ]; then
    if [ -n "$expect" ] && [ "$(sha "$dest")" = "$expect" ]; then
      echo "  ✓ $file already present and verified"; continue
    fi
    echo "  ! $file present but does NOT match SHA256SUMS — re-fetching"
  fi

  got=""
  if command -v npm >/dev/null 2>&1; then
    echo "  ↓ $name@$ver via npm ($(npm config get registry))"
    if ( cd "$TMP" && npm pack "$name@$ver" --silent >/dev/null 2>&1 ) \
       && tar -xzf "$TMP/$name-$ver.tgz" -C "$TMP" "$inpkg" 2>/dev/null; then
      got="$TMP/$inpkg"
    else
      echo "    npm failed (offline, or the version is not in your registry)"
    fi
  fi

  if [ -z "$got" ] && command -v curl >/dev/null 2>&1; then
    echo "  ↓ $name@$ver via cdnjs"
    curl -fsSL "https://cdnjs.cloudflare.com/ajax/libs/$cdnpath" -o "$TMP/$file" && got="$TMP/$file"
  fi

  if [ -z "$got" ] || [ ! -s "$got" ]; then
    echo "  ✖ could not obtain $file (no npm, no curl, or both blocked)"; missing=1; continue
  fi

  actual="$(sha "$got")"
  # An empty $expect means the file has no pinned hash. Installing it anyway would contradict
  # this script's own promise, and the bytes end up inlined verbatim into KB/report HTML that
  # gets shared — so refuse rather than install something unverifiable.
  if [ -z "$expect" ]; then
    echo "  ✖ $file has no pinned hash in $VENDOR/SHA256SUMS — refusing to install it"
    missing=1; continue
  fi
  if [ "$actual" != "$expect" ]; then
    echo "  ✖ $file hash MISMATCH — refusing to install"
    echo "      expected $expect"
    echo "      got      $actual"
    echo "    Either the upstream artifact changed or the download was tampered with."
    echo "    Investigate before trusting it; see $VENDOR/README.md."
    missing=1; continue
  fi
  cp "$got" "$dest"
  echo "  ✓ $file installed and verified"
done

if [ "$missing" -ne 0 ]; then
  cat <<'EOS'

✖ Some libraries are missing. The toolkit still works — generated HTML will simply link
  Mermaid/Cytoscape from cdnjs, which needs internet when you OPEN the report. If this machine is
  behind a proxy that blocks CDNs, copy vendor/*.min.js from a machine that has them, then run
  scripts/fetch-vendor.sh --check to confirm the hashes.
EOS
  exit 1
fi

echo
verify_all && echo "✔ vendor/ complete and verified — reports will render offline"
