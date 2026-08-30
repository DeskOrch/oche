# ADR 0005: Generated middleware execution kernel

- Status: Proposed
- Date: 2026-08-30

## Context

ADR 0003 accepts generated segmented-tree routing and ADR 0004 accepts direct,
typed, return-shape-specialized handler execution. Middleware must bracket that
handler interval while preserving the synchronous fast path, typed parameter
locals, deterministic unwind, reliable short-circuit, and existing error
mapping. It must not introduce a public framework API in this phase.

Phase 1C compares a generated unrolled direct chain with a fair prebuilt typed
runtime traversal at depths 0, 1, 3, 5, and 10. Raw `dart:io` and the Phase 1B
zero-middleware adapter are the relevant baselines.

## Provisional direction

Keep generated direct composition as the leading model for the next internal
experiment:

- flatten compile-time-known global/group/route scopes into each route;
- call sync middleware and sync handlers synchronously and directly;
- use explicit typed async executors only when a handler or step is async;
- execute before-hooks in declaration order and after-hooks in reverse order;
- on short-circuit, unwind only entered outer steps and never call downstream;
- retain raw `HttpRequest`, typed handler locals, specialized response mapping,
  and statically known middleware instances;
- allocate generic request state only when a route actually needs it.

This is not yet an Accepted architectural decision. The runtime traversal
candidate remains live, particularly for deep or highly replicated pipelines.
No public middleware interface, context, registration syntax, or dependency
model is decided here.

## Evidence

The native-Windows primary AOT matrix used `GET /users/42`, 100 routes,
concurrency 10/100/500, five-second warmup, 30-second measurement, five
balanced repetitions, and two-second cooldown (120 trials).

Generated depth three reached 97.56%, 99.11%, and 99.71% of Phase 1B and passed
the 97% target at all three concurrencies. Generated depth one reached 96.22%,
98.48%, and 99.05%; it missed the 98% target at concurrency 10 while equaling
raw `dart:io` there at 100.02%. Every generated d1/d3 group remained above 95%
of raw. Runtime traversal was statistically tied, ranging from 96.04% to
100.81% of Phase 1B across the same groups.

The direct-chain microbenchmark is materially smaller than runtime traversal
at equivalent depth, but these nanosecond loops are diagnostic. End-to-end HTTP
does not establish a throughput winner.

Generated source grows with routes times depth. At 1,000 routes/depth 3 it used
1,694.4 KiB source, 7.562 MiB AOT, and 6.73 seconds observed compile, versus
769.5 KiB, 7.472 MiB, and 5.51 seconds for runtime traversal. At 100 routes/depth
10 generated used 716.3 KiB source and 6.623 MiB AOT versus 78.1 KiB and 6.335
MiB runtime. The binary growth is not pathological, but the source/compile
trade-off is material.

Correctness tests and load diagnostics cover zero/one/three middleware,
sync/async/mixed continuation, sync/async short-circuit with zero handler
invocations, exact before/after order, throws before/inside/after/async, typed
one- and two-parameter handlers, instance middleware, lazy/typed state, and
400/404/405/409/500 semantics.

Detailed measurements and caveats are in
`docs/architecture/middleware-execution.md`.

## Why Proposed

The evidence supports the execution semantics but does not clearly favor one
implementation model. The generated candidate misses one incremental
throughput budget, while runtime traversal materially reduces deep-chain source
growth without a demonstrated HTTP penalty. Accepting either model, or an
untested arbitrary hybrid threshold, would overstate the evidence.

## Consequences

Phase 1C can be used as a reproducible kernel laboratory without constraining
the public API. A follow-up experiment should isolate whether a closure-free
shared helper can retain direct typed calls while reducing duplicated source,
then repeat the marginal depth-one concurrency-10 group and a deep 1,000-route
build. ADR 0003 and ADR 0004 remain Accepted. ADR 0002 remains Proposed pending
independent native-Linux validation.
