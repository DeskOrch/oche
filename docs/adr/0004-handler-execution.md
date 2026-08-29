# ADR 0004: Generated handler execution contract

- Status: Accepted
- Date: 2026-08-28

## Context

ADR 0003 selected generated segmented-tree dispatch. The next private boundary
must invoke realistic Dart handlers without turning generated routing into a
dynamic invocation runtime. Handlers naturally return synchronous values,
`void`, immediately completed futures, or futures with real asynchronous work.
Future controllers also require direct method invocation on statically known
instances.

Phase 1B compares a generated result-type-specialized adapter with a credible
uniform `FutureOr<Object?>` adapter. The Phase 1A direct-response contract is the
primary performance baseline, and hand-written `dart:io` remains the long-term
lower bound.

## Decision

Future generated Oche code should emit direct typed handler calls and specialize
the execution path by declared return shape:

- synchronous values map synchronously without creating a future;
- `Future<T>` values use a typed async helper;
- parameters remain validated typed locals;
- controller methods use statically known instances;
- synchronous unexpected failures are caught at one shared dispatch boundary;
- asynchronous helpers catch failures after `await`;
- result mapping is specialized at the generated leaf;
- no generic handler collection, reflection, `Function.apply`, dynamic argument
  list, parameter map, or service locator participates in request execution.

`FutureOr` and the intermediate internal result remain comparison mechanisms,
not selected runtime contracts. Raw `HttpRequest` remains sufficient internally;
the lazy request view is retained only as measured evidence and is not public.

## Evidence

A 540-trial native-Windows AOT screening matrix covered 10/100/1,000 routes,
concurrency 10/100/500, three synchronous handler shapes, four implementations,
and five balanced repetitions. It used an abbreviated local 1-second warmup,
5-second measurement, and no cooldown. Specialized averaged 100.79% of the
matching Phase 1A direct throughput and 100.41% of raw `dart:io`; all 27 groups
remained above 95% of raw. Its minimum in the abbreviated matrix was 97.30% of
Phase 1A direct.

The worst short group was repeated with the target five-second warmup,
30-second measurement, five repetitions, and two-second cooldown. Specialized
then reached 6,007.96 requests/s: 99.07% of Phase 1A direct and 100.59% of raw.
It therefore meets the primary 98% and long-term 95% acceptance thresholds.

The uniform candidate was statistically tied in HTTP throughput, but generated
810-861 more source bytes and necessarily constructs the intermediate response
on synchronous mapped results. Specialized and uniform AOT executable sizes
were identical at 10, 100, and 1,000 routes. RSS, CPU, and latency ranges
overlapped. The isolated microbenchmark showed no basis for selecting on direct
call, instance call, tear-off, or `FutureOr` discrimination alone; it did show
about 197 ns for constructing and encoding the representative intermediate
response versus about 1.3-3.0 ns for the call/adapter-only cases. These tiny
loops are subject to AOT inlining and devirtualization.

Correctness tests exercise all three generated candidates with synchronous and
asynchronous top-level calls, synchronous and asynchronous instance methods,
zero/one/multiple typed parameters, text/JSON/bytes/void/structured results,
400/404/405/409/500 mappings, exact content types and bodies, and non-disclosure
of internal error details. No public Oche API changed. Full measurements and
limitations are recorded in the handler-execution architecture document.

## Consequences

Production code generation can later emit small leaf adapters without a public
handler base class or dynamic invocation layer. Sync handlers keep a fully
synchronous fast path. Async semantics remain explicit and type-directed.
Generated middleware can wrap the documented execution interval. Public
controller, request, result, exception, and serialization designs remain free
to evolve.

The main cost is additional generated source per return shape. Async helpers and
result writers must remain carefully audited for equivalent error semantics.
Specialization may duplicate small amounts of generated code, which is measured
against source, compile-time, and binary-size growth.
