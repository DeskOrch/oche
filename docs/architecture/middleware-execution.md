# Internal middleware execution kernel

## Scope

Phase 1C evaluates the private execution interval between the accepted
segmented routing tree (ADR 0003) and specialized typed handler adapter (ADR
0004). It does not define a public middleware interface, context, dependency
injection, annotations, or `Oche.use`. Everything under
`benchmarks/handler_execution` remains benchmark-only.

The experimental request path is:

```text
dart:io HttpRequest
  -> generated segmented route tree
  -> generated typed parameter locals
  -> compile-time-known middleware pipeline
  -> specialized handler call
  -> specialized result/error mapping
  -> dart:io HttpResponse
```

The tree, binding, handler, and response semantics are identical between the
middleware candidates. Raw `HttpRequest` remains directly available. No
parameter map, dynamic argument list, reflection, runtime registration, service
locator, or public Oche API was introduced.

## Compared execution models

### Generated direct chain

Each generated leaf emits direct calls for every known middleware step. The
primary synchronous leaf is closure-free and stays synchronous. A depth-three
pipeline is structurally equivalent to:

```text
M0.before -> M1.before -> M2.before -> handler
                                  -> M2.after -> M1.after -> M0.after
```

The generator can flatten future global, group, and route scopes into this
single chain at build time. It never merges middleware lists per request.

### Prebuilt runtime traversal

The fair runtime candidate constructs one immutable typed step list at startup
and walks it for each request. Typed route arguments remain locals, and no
middleware list is allocated or merged per request. The leaf supplies a typed
handler closure to shared traversal machinery. This candidate centralizes
unwind behavior and shares more generated source, but adds loop/index/closure
machinery to the synchronous path.

### Baselines

`middleware_raw` is the hand-written `dart:io` lower bound.
`middleware_phase1b` is the accepted segmented tree plus specialized handler
adapter with zero middleware and is the primary 100% normalization. Generated
depth zero is an additional control.

## Execution contract

### Synchronous pipelines

A synchronous middleware returns `proceed` or `unauthorized` directly. The
generated path does not become `async`, construct a future, or allocate a
request wrapper merely because middleware exists. A successful handler result
is written only after all entered after-hooks finish.

### Asynchronous and mixed pipelines

Async routes enter an explicit typed async executor. A middleware step is
awaited only when its compile-time profile is async. Mixed pipelines alternate
sync and async steps without forcing the sync middleware implementation through
`Future.sync` or `Future.value`. The experiment distinguishes immediately
completed futures from one real `Duration.zero` event-loop boundary.

### Short-circuit

The first middleware may return `unauthorized` synchronously or asynchronously.
The executor then unwinds only already-entered outer steps, writes exactly one
401 JSON response, and does not invoke downstream middleware or the handler.
Correctness tests assert the exact body and an invocation count of zero. This
is the required foundation for future authorization and rate-limiting
middleware.

### Before/after ordering

Before-hooks execute in declaration order and after-hooks in reverse order.
For depth three the exact trace is:

```text
M0.before,M1.before,M2.before,handler,M2.after,M1.after,M0.after
```

Generated and runtime traversal candidates produce the same trace.

### Errors and response ownership

Throws in a sync `before`, the handler, or a sync `after` reach the existing
synchronous dispatch boundary. Throws after an `await` are caught by the async
response executor. Expected application failure remains 409; all unexpected
middleware/handler failures become the fixed 500 JSON body. Exception messages
are never returned. Response mapping happens after successful unwind, so a
failing after-hook cannot follow an already-closed success response.
As modeled here, pending after-hooks run after a successful handler or when an
inner step short-circuits; an uncaught handler/before/after exception stops the
remaining chain. A future public contract could opt into `finally` semantics,
but this phase does not silently impose them.

## State, composition, and instances

The normal pipeline creates no request-state container. The lazy experiment
allocates its `Map<Object, Object?>` only on the route that writes state. The
typed experiment constructs a generated-shaped holder with a direct `int`
field. HTTP results do not establish a stable speed ranking between these tiny
routes, so the architectural finding is pay-for-use: do not allocate a generic
state map unconditionally, and allow generated typed state when a future
feature can know its shape.

The first three generated steps emulate global, group, and route middleware.
They are flattened before runtime. A statically constructed middleware
instance is called directly; no lookup or dependency injection occurs. Its
three-trial HTTP result overlaps top-level middleware and exposes no
architectural blocker.

The boundary can later host logging, metrics, tracing, request timing,
authentication, and rate limiting: it sees raw request data, brackets handler
execution, supports async work and reliable early exit, and owns a deterministic
error/unwind interval. Those features and their public APIs remain out of
scope.

## Windows AOT evidence

The development host was native Windows 11 Pro build 26200 on an Intel Xeon
E5-2680 v4, with 28 logical CPUs, Dart 3.13.1 AOT, one server isolate, and
`oha` 1.16.0 on loopback. JSON results are local and ignored by Git.

### Primary representative route

The authoritative representative `GET /users/42` matrix used 100 routes,
concurrency 10/100/500, five seconds warmup, 30 seconds measured, five balanced
repetitions, and two seconds cooldown: 120 trials. The table contains generated
direct-chain medians.

