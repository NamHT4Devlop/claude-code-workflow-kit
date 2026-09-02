# Universal Review Skills
# ══════════════════════════════════════════════════════════════════
# Author: Principal Software Engineer × Principal AI Engineer
# Version: 2.0 — Language-agnostic
#
# Usage:
#   Copy this file into your project's knowledge-base/review-skills.md.
#   The namht Kit injects it into /namht-review, /namht-build and /namht-pr.
#   For pure backend/frontend projects: remove Section 8 (AI Engineering).
#   For projects with AI components: keep all sections.
#
# Severity:
#   [CRITICAL] — Block merge. Must fix before shipping.
#   [MAJOR]    — Fix in this sprint; do not merge if risk is high.
#   [MINOR]    — Fix in a follow-up task, or include in this PR.
#   [NIT]      — Optional — style preference, does not block.
# ══════════════════════════════════════════════════════════════════

---

## 0. EVIDENCE — what a finding has to rest on

A review is only worth the evidence under it. Most of the checks below are claims about
**reach**: who calls this, what breaks if it changes, whether a test covers it. Read off a file,
those are guesses; read off a call graph, they are facts. The difference decides whether a
`[CRITICAL]` is real.

**Where a `.codelens/` index exists, use it** (Java · Ruby · TS/JS only):

| The claim you are about to make | What settles it |
|---|---|
| "this is called from N places" | `codelens callers <symbol> --json` — a grep hit count is not a caller count |
| "changing this breaks X" | `codelens impact <symbol>` — transitive, through DI, interfaces and mixins |
| "nothing tests this" | `git diff --name-only \| codelens affected` — it names the tests that do |
| "this layer reaches into that one" | `codelens path <from> <to>` — a real chain, or none |
| "this is unused / can be deleted" | `codelens dead` — already filtered against templates and config |
| "this is the hot path" | `codelens hotspots` — fan-in, not intuition |

Two rules, and they matter more than the table:

- **Check the index before trusting it.** `codelens status` once; `codelens sync` if the working
  tree moved since it was built. A stale index is worse than none because it looks authoritative.
  If coverage reads low, `codelens doctor` says whether that is a resolver limit or just an
  uninstalled dependency — those look identical in the number and are nothing alike in the fix.
- **Degrade out loud.** No index, no `codelens`, or a language it does not cover → Grep/Glob, and
  mark the finding `⚠️ grep-depth only (no codelens index)`. Never state a grep hit as a resolved
  call. And **absence of a path is not proof of safety**: reflection, dynamic dispatch and
  string-built calls are exactly what a graph misses.

When a finding rests on an edge below `direct`, quote its confidence. A 0.4 `unique-name` link is
a lead to check, not a verdict to file.

---

## 1. ARCHITECTURE & DESIGN

> *"Good architecture makes wrong things hard, right things easy."*
> — Principal SE Principle

### 1.1 Separation of Concerns (SoC)
- [CRITICAL] Business logic MUST NOT reside in the transport layer (Controller, Handler, Route, View).
- [CRITICAL] Infrastructure concerns (DB, HTTP client, file I/O, message queue) MUST NOT reside in the domain/service layer — they must go through an interface/port/abstraction.
- [MAJOR] A component must not know the implementation details of another component — it may only know the contract (interface).

> **Proving a violation (§0).** A layering breach is a resolved edge, not an import line:
> `codelens explore <symbol>` shows what it really calls, `codelens path <ui> <infra>` shows whether
> the forbidden chain exists, and `codelens cycles` lists the files that depend on each other the
> long way round. Report a crossing you proved; label one you inferred.

### 1.2 Dependency Direction (Clean / Hexagonal Architecture)
```
UI / API  →  Application Service  →  Domain  ←  Infrastructure
                                              (port ← adapter)
```
- [CRITICAL] Dependencies must only point inward (toward Domain). Infrastructure MUST NOT import Domain implementations — it only implements interfaces defined by the Domain.
- [MAJOR] No circular dependencies between modules / packages.
- [MAJOR] Framework-specific annotations must not leak into the Domain layer (e.g., `@Entity`, `@Column` ORM annotations should not appear in pure domain objects in a Clean Architecture project).

