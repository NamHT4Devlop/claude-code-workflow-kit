# Knowledge Base — Section Specs (16 docs)

> Ported from Auto Spec extension's `KB_STEPS`. Each section becomes one file under
> `<repo>/knowledge-base/`. Every prompt is designed to reason about **business
> intent** from code, not just describe technical structure.
>
> **Golden rules for every section:**
> 1. ALWAYS cite real file paths + function/class/variable names as evidence.
> 2. NEVER write generic statements — if no evidence is found, write `(not found in codebase)`.
> 3. Analyze at BUSINESS DEPTH — explain *what user problem* each feature solves.
> 4. Priority of evidence: **test files > service layer > controller > model**.
> 5. Magic numbers → explain their business meaning.
> 6. Treat XML/`.properties`/YAML/SQL migrations as first-class business context.
> 7. **Every diagram is Mermaid**, in a fenced ```mermaid block — never ASCII art or prose-only.
>    Use the fitting type: `flowchart` for architecture/deployment, `sequenceDiagram` for a
>    request/auth journey, `erDiagram` for data, `stateDiagram-v2` for a lifecycle. Keep labels
>    short and real (actual service/module/table names). This keeps the KB renderable to
>    HTML/PDF and comparable across rescans.

> 8. **Structure claims come from the call graph where one exists.** With a `.codelens/` index
>    (Java · Ruby · TS/JS), `codelens hotspots` names the real hubs, `codelens cycles` the real
>    circular dependencies, `codelens dead` what nothing reaches, and `codelens explore <symbol>`
>    the real callers and callees. Use them for §06, §07, §10 and §16 rather than inferring
>    coupling from folder names or imports. Record the coverage figure in `_meta.yml` (below), and
>    when there is no index say the structural sections are grep-depth — a KB that overstates how
>    it knows something is worse than one that admits the limit.
>    **The graph is an input, never the output.** Do not paste `hotspots` into a KB page: a
>    fan-in number is not a business meaning, and the meaning is the whole point of these docs.

Sections **04, 05, 10, 13, 16** are the highest-value "deep analysis" docs — spend
the most effort there and, when possible, analyze them with parallel sub-agents
(service layer / tests+validators / models+schema) then synthesize.

---

## 01 — `01-project-structure.md` — Project Structure & Ownership Map
Analyze the project structure. Always cite actual paths.
1. **Project Type & Scale** — monolith / monorepo / microservices / hybrid? Evidence. How many deployable units (name + path)? What stage (MVP / scale-up / enterprise legacy)?
2. **Folder Structure with Business Meaning** — directory tree 2–3 levels; for each folder: technical function AND the business domain it represents.
3. **Dependency Direction** — which module depends on which (text diagram of coupling).
4. **Critical vs Supporting Code** — which dirs hold CORE business logic vs infra/utility.
5. **Technical Debt Indicators** — signs of tech debt visible from structure.

## 02 — `02-tech-stack.md` — Tech Stack & Architecture Decisions
1. **Stack Summary Table** — `| Layer | Technology | Version | Role |`.
2. **Architecture Decision Inferences** — for each important tech choice, WHY it was selected.
3. **Version Risks** — old/deprecated dependencies.
4. **Testing Stack** — framework, coverage, mocking (check package.json, pom.xml, build.gradle, Gemfile, go.mod, etc.).
5. **Build & Deploy Pipeline** — build tool, Dockerfile, CI/CD, scripts, plugin configs.

## 03 — `03-entry-points.md` — Entry Points & Runtime Behavior
1. **Application Startup Sequence** — from main file to "ready".
2. **All Entry Points** — every way external parties can trigger code.
3. **Environment Configuration** — all env vars, properties/yml, profiles, `.env`, config classes.
4. **Health & Observability** — health endpoints, actuator, metrics, tracing, logging config.
5. **Local Setup (step-by-step)** — prerequisites, DB, migrations, seed data, run commands.

## 04 — `04-business-domain.md` — Business Domain & User Stories ★DEEP
Answer as a Business Analyst reading the ENTIRE codebase.
1. **Product Brief**  2. **User Roles & Capabilities Matrix**  3. **Top 10 Core Features (ranked by business importance)**  4. **User Journey (main flow)**  5. **Business Constraints Evident in Code**.

## 05 — `05-domain-model.md` — Domain Model & Entity Lifecycle ★DEEP
Check ALL sources: JPA `@Entity`, Prisma schema, TypeORM, Django models, ActiveRecord, MyBatis mapper XML (resultMap/resultType), SQL `CREATE TABLE`, Proto messages.
1. **Entity Catalog**  2. **State Machines**  3. **Entity Relationships** (ORM + MyBatis XML joins)  4. **Aggregate Boundaries**  5. **Data Lifecycle**.

## 06 — `06-modules.md` — Module Map & Feature Boundaries
1. **Module Overview Table**  2. **Module Deep-Dive**  3. **Cross-Module Communication**  4. **Feature Flags / Toggles**  5. **Module Maturity Assessment**.
With an index: `codelens hotspots` ranks the modules most depended on (start the Deep-Dive there, not alphabetically), and `codelens cycles` turns "Cross-Module Communication" from a diagram of intent into a list of what actually happens.

## 07 — `07-architecture-diagram.md` — System Architecture & Data Flow
1. **High-Level Architecture Diagram** — a ```mermaid `flowchart` showing every deployable unit and
   the real edges between them: clients/entry points → services/modules → datastores → queues/topics
   → external systems, each labelled with the actual name and protocol (HTTP route prefix, SQS queue,
   DB engine). Group with `subgraph` per tier/service. This is the picture a newcomer reads first —
   keep it current whenever the topology changes.
