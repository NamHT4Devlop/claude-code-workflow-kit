---
name: cwk-map
description: >-
  Generate an INTERACTIVE HTML dependency graph of a codebase (Cytoscape.js) —
  nodes are files/classes/routes, edges are real imports, dependency injection,
  inheritance (extends/implements) and method calls, colored by architecture
  layer, with zoom/pan, click-to-highlight-neighbors, search, layer filters and
  hub highlighting. Opens in the browser. Use when the user asks to "/map", "map
  the codebase", "show the dependency graph", "code graph", or "visualize architecture".
---

# cwk-map — interactive code graph (HTML)

Produces a **single self-contained interactive HTML file** (Cytoscape.js) — NOT a Markdown/
Mermaid dump. It runs a bundled, dependency-free multi-language static analyzer
(`references/graph-builder.js`, pure Node `fs`/`path`) supporting TS/JS, Python, Java/Kotlin,
Go, Ruby, C#, PHP and Rust, then injects the graph into `references/viewer-template.html`.

### provenlens (optional)
`.provenlens/` present → prefer `provenlens` over grep for anything about **who calls what**: it resolves
through DI, interfaces, mixins and framework string-bindings (MyBatis · Camel · SQS · Kafka · HTTP routes · Spring events · GraphQL · gRPC · Flyway) and
scores every edge. Confirm it with `provenlens status`, and run `provenlens sync` first if the working
tree has moved since it was built — **a stale index is worse than none, because it looks
authoritative**. If coverage reads low, `provenlens doctor` says whether that is a resolver limit or
just an uninstalled dependency; those look identical in the number and are nothing alike in the fix.
No index, no `provenlens` command, or a language it does not cover (**Java · Ruby · TS/JS** only) →
fall back to Grep/Glob and write `⚠️ grep-depth only (no provenlens index)` in the output. A grep hit
is never a resolved call — do not report it as one. Playbook: `docs/provenlens.md`.

**Here:**
- **`build-map.cjs` already does the choosing — you do not.** It calls
  `references/provenlens-graph.cjs` first: with a `.provenlens/` index and `provenlens` on PATH it draws
  the **resolved call graph** (edges are real calls, each labelled with its `via` and confidence);
  otherwise it falls back to the regex scan and prints why on stderr. Read that line and repeat it
  in your summary.
- **The viewer says which one drew it** — the meta bar reads `provenlens (resolved call graph)` or
  `static import/inheritance scan`. Never describe a regex edge as a call.
- **Uncovered languages are named, not hidden.** If the tree holds Python, Go, C#, PHP, Rust,
  Kotlin, Scala, Swift or C/C++, stderr warns that those files are absent from a provenlens graph.
  **Put that in the summary** — a map that silently drops a service is worse than one that admits
  the hole.
- **The resolved graph can be a neighbourhood, not the repository.** `provenlens export` seeds from
  the busiest hubs and stops at a node cap, so on a large repo it draws what surrounds those hubs.
  If a language is **indexed and still absent** — every hub was Ruby, so the TypeScript half was
  never reached — stderr prints `WARNING: … is indexed but absent`. That warning is not optional
  reading: repeat it, or re-run with `PROVENLENS=0` for a whole-repo scan. On human-essentials the
  resolved graph is 400 nodes / 796 edges of Ruby; the static scan is 1578 nodes / 1084 edges
  across Ruby and JavaScript. Denser and truer, against wider. Say which one you gave them.
- `PROVENLENS=0 node references/build-map.cjs …` forces the regex analyzer, for a side-by-side
  comparison when you want to show what the index is buying.
- `provenlens hotspots` names the hubs for the summary; `provenlens cycles` names the circular
  dependencies. Both beat degree-counting on a regex graph.

## How to run it
1. **Pick the root.** Default = the current project (cwd). If the user named a sub-path/module,
   use that folder as the root (the analyzer scans the folder you point it at). Optional `mode`:
   `all` (default — files+classes+routes+KB), `files` (lighter, import graph only), `classes`,
   `routes`, `domain` (KB only).
2. **Run the bundled generator with Node** (Node ≥18; v20+ ideal). Resolve this skill's
   `references/` dir first (call it `$SKILL_DIR`): `${CLAUDE_PLUGIN_ROOT}/skills/cwk-map/references`
   if `CLAUDE_PLUGIN_ROOT` is set, else the `references/` folder next to this SKILL.md, else
   `$HOME/.claude/skills/cwk-map/references`:
   ```bash
   node "$SKILL_DIR/build-map.cjs" "<PROJECT_ROOT>" "" all
   ```
   - Arg 1 = project root (absolute path preferred). Arg 2 = `""` lets it default the output to
     `<root>/cwk-sessions/maps/<name>-<date>.html` (gitignored). Arg 3 = mode.
   - The script prints the **output HTML path on stdout** (stats on stderr). Capture it.
   - If `node` isn't found, tell the user Node.js is required for the interactive graph.
3. **Open the file** for the user:
   - macOS: `open "<path>"` · Linux: `xdg-open "<path>"` · Windows: `start "" "<path>"`.
4. **Give a short written summary** alongside the file: from the stderr stats (or by reading the
   generated graph) report node/edge counts, the **top hubs** (highest-degree nodes = biggest
   blast radius), the architecture layers present, and any obvious coupling concern. Tell the
   user that clicking a node in the viewer shows its "Used by / Depends on".

## What the viewer gives the user
- Zoom/pan; **click a node** → highlights neighbors + a details panel (file, type, layer,
  degree, used-by, depends-on, methods, fields); **double-click** → focus/zoom.
- **Search** box, **layer filter** (click legend rows to toggle), **Highlight hubs** button,
  **Fit** and **Re-layout**. Edges are directional; `extends` (red), `implements` (dashed),
  `injects` (green) are visually distinct.

## Notes
- Knowledge Base enrichment is automatic: in `all`/`domain` mode the analyzer also pulls
  `knowledge-base/*.md` as domain nodes, so the KB shows beside the code when present.
- Large repos: if a graph exceeds ~1800 nodes the generator auto-switches to `files` mode for
  readability; you can also pass `files` explicitly, or point it at a sub-module to drill in.
- **Offline by default when vendored.** If the repo has `vendor/cytoscape.min.js`, the generator
  **inlines** it so the HTML is fully self-contained — zero external network calls (enterprise /
  air-gapped safe). Without `vendor/`, it falls back to a Cytoscape CDN link (needs internet).
  Either way your graph data is embedded inline — no code leaves the machine.
- Output lives under `cwk-sessions/maps/` which is gitignored, so nothing lands in a commit.
- If the user instead wants a graph the AGENT can query (an agent-queryable index) rather than a human
  visual, that's a different tool — say so rather than forcing this viewer to do it.
