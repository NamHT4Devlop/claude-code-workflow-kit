---
description: Map a microservices workspace end-to-end — cross-service dependency graph + business flows that span services (run at the workspace root)
argument-hint: "[optional: focus flow/service, e.g. checkout]"
---

Use the **cwk-system-map** skill to build a SYSTEM-level map of the microservices in this
workspace folder: discover the service repos, stitch each one's exposed endpoints (KB
`11-api-docs`) to others' outbound calls (KB `14-integrations`) into a cross-service dependency
graph, trace **end-to-end business flows** that span services (sequence diagrams), and catalog
shared events/contracts + risks. Write to `<workspace>/system-map/` (dual-audience) and render
the graph + flows to HTML. Run this at the **workspace root** (parent of the service repos);
each service should ideally have a KB already (`/cwk-scan`).

Optional focus (a specific flow or service to center on): $ARGUMENTS

If the current folder is a **KB hub** (`projects/<name>/knowledge-base/`, produced by
`scripts/kb-export.sh`) rather than a workspace of checked-out repos, build the map from those KBs —
and say plainly in the output that edges could not be confirmed against source and that each
project is a snapshot at the commit in its `_meta.yml`, listing those dates.
