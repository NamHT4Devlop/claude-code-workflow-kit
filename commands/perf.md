---
description: Measure-first performance optimization — find the real bottleneck, fix it, prove it with before/after numbers
argument-hint: "[slow area/endpoint/query + any profiling data]"
---

Use the **cwk-perf** skill to optimize with a **measure-first** discipline: get a baseline number,
find the biggest bottleneck (N+1, missing index, full scan, blocking/sequential calls, missing
cache/pagination, chatty service calls), fix it with change-discipline, then **re-measure** to prove
the win. No blind micro-optimizing; correctness first (watch cache invalidation).

Slow area / endpoint / query (+ profiling data if any):
$ARGUMENTS