### 1.3 Single Responsibility & Cohesion
- [MAJOR] A class/module must have exactly one reason to change (SRP).
- [MAJOR] A function must do exactly one thing — its name must accurately reflect what it does. If you need "and" to describe the function name → split it.
- [MINOR] Files should not exceed **300 lines**. Functions/methods should not exceed **50 lines**. If exceeded → look for extraction opportunities.

### 1.4 Open/Closed & Extensibility
- [MAJOR] Adding a new feature should not require modifying existing code — use strategy, plugin, or configuration instead of if/else chains or switch-case branching by type.
- [MAJOR] Enums / string literals must not be scattered across the codebase — there must be a single source of truth.

### 1.5 Interface Segregation & Dependency Inversion
- [MAJOR] Interfaces must not be "fat" — callers should only depend on the methods they actually use.
- [CRITICAL] Dependencies must be injectable (constructor injection preferred over service locator) — this is a prerequisite for unit testability.

---

## 2. SECURITY

> *"Security is not a feature — it is a foundational property."*

### 2.1 Input Validation (all languages)
- [CRITICAL] All input from external sources (HTTP, gRPC, message queue, file upload, CLI args, env vars) MUST be validated before processing.
- [CRITICAL] Validate at the **boundary** (outermost layer) — do not rely on downstream validation.
- [CRITICAL] Whitelist validation (allow only what is known to be valid) > Blacklist validation (block only what is known to be bad).

### 2.2 Injection Prevention
- [CRITICAL] **SQL Injection**: NEVER use string concatenation to build queries. Use parameterized queries / prepared statements / ORM.
  ```
  # BAD  (any language)
  query = "SELECT * FROM users WHERE id = " + userId

  # GOOD
  query = "SELECT * FROM users WHERE id = $1", [userId]
  ```
- [CRITICAL] **Command Injection**: Do not pass user input to shell commands. If unavoidable, escape properly and sandbox the process.
- [CRITICAL] **XSS**: Escape output when rendering HTML. Use Content-Security-Policy headers.
- [CRITICAL] **Path Traversal**: Sanitize file paths — do not allow `../` in user-supplied paths.

### 2.3 Authentication & Authorization
- [CRITICAL] Authorization checks MUST be placed at the start of a function/handler — do not let logic execute before the permission check.
- [CRITICAL] Do not expose internal IDs (sequential integers) in the API — use UUID or opaque tokens.
- [CRITICAL] Tokens / sessions must have expiry. Refresh tokens must have rotation.
- [MAJOR] Every endpoint MUST clearly document: is auth required? What role/permission is needed?
- [MAJOR] Do not hardcode JWT secrets in code. Load from environment variables / secret manager.

### 2.4 Sensitive Data
- [CRITICAL] NEVER LOG: passwords, tokens, secret keys, credit card numbers, PII (email, phone, national ID), session IDs.
- [CRITICAL] Passwords must be hashed with bcrypt / argon2 / scrypt (not MD5, SHA-1, or plain SHA-256).
- [CRITICAL] Sensitive config (API keys, DB credentials) MUST be read from env vars / secret manager — never hardcode, never commit to git.
- [MAJOR] PII stored in the database must be encrypted at rest. Logs must mask PII.

### 2.5 Error Responses
- [CRITICAL] Stack traces MUST NOT be exposed in production responses.
- [MAJOR] Error messages returned to clients must not leak internal system information (table names, column names, internal paths).
- [MAJOR] Authentication errors: use the same message and response time for "user does not exist" and "wrong password" (prevents user enumeration attacks).

### 2.6 Dependency Security
- [MAJOR] Dependencies MUST have pinned versions (package-lock.json, poetry.lock, go.sum, etc.).
- [MAJOR] Run a dependency audit before merging (`npm audit`, `safety check`, `govulncheck`, etc.).
- [MINOR] Do not pull in a dependency just to do something simple that can be implemented safely inline (reduces attack surface).

---

## 3. ERROR HANDLING & RESILIENCE

> *"Failure is inevitable. Graceful degradation is a choice."*