2. **Request Journey (end-to-end)** — a `sequenceDiagram` for the main request.
3. **Async / Background Processing**  4. **External Service Integration**  5. **Failure Points & Resilience**.

## 08 — `08-database-schema.md` — Database Schema & Query Patterns
1. **Schema Overview** (JPA, Prisma, TypeORM, Django, ActiveRecord, SQL migrations, MyBatis resultMaps).
2. **Full ERD**  3. **Critical Business Columns**  4. **Index Strategy**  5. **Data Integrity & Constraints** (DB-level + ORM validation: `@NotNull/@Size`, Prisma `@unique`, Rails `validates`).
6. **Migration History** — Flyway `V*.sql`, Liquibase, Prisma, Rails `db/migrate`, Alembic — what business decision drove each change?

## 09 — `09-auth-security.md` — Auth, Security & Permission Model
1. **Authentication Mechanism**  2. **Authorization Model**  3. **Permission Matrix**  4. **Auth Flow Sequence Diagrams**  5. **Security Hardening**.

## 10 — `10-core-flows.md` — Core Business Flows (End-to-End) ★DEEP — MOST IMPORTANT
Identify and diagram **every flow a stakeholder would name** — the ones people say out loud in a
standup or a support ticket. There is **no upper limit**: a business-heavy system legitimately has
twenty, and a cap would silently drop the ones that matter to somebody. Practical handling:
- Fewer than ~8 → document them all here, in full.
- More than that → keep the **cross-cutting** ones here (the flows that span modules, move money,
  or change state other modules depend on) and put the module-local ones in `modules/<m>.md`,
  with a one-line index here pointing at each. Splitting is fine; **dropping is not**.
- If you deferred any flow for cost, **list it by name** in `_coverage-report.md` under
  *Flows not yet documented*. An undocumented flow the reader knows about is a gap; an
  undocumented flow nobody mentions is a landmine.

Give each flow a stable id — `CF-01`, `CF-02`, … — and **never renumber** them (see the id rule
under §13; `/namht-qa` and `/namht-build` cite these).

For each flow, trace through EVERY layer (entry → service → domain → data → response), with state
transitions and error/rollback paths.

## 11 — `11-api-docs.md` — API Reference
**API Overview** · **Endpoints by Module** · **Rate Limits & Special Behaviors**. List ALL endpoints.

## 12 — `12-conventions.md` — Coding Conventions & Patterns
Every rule MUST have a real code example.
1. Naming  2. Folder & File Organization  3. Architecture Layers & Rules  4. Error Handling Pattern  5. Async/Await Pattern  6. Testing Conventions  7. Logging Convention  8. "The Rules" — quick reference card.

## 13 — `13-business-rules.md` — Business Rules & Invariants ★DEEP — MOST IMPORTANT
Document ALL business rules implemented in code.
1. Validation Rules  2. Business State Rules (state-machine)  3. Business Calculation Rules  4. Access-Control Business Rules  5. Time-Based Rules  6. Business Invariants  7. **Under-Enforced Business Rules (Risk)**.

**Every rule gets a stable id — this is not optional.** `/namht-build`, `/namht-qa` and
`/namht-review` cite rules by id (`BR-V2`, `CF-03`) to tie a test or a finding to the rule it
protects. Without ids that traceability is prose, and a regression test cannot say what it defends.

- Format: `BR-<AREA><n>` where `<AREA>` is one letter per category — **V**alidation, **S**tate,
  **C**alculation, **A**ccess, **T**ime, **I**nvariant — e.g. `BR-V7`, `BR-S2`, `BR-A1`.
- **Append-only. Never renumber, never reuse a retired id.** Ids are cited from test names,
  evidence reports and journals that this scan cannot see; renumbering silently repoints every
  one of them. A rule that no longer exists is marked `[REMOVED <date>]` and kept in place.
- Each rule is one row:
  `| id | rule in one plain sentence | severity | where it is ENFORCED (file:line) | how it is tested (test name, or NONE) |`
- **`NONE` in the last column is a finding, not a blank.** Roll those up into §7
  (Under-Enforced) — an unenforced or untested business rule is the highest-value thing this
  whole document produces.
- State the rule in **business language first**, then the code that implements it. "Total must
  never exceed the credit limit" is the rule; `if (t > lim) throw` is the implementation.

