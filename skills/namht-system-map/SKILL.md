---
name: namht-system-map
description: >-
  Build a SYSTEM-LEVEL map across multiple microservice repos in one workspace
  folder: discover the services, stitch each service's exposed endpoints (KB
  11-api-docs) to the others' outbound calls (KB 14-integrations) into a
  cross-service dependency graph, trace END-TO-END business flows that span
  services (with sequence diagrams), and catalog shared events/contracts + risks.
  Use when the user asks to "/system-map", "map the microservices", "end-to-end
  flow across services", "how do the services call each other", or works in a
  folder containing several service repos that call each other.
---

# namht-system-map — cross-service / end-to-end map for a microservices workspace

Per-service `/namht-scan` (KB) understands each service **internally**. This skill adds the
**second layer**: how the services connect (HTTP/gRPC/queues/events) and the **end-to-end business
flows** that span them. It works for a **multi-repo workspace** — a parent folder containing N
service repos in possibly different languages.

## Two possible sources — check which one you are standing in
1. **A workspace of checked-out repos** (the normal case) — a parent folder containing the service
   repos. Full fidelity: you can read the KBs *and* confirm edges in real source.
2. **A KB hub** (`scripts/kb-export.sh` output) — a folder with `projects/<name>/knowledge-base/`
   and no source code. Everything this skill actually consumes (`11-api-docs`, `14-integrations`,
   `17-async-events`) is in there, so the map builds fine — with two honest limits you must state in
   the output: you **cannot confirm an edge by reading code**, and each project is a **snapshot** at
   the commit in its `_meta.yml`, so the map is as old as the oldest export. Print that table of
   project/commit/exported dates at the top and flag anything older than ~30 days.
   Detect this case by the `projects/*/knowledge-base/` layout; treat each project folder as a service.

This is what makes the hub useful to someone who is not a developer: a PM, an architect or a new
joiner can produce the cross-service map from the hub alone, without cloning a single repo.

## Inputs & setup
- **Run at the workspace root** (the parent folder that contains the service repos), **or at a KB
  hub root** (see above).
- **Discover services:** each immediate sub-folder that is a git repo or has a manifest
  (`package.json`, `pom.xml`/`build.gradle`, `go.mod`, `Gemfile`, `requirements.txt`,
  `*.csproj`, `Cargo.toml`) and/or a `knowledge-base/`. List them with detected language + role.
- **Precondition (strongly recommended):** each service should already have a Knowledge Base
  (`cd <svc> && /namht-scan`). If some don't, list them and offer to scan them first — the system
  map is far more accurate from per-service KBs. You can still proceed by reading source for
  un-scanned services, at lower fidelity (say so).
- **Confirm edges by reading code:** when a service's KB is thin, read its HTTP-client calls /
  endpoint handlers / queue producers-consumers directly to confirm the real cross-service edges.

### codelens (optional)
`.codelens/` present → prefer `codelens` over grep for anything about **who calls what**: it resolves
through DI, interfaces, mixins and framework string-bindings (MyBatis · Camel · SQS · Flyway) and
scores every edge. Confirm once with `codelens status`. No index, no `codelens` command, or a
language it does not cover (**Java · Ruby · TS/JS** only) → fall back to Grep/Glob and write
`⚠️ grep-depth only (no codelens index)` in the output. A grep hit is never a resolved call — do not
report it as one. Playbook: `docs/codelens.md`.

**Here:**
- Index each service once (`cd <svc> && codelens init .`), then query from the **workspace root** —
  `codelens serve` and the MCP server both accept a folder of checkouts and answer across all of them.
- Cross-service edges stop being inferred. A producer and a consumer sharing a queue name or an
  endpoint URI are linked by the binding layer, **across languages** (a Java publisher to a Ruby
  worker). Mark those edges **confirmed**; keep "inferred" for the ones only KB prose supports.
- `codelens path <symbol in A> <symbol in B>` walks a chain that crosses the repo boundary — that is
  an end-to-end flow proven, and it is what the sequence diagram should be drawn from.
