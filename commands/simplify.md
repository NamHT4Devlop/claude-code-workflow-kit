---
description: Behavior-preserving simplification — reduce complexity/duplication/nesting, improve clarity, tests stay green
argument-hint: "[file/function/module to simplify | empty = the files changed on this branch]"
---

Use the **cwk-simplify** skill to reduce complexity and improve clarity of the target **without
changing behavior**: remove dead code, flatten nesting (guard clauses), extract/rename for
readability, kill duplication, drop needless abstraction — one small refactor at a time, keeping
tests green after each. If a bug surfaces, stop and flag it (don't change behavior). Change-discipline.

Target (file/function/module; empty = the files changed on this branch vs its base — commit them first, the safety net needs a clean tree):
$ARGUMENTS
