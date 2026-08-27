# ADR 0001: Performance-first development

- Status: Accepted
- Date: 2026-08-27

## Context

Oche aims to combine enterprise-oriented developer ergonomics with very small
runtime overhead. HTTP foundation choices affect routing, request/response
models, middleware, AOT size, startup, memory, and the cost of every future
request. Building high-level APIs first would couple Oche to assumptions that
are expensive to reverse and would make their overhead difficult to isolate.

Relic is a plausible foundation, but selecting it from features or headline
benchmarks alone would conflict with Oche's performance-first principles. Raw
`dart:io` establishes the lower-level reference point on the same Dart runtime.

## Decision

Before designing high-level APIs, maintain equivalent raw `dart:io` and Relic
servers for three workloads: plaintext, fixed JSON, and a parameterized route.
Measure them with the same external load generator, process lifecycle, warmup,
configuration, host, and AOT mode. Preserve machine-readable raw results and
report unavailable measurements as absent rather than invented values.

Correctness tests are part of the baseline: performance results are meaningful
only when implementations satisfy the same HTTP contract.

## Consequences

- Phase 0 produces evidence and tooling rather than a framework architecture.
- Relic remains a candidate, not a selected dependency for Oche itself.
- Measurements must be repeated on representative Linux production hardware;
  development-host results are directional only.
- Any benchmark optimization must be evaluated for equivalent applicability to
  both implementations.
- High-level APIs remain deferred until routing overhead, startup, RSS, CPU, and
  executable-size evidence can inform the next decision.