### 3.1 Error Handling Hierarchy
```
Infrastructure Error  →  wrap into  →  Domain Exception  →  map into  →  API Error Response
(DB connection fail)                   (RepositoryException)             (503 Service Unavailable)
```
- [CRITICAL] Do not let raw infrastructure errors (DB errors, HTTP timeouts) bubble up into API responses.
- [CRITICAL] No **empty catch blocks** — if an error is intentionally ignored, there must be a comment explaining why.
- [MAJOR] Custom exceptions must have clear semantic meaning (NotFoundException, ValidationException, ConflictException) — do not throw a generic Error/Exception for every case.
- [MAJOR] Log the error **before** throwing/re-throwing, with enough context to debug (requestId, userId, input summary).

### 3.2 Async & Concurrent Error Handling
- [CRITICAL] Every async operation must have an error handler — no "floating promises" (Promises that are not awaited or have no `.catch()`).
- [MAJOR] Race conditions: if multiple async operations modify shared state, a synchronization mechanism must exist.
- [MAJOR] Deadlock risk: if acquiring multiple locks, always acquire them in the same order.

### 3.3 External Service Resilience
- [MAJOR] Calls to external HTTP/RPC services MUST have a timeout. Do not use the default infinite timeout.
- [MAJOR] Retry logic MUST use exponential backoff with jitter. Do not retry immediately.
- [MAJOR] Idempotency: write operations that may be retried must be idempotent (use an idempotency key or upsert pattern).
- [MINOR] Circuit breaker pattern for services with low SLA or non-critical paths.

### 3.4 Partial Failure
- [MAJOR] When a batch operation has one item fail, the behavior must be explicitly defined: fail-fast, skip-and-continue, or rollback-all?
- [MAJOR] Saga / compensating transactions for distributed transactions — do not use 2PC.

---

## 4. PERFORMANCE & SCALABILITY

### 4.1 Algorithmic Complexity
- [CRITICAL] Nested loops on large datasets: O(n²) or worse with n > 1000 requires justification or must be optimized.
- [MAJOR] Do not sort/filter in memory when the database can do it more efficiently.
- [MAJOR] Pagination MUST be present on every list endpoint. Do not return unbounded lists.

> **N+1 is a graph fact, not a text pattern (§0).** `codelens callers <query method>` answers the
> only question that matters — is it reached from inside a loop — and `codelens path <controller>
> <repository>` shows the full chain behind a slow endpoint, which is where an N+1 hides between
> two layers that each look innocent.

### 4.2 Database Query Optimization
- [CRITICAL] **N+1 queries**: Do not query inside a loop. Use JOIN, eager loading, or batch fetch.
  ```
  # BAD
  for order in orders:
      user = db.find(order.userId)  # N queries

  # GOOD
  users = db.findByIds(orders.map(o => o.userId))  # 1 query
  ```
- [CRITICAL] `SELECT *` is forbidden in production code — only select the fields you need.
- [MAJOR] Foreign key columns and columns frequently used in WHERE/JOIN MUST have an index.
- [MAJOR] Slow queries: run EXPLAIN/ANALYZE before merging if the table is large (> 100k rows).
- [MAJOR] Write operations must acquire the minimum lock scope possible — avoid table-level locks.

### 4.3 Caching
- [MAJOR] Cache invalidation strategy MUST be defined — do not cache indefinitely.
- [MAJOR] Cache stampede (thundering herd): use probabilistic early expiration or lock-based refresh.
- [MAJOR] Do not cache sensitive data without encryption.
- [MINOR] Cache hit rate must be monitored — a cache without metrics is a useless cache.

### 4.4 Resource Management
- [CRITICAL] File handles, DB connections, and network sockets MUST be closed after use — use try-finally, `with` statements, `defer`, `using`, or the resource management pattern of the language.
- [MAJOR] Connection pool size must be configured — do not use the default unlimited setting.
- [MAJOR] Memory leaks: objects that are no longer needed must be released — particularly event listeners, timers, and subscriptions.

---

## 5. OBSERVABILITY

> *"Code you cannot debug in production is unfinished code."*

