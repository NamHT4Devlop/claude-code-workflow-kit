# vendor/ — pinned third-party libraries

These minified bundles are inlined into generated HTML so reports render **offline** (no CDN call).
They are large and unreadable, which makes a malicious edit easy to miss in review — so their hashes
are pinned in `SHA256SUMS` and verified by `tests/run.sh`.

| File | npm package | Version | License | Upstream CDN |
|---|---|---|---|---|
| `mermaid.min.js` | `mermaid` → `dist/mermaid.min.js` | 10.9.8 | MIT | https://cdnjs.cloudflare.com/ajax/libs/mermaid/10.9.8/mermaid.min.js |
| `cytoscape.min.js` | `cytoscape` → `dist/cytoscape.min.js` | 3.30.2 | MIT | https://cdnjs.cloudflare.com/ajax/libs/cytoscape/3.30.2/cytoscape.min.js |

Both bundles are **byte-identical** whether taken from npm or from cdnjs (verified against the hashes
below), so you can obtain them through whichever channel your organisation allows.

## Get them on a new machine (don't copy 3.6 MB by hand)
```bash
scripts/fetch-vendor.sh
```
It prefers **npm**, which honours the registry in your `.npmrc` — on a company machine that is your
internal mirror/Artifactory, i.e. the channel your org already vets — and falls back to cdnjs when npm
isn't available. Every download is checked against `SHA256SUMS` and a mismatch aborts the install.

## Verify
```bash
scripts/fetch-vendor.sh --check     # or: cd vendor && shasum -a 256 -c SHA256SUMS
```
`tests/run.sh` runs this check too.

## Optional
These files are only an **offline convenience**. Without them the generated HTML links Mermaid/
Cytoscape from cdnjs and renders fine on any machine with internet — you only need `vendor/` when the
network blocks CDNs or the machine is air-gapped.

## Updating a library
1. Download the new bundle from the upstream URL above (note the new version).
2. `cd vendor && shasum -a 256 *.min.js > SHA256SUMS`
3. Update the version in the table, and commit the bundle + SHA256SUMS + this table **together** —
   a hash change with no version bump in the same commit is the signal a reviewer looks for.