- Services you could not index (unsupported language, no checkout) must be named in the output. A
  map that silently omits a service is worse than one that admits a hole.

## What to build
For each service, read its KB: `11-api-docs.md` (endpoints it **exposes**), `14-integrations.md`
(systems/services/queues it **calls out to**), `17-async-events.md` (its Event/Contract Catalog),
`03-entry-points.md`, `06-modules.md`, plus `10-core-flows.md` (its internal flows). Then:

1. **Service inventory** — name, language/stack, role, base URL/route prefix, exposed surface.
2. **Cross-service dependency graph** — match each service's **outbound** targets (base URLs,
   service names, gRPC services, Kafka/SQS topics, event names) to the **inbound** side of other
   services (their endpoints / consumers). Edge = caller → callee, labelled with protocol
   (REST/gRPC/queue/event) and the operation. Flag edges you inferred vs. confirmed in code.
3. **End-to-end business flows (3–7 key ones)** — trace a user/system action from its **entry
   service** through every downstream hop to completion. For each: a Mermaid `sequenceDiagram`
   (participant per service), the trigger, each hop (service · endpoint/handler · protocol),
   state changes, and failure/compensation paths. Cite the file/endpoint in each service.
4. **Event/Contract Catalog** — the cross-service backbone. Build one table from every service's
   `17-async-events.md` + `14-integrations.md`, one row per channel:
   `channel (queue/topic/event) · publisher · consumer(s) · message schema · owner · FIFO? · DLQ? · idempotent?`.
   Also catalog REST/gRPC contracts at boundaries. Match **publisher→consumer by exact channel name** — this
   is the authoritative answer to "if I change this message, who breaks?".
5. **Risks (async-first)** — for each event edge: **at-least-once duplicates** without consumer
   idempotency, **missing DLQ / poison-message** handling, **ordering** assumptions on standard (non-FIFO)
   queues, **contract/version skew** between producer and consumer, fan-out **cascade/back-pressure**, no
   retry/visibility tuning. For sync edges: long synchronous chains (latency/cascade), no
   circuit-breaker/timeout, chatty calls, single points of failure, auth between services, shared-DB coupling.

## Output (write to `<workspace>/system-map/`)
Dual-audience (plain summary + technical detail), each file Markdown:
- `_index.md` — links + last-updated + service list.
- `00-system-overview.md` — **In plain words** (what the system does, who the services are) +
  the inventory table.
- `01-service-dependency-graph.md` — a Mermaid `flowchart` (nodes = services, edges = calls,
  grouped by layer: edge/gateway → core → data/async); written analysis of hubs, cycles,
  sync-coupling hot-spots.
- `02-end-to-end-flows.md` — the cross-service flows with sequence diagrams.
- `03-contracts-events.md` — contracts/events tables + risks.

Then **render `01` and `02` to HTML** (diagrams drawn) with the bundled renderer and open them.
Resolve this skill's `references/` dir first (call it `$SKILL_DIR`): `${CLAUDE_PLUGIN_ROOT}/skills/namht-system-map/references`
if `CLAUDE_PLUGIN_ROOT` is set, else the `references/` folder next to this SKILL.md, else `$HOME/.claude/skills/namht-system-map/references`.
```bash
node "$SKILL_DIR/render-html.cjs" \
  "<workspace>/system-map/02-end-to-end-flows.md" "<workspace>/system-map/02-end-to-end-flows.html" "End-to-end flows"
# then: open / xdg-open / start  the printed path
```

## Notes
- `system-map/` is a workspace-level artifact (the parent folder usually isn't a git repo). It's
  also covered by the global gitignore (`system-map/`) so it never lands in a service repo.
- **Keep it fresh:** after a service changes its API/integrations, `/namht-rescan` that service,
  then re-run `/namht-system-map` (or just re-derive the affected flow).
- Polyglot is fine — the map works off **contracts/events** (language-agnostic), not code imports;
  each service's own KB handled its language.
- This is a *map*, not a deploy/runtime tool — it documents the system from code+KB; confirm
  uncertain edges with the team or by reading the actual client/handler.