## 14 — `14-integrations.md` — Integration Map & External Dependencies
1. **Integration Map** — all external systems (REST, SOAP, SQS/Kafka/RabbitMQ, AWS/GCP/Azure, payment, email/SMS, Elasticsearch, Redis).
2. **Integration Details** — protocol, auth, retry, circuit breaker, timeout, error handling.
3. **Internal Service Communication** — REST, gRPC, queues, Camel routes, event bus, shared DB.
4. **Event-Driven Integration** — Kafka topics, SQS queues, SNS, RabbitMQ exchanges, domain events — producers, consumers, schemas.
5. **Integration Risks & Single Points of Failure**.

## 15 — `15-error-scenarios.md` — Error Scenarios & Operational Runbook
1. Error Response Taxonomy  2. Critical Error Scenarios (business impact)  3. Data Consistency Risks  4. Graceful Degradation  5. Operational Runbook (common issues)  6. Logging & Observability.

## 16 — `16-architecture-patterns.md` — Architecture & Design Patterns ★DEEP — GUARDRAILS
Document the ACTUAL architecture so future changes follow it and DO NOT break the design. Cite real files/classes. A large repo often mixes MULTIPLE patterns — capture each + WHERE it applies.
1. **Architectural Style(s)** — Layered / Hexagonal / Clean / DDD / CQRS / Event-Driven / Pipeline (Camel) / MVC / Modular Monolith / Microservices — per module + evidence.
2. **Design Patterns Catalog** — every recurring pattern with a real example (file + class) and WHEN to use it here.
3. **Layer & Dependency Rules (allowed vs forbidden)** — make them explicit & enforceable; cite where honored.
4. **Module Boundaries & Communication** — how modules talk (call / port / event / queue / shared DB); what crossing is allowed.
5. **Extension Recipes** — "Add a REST endpoint", "Add an entity + persistence", "Add an async consumer" — step-by-step, citing an existing example to copy.
6. **Architecture Invariants — DO NOT BREAK** — a numbered checklist of hard rules new code MUST satisfy (layering, naming, transaction boundaries, where validation lives, idempotency for consumers…). Mark `[CRITICAL]`/`[MAJOR]`. **This list is used to review every generated change.**
   **Prefer invariants that can be checked.** "Nothing may bypass `X`" is verifiable when `X` is a named symbol — `codelens callers X` and `codelens path <caller> <forbidden target>` settle it in one command — whereas "keep the layers clean" can only ever be argued about. Where an invariant rests on an edge the index cannot resolve, say so in the rule itself.

---

## 17 — `17-async-events.md` — Event / Contract Catalog (only if the service uses messaging)
The language-agnostic surface `/namht-system-map`, `/namht-qa` and `/namht-build` use for
**cross-service** impact — publisher→consumer is matched by exact channel name, so this table is what
answers "if I change this message, who breaks?". One row per channel:
`channel (queue/topic/event) · role (produce/consume) · message schema · trigger · FIFO? · DLQ? ·
idempotency key`, plus Camel routes and outbound HTTP/gRPC targets. Record the **field names**
verbatim — a producer sending `order_id` to a consumer reading `orderId` is invisible until the two
catalogs are put side by side.

## Auxiliary outputs (also written by Scan)
- `review-skills.md` — the universal review checklist (see `review-skills-universal.md`) with a **Section 14 — Project-Specific Rules** appended (naming, mandatory patterns, banned anti-patterns, business rules every new feature must respect — each with a code citation).
- `modules/<module>.md` + `modules/_index.md` — deep per-module docs for large projects (exhaustive flows + rules + entities + API + dependencies).
- `_coverage-report.md` — which files were analyzed vs covered by global scan only. Where an index exists, also record `codelens status` and anything `codelens doctor` flags as blocking: low coverage caused by an uninstalled dependency and low coverage caused by a resolver limit look identical in the number and are nothing alike for whoever reads this KB next.
- `_meta.yml` — **the KB's identity.** The folder is called `knowledge-base/` in every repo, which is
  fine inside one repo and useless the moment KBs from several projects sit side by side. This file is
  how a KB says which project it belongs to and how old it is. Write it every scan/rescan:
  ```yaml
  project: taskflow              # the repo/product name a human uses
  repo: git@github.com:acme/taskflow.git   # origin, or "(no remote)"
  branch: main
  commit: 9f2c1ab                # HEAD at scan time — the KB describes THIS revision
  generated: 2026-08-13
  generator: namht-scan
  depth: standard                # quick | standard | deep
  modules: [auth, orders, billing]         # the modules/ docs present
  files_analyzed: 412
  codelens: 93.4%                # in-repo resolution at scan time, or "none" if unindexed
  ```
  `codelens` records how much of the call graph was resolved when this KB was written
  (`codelens status`), or `none`. It is the honesty column: a reader comparing two KBs needs to
  know that one was built on a resolved graph and the other on grep. Omit the key rather than
  guess a number.
  Get `repo`/`branch`/`commit` from git (`git config --get remote.origin.url`, `git branch --show-current`,
  `git rev-parse --short HEAD`); if the folder is not a git repo, say so rather than inventing values.
  `project` defaults to the repo folder name — ask the user if that name is meaningless (`src`, `app`).
  Also put a one-line stamp at the top of `00-*`/`01-*`: `> KB for **<project>** · branch `<branch>` ·
  commit `<commit>` · generated <date>` so a printed or pasted page still says where it came from.
