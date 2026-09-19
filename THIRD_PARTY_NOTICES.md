# Third-party notices

The kit itself is MIT (see `LICENSE` and `NOTICE`). This file lists the third-party software it
redistributes, and the works whose design it adapts.

## Vendored libraries (`vendor/`)

Minified bundles inlined into generated HTML so reports render offline. Hashes are pinned in
`vendor/SHA256SUMS` and checked by `tests/run.sh`; `vendor/README.md` says how to fetch and update them.

| File | Package | Version | Licence | Upstream |
|---|---|---|---|---|
| `vendor/mermaid.min.js` | [mermaid](https://github.com/mermaid-js/mermaid) | 10.9.8 | MIT | https://cdnjs.cloudflare.com/ajax/libs/mermaid/10.9.8/mermaid.min.js |
| `vendor/cytoscape.min.js` | [cytoscape](https://github.com/cytoscape/cytoscape.js) | 3.30.2 | MIT | https://cdnjs.cloudflare.com/ajax/libs/cytoscape/3.30.2/cytoscape.min.js |

Both are distributed under the MIT License; the copyright notices are retained inside the bundles.

## Adapted designs (no code copied)

| Work | Licence | What was adapted | Where |
|---|---|---|---|
| [alibaba/open-code-review](https://github.com/alibaba/open-code-review) | Apache-2.0 | The review pipeline design: account for every file, group, review with language traps, fact-check, present | `resources/review-protocol.md` (bundled into `skills/cwk-review` and `skills/cwk-pr` as `references/review-protocol.md`) |
| [addyosmani/agent-skills](https://github.com/addyosmani/agent-skills) | see upstream repository | The Rationalizations / Red flags / Verification trailer | `docs/skill-anatomy.md`, the high-stakes skills |

## Not covered here

`vscode-extension/` is proprietary (its own `LICENSE`; `"license": "UNLICENSED"` in `package.json`)
and has no runtime dependencies; its dev dependencies (`typescript`, `@types/*`) are not redistributed.
