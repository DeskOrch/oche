# ADR 0005: Shared closure-free middleware execution kernel

- Status: Accepted
- Date: 2026-08-30

## Context

ADR 0003 accepts generated segmented-tree routing and ADR 0004 accepts direct,
typed, return-shape-specialized handler execution. Middleware must bracket that
handler interval while preserving sync execution, typed parameter locals,
deterministic unwind, reliable short-circuit, and the established HTTP error
mapping. This ADR decides only the private execution kernel.

Phase 1C found that a fully generated direct chain has excellent isolated cost
but source grows with routes times middleware depth. Immutable runtime traversal
shares source but introduces loop/index/handler-closure machinery. HTTP did not
establish a stable throughput winner.

Phase 1D therefore tested a third model: shared, depth-limited closure-free
entry/exit helpers around a direct generated handler call.

## Decision

Use the shared closure-free kernel (Candidate C):

- flatten compile-time-known global/group/route scopes into a pipeline identity;
- select shared sync entry/exit helpers for known common depths;
- keep a fully sync pipeline synchronous;
- invoke the handler directly from generated route code with typed locals;
- use one generated async connector and shared async boundary traversal rather
  than route-specific executors or universal dynamic handler invocation;
- execute before hooks in declaration order and after hooks in reverse order;
- on short-circuit, unwind only entered steps and never invoke downstream;
- retain raw `HttpRequest`, specialized response mapping, static middleware
  instances, and lazy/pay-for-use request state.

The selected request path creates no middleware list, handler closure, `next`
closure chain, argument collection, response wrapper, or mandatory state map
per request. This is an implementation-inspection statement, not a claim that
the complete Dart HTTP path makes zero allocations.

No public middleware API, registration syntax, context, annotation, or
dependency model is decided here.

## Evidence

The ten-repetition 100-route d1/c10 repeat measured Candidate C at 5,492.26
req/s median: 102.05% of Phase 1B and 100.29% of raw. Generated and runtime
were 102.11% and 101.99% of Phase 1B. The earlier Phase 1C generated result of
96.22% was therefore not reproducible and appears to have been noise.

In the five-repetition production matrix, C d3 reached 99.58%, 100.22%, and
99.63% of Phase 1B at concurrency 10/100/500, passing the 97% budget. C d1
reached 100.02%, 95.16%, and 101.29%; a focused ten-repetition c100 run
confirmed that isolated incremental miss at 95.24%. In that run Phase 1B was
103.84% of raw and C remained 98.90% of raw. A separate d3 raw/C comparison
placed C at 99.81%, 102.89%, and 101.75% of raw, passing the complete-stack
95% target at all production concurrencies.

The AOT microbenchmark measured shared/generated at 2.179/2.189 ns for d1 and
5.735/5.758 ns for d3, versus runtime at 9.516 and 17.268 ns. It provides no
evidence that the c100 HTTP miss is caused by Candidate C's helper boundary.

At 1,000 routes/d3, Candidate C delivered 5,453.54 req/s (101.82% of Phase 1B,
102.97% of raw). Its 829,694-byte source was 47.02% of generated A and 101.47%
of runtime B. Its 7,505,408-byte AOT executable was smaller than A and B, and
its 5.170-second observed compile was shorter than both. C therefore achieves
the intended middle point without requiring a throughput win over A.

Correctness tests cover d0/d1/d3/d5/d10, sync/async/mixed continuation,
sync/async short-circuit with zero handler invocation, exact before/after
order, failure before/handler/after/async, typed one- and two-parameter routes,
static instance middleware, unused/lazy/typed state, and 400/404/405/409/500
semantics with no leaked exception details.

Detailed protocol, tables, maintainability comparison, and limitations are in
`docs/architecture/middleware-execution.md`.

## Why Accepted

Candidate C matches generated direct composition in the isolated d1/d3 path,
keeps the complete HTTP stack within budget, cuts the decisive 1,000-route/d3
source roughly in half, and produced the smallest measured AOT binary and
compile time. Its code generation is simpler than per-route unrolling and its
sync contract is simpler than runtime traversal.

The one incremental d1/c100 miss is documented, but another kernel experiment
would optimize against a noisy relative baseline despite C remaining above the
complete-stack budget and matching A in the diagnostic that isolates helper
cost. That uncertainty does not alter the architectural choice.

## Consequences

The first minimal user-facing Oche API may be designed on top of this private
kernel without reopening A/B/C. Future work must still decide public middleware
types, async shape policy, response ownership, streaming/cancellation, and
developer-facing diagnostics. It must preserve the direct typed connection and
pay-for-use state behavior accepted here.

ADR 0003 and ADR 0004 remain Accepted. ADR 0002 remains Proposed pending
independent native-Linux validation.
