# Review traps by language and framework

Used by `review-protocol.md` Step 3. Each trap names the defect, the evidence needed before
reporting it, and when not to report it. Most are taken from defects verified on real repositories
while building this kit; the example after "Seen:" is where one was found, so a reviewer can read a
real instance.

Report only what is likely real in the changed code and what it reaches. Check the project's
`review-skills.md` Section 14 first: project rules outrank these.

---

## Any language

- **Unscoped lookup by id in a multi-tenant or multi-user app.** A record is fetched by an id from the
  request with no filter on the current tenant or owner, then read, changed or deleted.
  Evidence: the lookup, the id's source (path, body, query), and the absence of a scope or ownership
  check on the path the request takes, including the controller and any policy.
  Don't flag: lookups on data that is public by design, or where a policy or query scope applies it.
  Seen: human-essentials `transfer_destroy_service.rb` `Transfer.find`; mall `detail(orderId)`.
- **Mass assignment.** Request fields bound straight onto a loaded entity (or permitted params that
  include `*_id`, `organization_id`, `role`, `price`, `status`), then saved.
  Evidence: which fields the binder or permit list allows, and one that the client should not set.
  Seen: spring-petclinic pet form binding onto `Owner`; mall cart `price`; human-essentials broadcast
  `organization_id`.
- **Authorisation on the page but not on the action.** The edit page checks a role, the update or
  POST handler does not; or a GET performs a state change.
  Evidence: both handlers side by side.
- **Check-then-act without a lock.** Read a balance, stock or counter, decide, then write, with no
  row lock, conditional update or unique constraint.
  Evidence: the read and the write are separate statements and two requests can interleave.
  Don't flag: single-writer paths or updates guarded by `WHERE qty >= ?`.
- **Idempotency on money and stock.** A payment, fulfilment or stock deduction that runs again on a
  retried or duplicated request.
  Evidence: the handler does not check current state before applying.
  Seen: mall `paySuccess` with no status check.
- **Side effect outside or inside the transaction, wrongly.** A message, email or HTTP call sent inside
  a transaction that can still roll back, or a write that must be atomic split across two
  transactions.
- **A catch that handles one constraint and rethrows the rest.** Code catches a database or
  validation exception, recognises one case (a duplicate name) and rethrows everything else. Every
  other constraint on the same write, such as column length, not-null, a foreign key or a check,
  now reaches the user as a 500 instead of a form error.
  Evidence: the schema's constraints on the columns this write touches, compared with what the
  validator checks before the save.
  Seen: spring-petclinic pet name `VARCHAR(30)` with no length validation behind a catch that only
  recognised the unique-name violation.
- **Recognising an error by its message text.** Matching a constraint name or phrase in an exception
  message breaks across databases, drivers, locales and unnamed constraints.
  Evidence: the schemas for each supported database, and whether each names the constraint.
- **Error swallowed into success.** A caught exception or failed call turned into a success response,
  an empty result or a log line, where the caller needs to know.
- **Secrets and personal data in logs or responses.** Request logging of bodies or query strings, or a
  response that serialises a whole entity including a password hash or token.
  Seen: mall `WebLogAspect`, `/sso/info`; prereview request log with OAuth `code`.
- **A token or signature check that trusts the token.** Algorithm taken from the token header, `none`
  accepted, expiry optional, signature compared with `==`.
  Evidence: read the library call and what it does for the pinned version.
  Seen: mall + Hutool 5.8.40 `JWTUtil.verify`.
- **Deleted business logic.** A removed branch, guard or validation. Evidence: what reached it
  (`provenlens impact`) and whether anything now does the same.

## Java / Spring

- **`@Transactional` that does not apply**: on a private method, on a self-invocation, or on a class
  the caller reaches without the proxy. Evidence: how the method is called.
  Don't flag it only because the annotation sits on the interface: recent Spring versions honour
  interface-level annotations through the bean's proxy, older ones depend on the proxy type. Check
  the Spring version before claiming it does not apply (library default, not verified here).
- **Business failure returned as HTTP 200** (`CommonResult.failed`, a result wrapper) where a client or
  monitor relies on status codes. Flag once per API style, not per endpoint.
- **`@Controller` handler returning a String meant as a body** without `@ResponseBody`: the string is
  treated as a view name. Seen: mall `AlipayController#notify`.
- **Binder without an allow-list** on an entity: `@InitBinder` that only disallows `id`, with
  `@ModelAttribute` binding request params onto a persistent object.
- **MyBatis `${}`** instead of `#{}` with request data: SQL injection. Evidence: the value's origin.
- **MyBatis `CASE id WHEN … THEN …` in a batch update** where two items can share an id: only the first
  `WHEN` applies. Seen: mall `PortalOrderDao.xml`.