### 5.1 Structured Logging
- [CRITICAL] Use structured logging (JSON) — do not use raw `print()` / `console.log()` strings in production code.
- [CRITICAL] Every log entry MUST include: `timestamp`, `level`, `correlationId/requestId`, `service`, `message`.
- [MAJOR] Log levels:
  - `ERROR`: Exception / failure requiring human action
  - `WARN`: Business rule violation, degraded behavior, approaching a limit
  - `INFO`: Important business events (user login, order created, payment processed)
  - `DEBUG`: Developer detail — MUST be disabled in production
- [MAJOR] Do NOT log inside a loop — use an aggregated log after the loop completes.
- [CRITICAL] Do NOT log sensitive data (see Section 2.4).

### 5.2 Distributed Tracing
- [MAJOR] CorrelationId / TraceId MUST be propagated throughout the entire service call chain.
- [MAJOR] Every external call (HTTP, DB, queue) must be instrumented with a span.
- [MINOR] Custom span attributes to annotate business context (userId, orderId, etc.).

### 5.3 Metrics & Alerting
- [MAJOR] Business metrics must be exposed: request count, error rate, latency (p50/p95/p99), queue depth.
- [MAJOR] Health check endpoints MUST verify actual dependencies (DB, cache, external services) — not just return 200 OK.
- [MINOR] SLI/SLO must be defined for critical paths.

### 5.4 Audit Trail
- [MAJOR] Every write operation on sensitive data (user accounts, payments, permissions) MUST have an audit log: who, what, when, previous_value → new_value.
- [MAJOR] Audit logs MUST NOT be deleted (append-only).

---

## 6. TESTING

> *"Tests don't prove code is correct. Tests reveal where code is wrong."*

> **"Untested" is checkable (§0).** `git diff --name-only | codelens affected --fail-if-untested`
> lists the tests that already reach the change, and exits **2** when production code changed and
> none do. Treat that exit as a `[CRITICAL]`, not a note. The same output is the regression set:
> one case per consumer it names.

### 6.1 Test Pyramid
```
         /\
        /E2E\       ← fewest, slowest, most expensive
       /──────\
      /Integration\  ← moderate
     /────────────\
    /  Unit Tests  \  ← most, fastest, cheapest
   ────────────────
```
- [MAJOR] Unit tests must cover: happy path, error cases, boundary values, edge cases.
- [MAJOR] Every public function/method MUST have at least 1 test.
- [MAJOR] Integration tests MUST test actual behavior (real DB, real HTTP) — do not over-mock.

### 6.2 Test Quality
- [CRITICAL] Tests must be INDEPENDENT — must not depend on execution order, must not share state between test cases.
- [CRITICAL] Tests must be DETERMINISTIC — same input must always produce the same result. Do not use random/time values directly — inject a clock/random provider.
- [MAJOR] Test descriptions MUST follow the pattern: `"should [expected behavior] when [condition]"`.
  - BAD: `test_user_login`
  - GOOD: `should return 401 when password is incorrect`
- [MAJOR] Each test should assert exactly ONE behavior — do not pack multiple unrelated assertions into a single test.
- [MAJOR] Tests must not contain business logic (if/else, loops) inside assertions — if they do, that is a test smell.

### 6.3 Test Coverage (outcome, not goal)
- [MAJOR] **Statement coverage ≥ 80%** for production code.
- [MAJOR] **Branch coverage**: Every if/else path must be covered.
- [MAJOR] **Mutation coverage**: If deleting a line of code still passes all tests → that test has no value.
- [MINOR] 100% coverage does not mean 100% correct — test BEHAVIOR, not implementation.

### 6.4 Test Design Patterns
- [MAJOR] Arrange–Act–Assert (AAA) pattern for all unit tests.
- [MAJOR] Mocks/Stubs should only mock dependencies at the **boundary** (external services, DB, file system) — do not mock internal collaborators.
- [MINOR] Test Factory / Object Mother pattern for complex test data — do not hardcode many literals in tests.
- [MINOR] Contract testing for service-to-service integration (Pact, Spring Cloud Contract, etc.).

---

## 7. DATA INTEGRITY & DATABASE

### 7.1 Transaction Boundaries
- [CRITICAL] Every operation involving multiple writes MUST be wrapped in a transaction.
- [CRITICAL] A transaction MUST NOT span an HTTP call or a message queue publish — this is an anti-pattern.
- [MAJOR] Keep transaction scope minimal — do not hold a transaction open longer than necessary.

