---
description: Generate an interactive HTML code graph (Cytoscape) — files/classes/edges, zoom/click/filter; opens in browser
argument-hint: "[optional: sub-path / module to focus]"
---

Use the **cwk-map** skill to generate an **interactive HTML dependency graph** of the
codebase: run the bundled analyzer (`references/build-map.cjs` via Node) to extract files/
classes/routes and real edges (imports, DI, extends/implements, calls), write a self-contained
Cytoscape viewer to `cwk-sessions/maps/`, and open it in the browser. Then give a short
written summary (node/edge counts, top hubs = blast radius, layers). NOT a Mermaid dump.

Scope (optional sub-path/module to map instead of the whole repo): $ARGUMENTS