| Depth | Concurrency | Requests/s | vs Phase 1B | vs raw | p50 ms | p95 ms | p99 ms | Peak RSS MiB | CPU |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 10 | 5,424.44 | 96.22% | 100.02% | 1.759 | 2.270 | 2.661 | 18.93 | 121.19% |
| 1 | 100 | 5,688.55 | 98.48% | 98.62% | 17.187 | 19.385 | 21.771 | 55.49 | 117.40% |
| 1 | 500 | 5,744.48 | 99.05% | 102.25% | 88.761 | 104.907 | 120.477 | 85.20 | 122.44% |
| 3 | 10 | 5,420.86 | 97.56% | 98.91% | 1.783 | 2.300 | 2.782 | 18.98 | 121.04% |
| 3 | 100 | 4,908.47 | 99.11% | 96.71% | 19.204 | 25.133 | 27.811 | 55.66 | 116.98% |
| 3 | 500 | 5,754.63 | 99.71% | 99.35% | 88.545 | 104.746 | 115.335 | 83.73 | 122.46% |

Idle RSS was 14.65-14.71 MiB. Generated and runtime traversal medians overlap:
runtime was between 96.04% and 100.81% of Phase 1B, while generated was between
96.22% and 99.71%. Neither is an end-to-end throughput winner.

Depth three meets its 97% Phase 1B target at every concurrency. Depth one meets
the 98% target at concurrency 100 and 500 but reaches only 96.22% at concurrency
10. That miss is not hidden even though generated is 100.02% of raw in the same
group. Every generated d1/d3 group remains above the complete-runtime budget of
95% of raw.

### Depth curve and behavior profiles

A separate diagnostic sweep used one second warmup, three seconds measured,
five repetitions, and no cooldown for depths 0/1/3/5/10. Its generated medians
across the three concurrency-specific medians were 5,365.7, 5,402.4, 5,374.9,
5,622.9, and 5,444.9 requests/s. Their median within-concurrency ratios to depth
zero were 100.0%, 101.7%, 97.9%, 102.8%, and 101.9%. The non-monotonic result
shows loopback/system noise dominates these tiny middleware costs; this short
sweep is not an acceptance gate. At concurrency 500 its p99 values were also
load-generator-saturated (about 649-738 ms), reinforcing that limitation.

Three-trial, one-second profile diagnostics at depth three covered sync-handler
plus sync middleware, async-handler plus sync middleware, all-async middleware,
mixed real-boundary execution, sync/async short-circuit, four error positions,
order, no/lazy/typed state, and instance middleware. All success groups returned
200, short-circuits returned 401, and errors returned 500 with success rate 1.0.
They are correctness-under-load evidence, not performance gates.

## Isolated AOT microbenchmark

Five-trial medians were:

| Case | ns/call |
| --- | ---: |
| Direct handler | 1.406 |
| Generated depth 1 / 3 / 5 | 2.238 / 5.647 / 10.293 |
| Runtime depth 1 / 3 / 5 | 8.380 / 15.905 / 26.458 |
| Generated/runtime short-circuit d3 | 1.619 / 5.768 |
| Generated before/after d3 | 5.736 |
| Sync middleware + async handler | 218.928 |
| Async middleware | 1,381.436 |
| Mixed real event-loop boundary | 14,553.9 |

Each loop carries an observable checksum. AOT can still inline and
devirtualize tiny code, so these values explain local machinery but do not
select the architecture; the HTTP matrix remains authoritative.

## Source, binary, and compilation growth

Representative single AOT builds were:

| Candidate | Routes | Depth | Source KiB | Lines | AOT MiB | Compile s |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Generated | 10 | 0 / 1 / 3 | 7.9 / 11.2 / 20.3 | 301 / 409 / 664 | 6.208 / 6.209 / 6.210 | 3.14 / 2.91 / 2.99 |
| Generated | 100 | 0 / 1 / 3 | 57.7 / 88.0 / 172.4 | 1,813 / 2,911 / 5,416 | 6.271 / 6.290 / 6.341 | 3.10 / 3.15 / 3.28 |
| Generated | 1,000 | 0 / 1 / 3 | 556.6 / 857.6 / 1,694.4 | 16,813 / 27,811 / 52,816 | 7.030 / 7.158 / 7.562 | 4.92 / 5.38 / 6.73 |
| Runtime | 10 | 0 / 1 / 3 | 9.1 / 9.1 / 9.1 | 355 | 6.211 | 2.84-2.92 |
| Runtime | 100 | 0 / 1 / 3 | 78.1 / 78.1 / 78.1 | 2,767 | 6.335 | 3.09-3.12 |
| Runtime | 1,000 | 0 / 1 / 3 | 769.5 / 769.5 / 769.5 | 26,767 | 7.471-7.472 | 5.44-5.51 |

At 100 routes, generated depth 5 and 10 grew to 288.4 and 716.3 KiB of
source, 6.395 and 6.623 MiB AOT, and 3.56 and 4.61 seconds compile. Runtime
remained 78.1 KiB, 6.335 MiB, and about 3.1 seconds because the step list is
shared. At 1,000 routes/depth 3, sharing removes about 925 KiB of source and
1.22 seconds of observed compile time, but only about 90 KiB from the AOT
binary. Conversely runtime is larger at shallow 1,000-route depths because its
per-leaf closure machinery remains present.

Full direct flattening is therefore source-expensive but did not cause
pathological AOT growth in the measured shapes. A shared or hybrid kernel may
be attractive for deep pipelines, but an arbitrary depth threshold is not yet
justified.

## Current conclusion

Generated direct composition remains the provisional lead because it preserves
the simplest closure-free synchronous contract, makes early exit and unwind
explicit, and keeps the measured complete runtime above 95% of raw. Runtime
traversal remains credible and wins source/compile growth for deep chains while
remaining tied in HTTP throughput. Because depth-one missed its incremental
budget at concurrency 10 and the code-size/runtime trade-off has no clear
winner, ADR 0005 remains Proposed. No public middleware contract follows from
this experiment.