### 7.2 Schema Design
- [MAJOR] Every table MUST have: primary key, `created_at`, `updated_at`.
- [MAJOR] Soft delete (`deleted_at`) vs. hard delete: must be an explicit, intentional decision — not a default.
- [MAJOR] Do not store JSON blobs for "flexibility" when you actually need to query into those fields — properly serialize to columns.
- [MAJOR] Enum values in the DB: use string enums instead of integers (easier to debug, easier to migrate).

### 7.3 Migration Safety
- [CRITICAL] Migrations MUST have a rollback (down migration).
- [CRITICAL] Do not drop a column/table in the same migration as the code deployment — always allow a transition period (deploy backward-compatible code first, then drop in a later sprint).
- [MAJOR] Adding a NOT NULL column must either have a DEFAULT value, or be added as nullable first, backfilled, then altered to NOT NULL.
- [MAJOR] Index creation on large tables must use CONCURRENTLY (PostgreSQL) or equivalent — do not lock the table.

### 7.4 Data Validation Layers
```
External Input  →  [Validator]  →  Application  →  [Domain Invariant]  →  [DB Constraint]
```
- [MAJOR] All 3 layers must exist — do not rely solely on DB constraints or solely on application validation.
- [MAJOR] Domain invariants must be enforced in the domain object constructor / factory — do not let an object exist in an invalid state.

---

## 8. AI / LLM ENGINEERING

> *Applies when the codebase has a component that calls an LLM or AI service.*

### 8.1 Prompt Design Quality
- [CRITICAL] Prompts MUST be version-controlled — do not hardcode long strings in code; store them in dedicated prompt files/templates.
- [MAJOR] System prompt and user prompt must be clearly separated.
- [MAJOR] Prompts must include an explicit output format instruction — do not let the model decide the format when code needs to parse the output.
- [MAJOR] Few-shot examples in prompts must cover edge cases, not only the happy path.
- [MINOR] Prompts must include a fallback instruction: "If you don't have enough information, say 'I don't know' instead of guessing."

### 8.2 AI Security (AI-specific OWASP)
- [CRITICAL] **Prompt Injection**: Do not interpolate user input directly into the system prompt.
  ```
  # BAD
  systemPrompt = f"You are a helpful assistant. User context: {userInput}"

  # GOOD — separate user content into the user turn
  messages = [
      {"role": "system", "content": systemPrompt},
      {"role": "user",   "content": userInput}
  ]
  ```
- [CRITICAL] **Data Exfiltration**: Do not include sensitive data (PII, secrets) in prompts unless strictly necessary.
- [MAJOR] **Indirect Prompt Injection**: Sanitize content from external sources (web scraping, user documents) before including it in context.
- [MAJOR] **Jailbreak Defense**: Validate AI output before executing it if the output is used to trigger an action (function calling, code execution).

### 8.3 Model Boundary Isolation
- [CRITICAL] AI calls MUST go through an abstraction layer (AIClient interface / port) — do not call OpenAI/Anthropic/Copilot SDKs directly from business logic.
- [MAJOR] Response parsing logic MUST handle malformed / unexpected AI output gracefully — model output format is never guaranteed.
- [MAJOR] AI components MUST have a fallback when the model is unavailable (circuit breaker, graceful degradation).

### 8.4 Determinism & Reproducibility
- [MAJOR] For reproducible output: pin the model version, set `temperature=0`, log prompt and response for debugging.
- [MAJOR] Non-deterministic AI output must not be used for operations that require an audit trail — log both the prompt and the response.
- [MINOR] A/B test prompt changes — never change a prompt without having comparison metrics.

### 8.5 Cost & Latency Optimization
- [MAJOR] Token budget must be defined and enforced — truncate context if necessary, by priority.
- [MAJOR] Cache AI responses for deterministic inputs (same prompt + same context → cache hit).
- [MAJOR] Stream responses when the UX requires it — do not buffer the entire response before displaying.
- [MINOR] Batch requests where possible instead of many serial calls.