- **`REPLACE INTO` / delete-and-reinsert** that omits columns: those columns are reset.
  Seen: mall `PmsSkuStockDao.xml` dropping `lock_stock` and `promotion_price`.
- **`BigDecimal` compared with `equals`, or converted with `intValue()`** for a money threshold.
  Seen: mall promotion thresholds truncated.
- **`Optional.get()` / unchecked `find` result** on a path where the row can be absent.
- **Spring Security**: a new endpoint missing from the matcher rules, or added to the ignore list; a
  filter that authenticates but never checks the account is enabled.

## Ruby / Rails

- **`Model.find(params[:id])`** instead of `current_organization.models.find(...)` in a tenant app.
  See the any-language trap; also check `find_by(id:)` and service objects that receive the raw id.
- **`create` instead of `create!` for a record that must exist** (an event, a ledger row): a failed
  validation returns an unsaved object and the caller carries on. Seen: human-essentials events.
- **Callbacks with side effects** (`after_create`, `after_save`) that do not run on `update_all`,
  `insert_all`, `delete_all`, or that run inside a transaction and send mail before commit
  (`after_commit` is usually wanted).
- **`delete_all` / `destroy` on associations without `dependent:`**: rows are orphaned or their
  foreign key is nulled. Evidence: the association definition.
- **`perform_now` in a request** for mail or slow work, where failure should not fail the request.
- **Strong params permitting a foreign key or role** that the user should not choose.
- **Migrations**: adding a column with a default or an index without `algorithm: :concurrently` on a
  large table; a data migration without a down path; `strong_migrations` checks bypassed.
- **N+1 in a new view or serializer loop.** Evidence: the loop and the association read inside it.
  Don't flag without a loop over a collection that can be large.

## TypeScript / JavaScript

- **Unhandled promise or an error channel dropped**: `await` missing, `.catch(() => {})`, an Effect or
  Either left branch mapped to a default. Evidence: what the caller then assumes.
- **Handlers swapped in a match / fold** (`matchEW(onLeft, onRight)` with the logging on the wrong
  side). Seen: prereview co-author invite logging failures as successes.
- **`throw` inside an Effect / fp-ts pipeline** where the code otherwise uses typed errors: it becomes
  a defect the typed handler never catches.
- **Delete-then-write without a lock** on a draft or session in a key-value store: two requests can
  both read before either deletes. Seen: prereview double publication.
- **Writing untrusted text to the DOM** with `innerHTML`, jQuery `.html()`, `dangerouslySetInnerHTML`,
  or a template's raw output. Evidence: where the value comes from (URL, API response, user input).
  Seen: metadata-maker `topBar.js` URL parameter into `.html()`.
- **Unescaped values in generated XML/HTML/CSV**, including attributes. Seen: metadata-maker MARCXML.
- **Byte length vs string length** when building binary formats or length-prefixed protocols
  (`.length` counts UTF-16 code units). Seen: metadata-maker MARC directory.
- **OAuth / login callback without a `state` bound to the session.**
- **Browser APIs that need a secure context** (`crypto.randomUUID`, clipboard, service workers) on a
  site that may be served over plain HTTP.
- **Type assertions (`as`, `!`) hiding a nullable** on data from outside the process.

## SQL, migrations and schema

- **A constraint the code relies on that the schema does not have**: uniqueness enforced only by a
  validation, a foreign key only in the ORM. Evidence: the schema file for each supported database.
  Seen: spring-petclinic unique pet name present in H2 and Postgres schemas, unnamed in MySQL.
- **A migration that rewrites or locks a large table** on a hot path.
- **A schema script that runs on every start but is not re-runnable.** When startup always applies
  the script (`spring.sql.init.mode=always`, a seed task, an entrypoint), every statement must be
  idempotent: `CREATE INDEX` or a constraint without `IF NOT EXISTS` fails the second start.
  Seen: spring-petclinic Postgres unique index.
- **A constraint added inside `CREATE TABLE IF NOT EXISTS`**: existing databases never get it.
- **A column dropped or renamed while code still reads it**, or read by another service.
- **Dialect drift**: the same schema maintained per database with a difference the code depends on.

## When not to report

- Anything a linter, formatter, compiler or type checker in the project already reports.
- A concurrency or security issue inferred only from a name ("`processAsync` must race").
- Style preferences not written in the project's conventions.
- Pre-existing code the diff did not touch, unless the diff makes it newly reachable or worse. Mention
  it once under "noticed, not in this change" if it is serious.
