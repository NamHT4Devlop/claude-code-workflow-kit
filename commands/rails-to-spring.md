---
description: Port a service or chosen endpoints to another stack (e.g. Rails+GraphQL → Spring Boot), preserving the contract + behavior, verified by golden tests
argument-hint: <what to port — source stack, target stack, and the endpoint set (all GraphQL + the specific REST APIs)>
---

Use the **cwk-rails-to-spring** skill to port the service below onto a new stack while preserving its contract
and business behavior. Default target profile: Spring Boot + MyBatis + Flyway + Camel + SQS + MySQL,
sharing the same database. Freeze the contract (port the GraphQL schema 1:1 + the named REST APIs),
ground the business rules in the source (`/cwk-scan`), capture golden/characterization tests of the
real responses, then re-implement endpoint-by-endpoint and verify byte-for-byte parity before cutover
(strangler). Port ONLY the scoped set — all GraphQL resolvers + the specific 3–5 REST APIs — and list
anything out of scope.

A port runs across many sessions: if `cwk-sessions/port/_progress.md` exists, **read it first and
continue from where it stopped** rather than restarting; otherwise create it once the scope is agreed.

What to port (source stack, target stack, endpoint list, DB & async decisions):
$ARGUMENTS

At step 0, confirm the scope and target profile, and ask for anything missing (the exact endpoint list,
the GraphQL library on the Java side, whether SQS/Camel/jobs are in scope) before porting. Do not invent
business rules — cite the Ruby source. Edits code; the human owns deploy and cutover.