### 8.6 RAG (Retrieval Augmented Generation)
- [MAJOR] Retrieval relevance must be measured — do not assume vector search always returns the correct results.
- [MAJOR] Grounding check: AI responses must cite sources and must not hallucinate facts outside the retrieved context.
- [MINOR] Chunk strategy must match the query pattern — chunks that are too large or too small both degrade quality.

### 8.7 Evaluation & Quality Gates
- [MAJOR] Every AI feature MUST have an eval set before shipping — do not merge an AI change without a baseline comparison.
- [MAJOR] Regression detection: if a prompt or model changes, run the eval suite and compare scores.
- [MINOR] Human-in-the-loop for high-stakes AI decisions (financial, medical, legal).

---

## 9. CODE QUALITY

> **Dead code and duplication (§0).** `codelens dead` is the delete list — it already excludes
> names that appear in templates and config, so a getter an `.erb` page renders is not on it.
> Before proposing a rename or an extraction, `codelens impact <symbol>` is the set that
> "behaviour unchanged" is measured against. Never file a deletion on zero grep hits alone.

### 9.1 Naming (all languages)
- [MAJOR] Names must be **self-documenting** — reading the name should immediately convey intent, without needing a comment to explain *what*.
  - BAD: `d`, `temp`, `data`, `result`, `flag`, `process()`
  - GOOD: `invoiceDueDate`, `pendingOrders`, `calculateShippingCost()`
- [MAJOR] Boolean variables/functions MUST use predicate form: `isActive`, `hasPermission`, `canRetry`.
- [MAJOR] Do not use uncommon abbreviations (`usrNm` → `username`, `calcTx` → `calculateTax`).
- [MINOR] Do not include the type in a variable name (`userList` → `users`, `nameString` → `name`).

### 9.2 Magic Values
- [MAJOR] Do not use magic numbers/strings — extract to a named constant or enum.
  ```
  # BAD
  if attempts > 3: ...
  status = "PENDING"

  # GOOD
  MAX_RETRY_ATTEMPTS = 3
  if attempts > MAX_RETRY_ATTEMPTS: ...
  class OrderStatus(Enum): PENDING = "PENDING"
  ```

### 9.3 Cognitive Complexity
- [MAJOR] Cyclomatic complexity ≤ 10 per function. If exceeded → extract method or use strategy pattern.
- [MAJOR] Nesting depth ≤ 3. More than 3 levels → use guard clauses / early return / extract function.
  ```
  # BAD — deep nesting
  if user:
      if user.isActive:
          if order:
              ...

  # GOOD — guard clause
  if not user: raise NotFoundException
  if not user.isActive: raise ForbiddenException
  if not order: raise NotFoundException
  ...
  ```
- [MINOR] Complex boolean expressions → extract to a named variable/function to make them self-documenting.

### 9.4 DRY vs DAMP
- [MAJOR] DRY (Don't Repeat Yourself): Business logic must not be duplicated — extract shared logic.
- [MINOR] DAMP (Descriptive And Meaningful Phrases) for tests: test readability is more important than DRY — a little duplication in tests is acceptable to make each test self-explanatory.
- [MAJOR] Premature abstraction: do not abstract before there are ≥ 3 real use cases — YAGNI.

---

## 10. API DESIGN

### 10.1 REST API
- [MAJOR] HTTP methods must have correct semantics: GET (read, idempotent), POST (create/non-idempotent), PUT (replace), PATCH (partial update), DELETE.
- [MAJOR] Status codes must be accurate:
  - 200 OK, 201 Created, 204 No Content
  - 400 Bad Request (validation), 401 Unauthorized (auth), 403 Forbidden (authz), 404 Not Found, 409 Conflict, 422 Unprocessable Entity
  - 500 Internal Server Error, 503 Service Unavailable
- [MAJOR] API response format must be consistent — wrapper object or flat? Pagination format? Error format? — must follow the project standard.
- [MAJOR] Breaking changes to the API MUST have a versioning strategy.
- [MINOR] Idempotency key for important POST operations (payments, order creation).

### 10.2 gRPC / GraphQL
- [MAJOR] Protobuf: backward-compatible changes only add new fields; do not reuse field numbers; do not rename fields.
- [MAJOR] GraphQL: N+1 problems must be solved with DataLoader / batching. Do not allow query resolvers without depth limiting.

### 10.3 Event / Message Design
- [MAJOR] Event schema must include: `eventId`, `eventType`, `version`, `occurredAt`, `aggregateId`.
- [MAJOR] Events MUST be immutable — do not modify a published event. If a change is needed, publish a compensating event.
- [MAJOR] Consumers must be idempotent — the same message may be delivered more than once (at-least-once delivery).

---

## 11. DOCUMENTATION

### 11.1 Code Comments
- [MAJOR] Comments should explain **WHY** (why was this decision made?), not **WHAT** (the code already says that).
  ```
  # BAD — comment the what
  # Increment counter by 1
  counter += 1

  # GOOD — comment the why
  # Use optimistic locking version bump instead of SELECT FOR UPDATE
  # to avoid table-level lock on high-traffic inventory table
  version += 1
  ```
- [MINOR] Commented-out code MUST NOT exist in the main branch — use git history instead.

### 11.2 Public API Documentation
- [MAJOR] Every public interface/function/method MUST have a docstring/JSDoc with: purpose, params, return value, exceptions/errors thrown, and an example if non-obvious.
- [MAJOR] API endpoints MUST have OpenAPI/Swagger annotations sufficient to auto-generate docs.

### 11.3 Decision Documentation
- [MINOR] Architecture Decision Records (ADR) for important decisions: why was library X chosen, why was design pattern Y used.

---

## 12. REVIEW CHECKLIST — QUICK REFERENCE

Use this checklist to ensure nothing is missed during review:

### ✅ Security Gate (block if any item fails)
- [ ] No hardcoded secrets / credentials
- [ ] All user input is validated
- [ ] No SQL injection risk
- [ ] Authorization checks are in the correct location
- [ ] No sensitive data is logged
- [ ] Stack traces are not exposed to clients

### ✅ Architecture Gate
- [ ] Business logic is in the correct layer
- [ ] Dependencies are injectable (testable)
- [ ] No circular dependencies
- [ ] External calls go through an abstraction

### ✅ Reliability Gate
- [ ] All async operations have error handlers
- [ ] External calls have timeouts
- [ ] Transaction boundaries are correct
- [ ] Retries use backoff

### ✅ Observability Gate
- [ ] Structured logging (no bare console.log)
- [ ] CorrelationId is propagated
- [ ] Errors are logged with context before being thrown

### ✅ Performance Gate
- [ ] No N+1 queries
- [ ] List endpoints have pagination
- [ ] Resources are properly released

### ✅ Test Gate
- [ ] Unit tests cover happy path + error cases
- [ ] Tests are independent and deterministic
- [ ] Mocks are only at the boundary

### ✅ AI Gate (if project has AI components)
- [ ] User input is not injected into the system prompt
- [ ] AI calls go through an abstraction layer
- [ ] Output parsing has error handling
- [ ] Sensitive data is not included in prompts

---

## 13. SEVERITY DECISION MATRIX

```
                     │  HIGH RISK  │  MEDIUM RISK  │  LOW RISK  │
─────────────────────┼─────────────┼───────────────┼────────────┤
 HIGH IMPACT         │  CRITICAL   │    MAJOR      │   MAJOR    │
 (Security/Data/Prod)│             │               │            │
─────────────────────┼─────────────┼───────────────┼────────────┤
 MEDIUM IMPACT       │  MAJOR      │    MAJOR      │   MINOR    │
 (Performance/UX)    │             │               │            │
─────────────────────┼─────────────┼───────────────┼────────────┤
 LOW IMPACT          │  MINOR      │    MINOR      │    NIT     │
 (Style/Convention)  │             │               │            │
─────────────────────┴─────────────┴───────────────┴────────────┘
```

**Merge rules:**
- Has `[CRITICAL]` → **Block merge** — must fix and re-review
- Has `[MAJOR]` with high risk → Block merge
- Has `[MAJOR]` with low risk → May merge; create a follow-up ticket
- `[MINOR]` / `[NIT]` → Does not block merge

---

## 14. PROJECT-SPECIFIC RULES

> Fill this in after running `/namht-scan` to add rules specific to your project.
> `/namht-build` updates this section from what each task taught it.

<!-- Placeholder — written by /namht-scan, kept current by /namht-rescan -->
