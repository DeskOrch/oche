# Internal middleware execution kernel

## Scope

Phases 1C and 1D evaluate the private execution interval between the accepted
segmented routing tree (ADR 0003) and specialized typed handler adapter (ADR
0004). They do not define a public middleware interface, request context,
dependency injection, annotations, or `Oche.use`. Everything under
`benchmarks/handler_execution` remains benchmark-only.

The accepted experimental request path is:

```text
dart:io HttpRequest
  -> generated segmented route tree
  -> generated typed parameter locals
  -> compile-time-known shared middleware kernel
  -> direct specialized handler call
  -> specialized result/error mapping
  -> dart:io HttpResponse
```

Raw `HttpRequest` remains directly available. There is no parameter map,
dynamic argument list, reflection, runtime registration, service locator, or
public Oche API.

## Compared execution models

### A: generated direct chain

Each generated leaf emits calls for every known middleware step. Its primary
sync path is closure-free and fast, but executor source grows with routes times
middleware depth.

### B: immutable runtime traversal

One immutable typed step list is built at startup and walked per request. No
list is constructed per request, but each leaf passes a typed handler closure
to loop-based shared machinery. It minimizes duplicated executor source at the
cost of loop/index/closure machinery in the sync path.

### C: shared closure-free kernel

The selected model separates middleware entry and exit from handler execution.
Generated route code identifies a depth-specialized shared kernel, calls the
handler itself with typed locals, and then invokes the matching unwind helper:

```dart
if (!enterSharedSyncPipeline3(request, profile)) {
  writeMiddlewareUnauthorized(request);
  return;
}
final result = middlewareTwoIntHandler(userId, orderId);
exitSharedSyncPipeline3(request, profile);
```

Sync helpers for depths 1, 3, 5, and 10 exist once in support code rather than
once per route. The primary request path passes no handler, closure, middleware
list, dynamic argument collection, context wrapper, or intermediate response
object to the kernel. Source inspection establishes those properties; it does
not justify a claim of zero allocations for the complete Dart HTTP stack.

Generated source contains route dispatch, typed binding, the selected pipeline
identity, and the direct handler connection. Global, controller/group, and
route scopes are flattened into that identity at compile time. There is no
runtime scope merge.

### Baselines

`middleware_raw` is the hand-written `dart:io` lower bound.
`middleware_phase1b` is the accepted segmented tree and specialized handler
adapter with zero middleware and is the incremental 100% normalization.

## Execution contract

### Synchronous pipelines

A sync pipeline remains sync. Depths 1, 3, and 5 use bounded specialized
enter/exit helpers; depth 10 composes the depth-5 helper with a small loop for
the stress-only tail. The handler remains outside the helper and is invoked
directly. No `Future` is introduced merely because sync middleware exists.

### Asynchronous and mixed pipelines

Candidate C emits one application-level async connector rather than a unique
executor per route or per parameter shape. A sync-middleware/async-handler
profile uses the sync enter/exit helper around a direct awaited typed handler.
Profiles with genuine async middleware use one shared async enter/exit loop;
only statically known async steps are awaited. The connector selects the two
known handler boundary shapes directly and never receives a callback.

This avoids both universal dynamic invocation and a combinatorial executor for
every sync/async sequence. A future generator may add another shared shape only
when a measured application needs one.

### Short-circuit and ordering

An unauthorized decision stops later middleware and the handler, unwinds only
successfully entered outer steps, and writes one 401 JSON response. Before
hooks run in declaration order and after hooks in reverse order:

```text
M0.before,M1.before,M2.before,handler,M2.after,M1.after,M0.after
```

### Errors and response ownership

Expected application failure remains 409. Invalid parameters, unknown routes,
and wrong methods remain 400, 404, and 405 with `Allow`. Unexpected failures
from sync/async before, handler, or after positions become the fixed generic
500 JSON body; exception details and stack traces are not returned.

Pending after hooks run after success and for entered outer steps during a
short-circuit. As in Phase 1C, an uncaught handler/before/after exception stops
the remaining chain rather than silently imposing `finally` semantics.

### State and instances

The normal path allocates no request-state container. The lazy experiment
allocates its map only when state is written, while the typed experiment uses a
direct generated-shaped field. A statically constructed middleware instance is
called directly with no lookup or dependency injection.

## Native Windows AOT evidence

The host was Windows 11 Pro build 26200, Intel Xeon E5-2680 v4, 28 logical
CPUs, Dart 3.13.1 AOT, one server isolate, and `oha` 1.16.0 on loopback. Unless
stated otherwise, runs used 5 seconds warmup, 30 seconds measurement, 2 seconds
cooldown, a deterministic position-balanced order, and retained raw JSON
trials under the Git-ignored results directory.

### Critical d1 / concurrency 10 repeat

The representative `GET /users/42`, 100-route group used ten repetitions and
five implementations (raw was retained as an extra lower-bound reference):

| Implementation | req/s median | mean | min | max | stddev | p50 ms | p95 ms | p99 ms | Peak RSS MiB | CPU |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Phase 1B | 5,381.81 | 5,359.92 | 4,986.09 | 5,704.76 | 221.08 | 1.790 | 2.282 | 2.627 | 18.94 | 122.77% |
| Generated A | 5,495.22 | 5,492.78 | 5,090.56 | 5,825.61 | 208.49 | 1.756 | 2.239 | 2.579 | 18.93 | 122.25% |
| Runtime B | 5,489.07 | 5,418.18 | 5,112.84 | 5,704.13 | 194.41 | 1.750 | 2.243 | 2.673 | 18.97 | 122.85% |
| Shared C | 5,492.26 | 5,468.85 | 5,092.91 | 5,693.67 | 189.88 | 1.738 | 2.290 | 2.670 | 18.95 | 123.03% |
| Raw | 5,476.67 | 5,447.13 | 5,130.17 | 5,719.49 | 199.00 | 1.752 | 2.242 | 2.596 | 18.79 | 122.87% |

Candidate C was 102.05% of Phase 1B and 100.29% of raw. The earlier Phase 1C
generated result of 96.22% at this exact group was noise rather than a stable
kernel penalty: all A/B/C candidates exceeded Phase 1B in the ten-trial repeat.

### Production depth/concurrency matrix

Candidate C and Phase 1B were measured in five paired repetitions for depths
0/1/3/5 and concurrency 10/100/500:

| Depth | c | C req/s | C vs 1B | p50 ms | p95 ms | p99 ms | Peak RSS MiB | CPU |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 0 | 10 | 5,798.22 | 101.12% | 1.676 | 2.022 | 2.322 | 18.94 | 124.23% |
| 0 | 100 | 5,749.61 | 102.22% | 17.025 | 19.588 | 21.521 | 55.48 | 121.94% |
| 0 | 500 | 6,070.23 | 99.84% | 84.616 | 98.210 | 107.196 | 84.15 | 124.01% |
| 1 | 10 | 5,775.93 | 100.02% | 1.679 | 2.050 | 2.376 | 18.96 | 123.97% |
| 1 | 100 | 5,324.40 | 95.16% | 18.073 | 22.856 | 25.794 | 55.51 | 119.36% |
| 1 | 500 | 5,578.63 | 101.29% | 89.667 | 119.921 | 144.457 | 84.08 | 123.27% |
| 3 | 10 | 5,766.01 | 99.58% | 1.684 | 2.037 | 2.341 | 18.96 | 124.62% |
| 3 | 100 | 5,801.75 | 100.22% | 16.934 | 19.084 | 21.300 | 55.28 | 123.75% |
| 3 | 500 | 6,182.05 | 99.63% | 83.046 | 95.385 | 101.365 | 87.06 | 125.63% |
| 5 | 10 | 5,182.47 | 102.52% | 1.861 | 2.442 | 2.906 | 18.96 | 121.68% |
| 5 | 100 | 5,362.10 | 105.83% | 18.077 | 22.571 | 27.062 | 55.20 | 120.95% |
| 5 | 500 | 5,933.99 | 103.30% | 85.806 | 103.588 | 114.029 | 84.12 | 123.40% |

d3 passed its 97% incremental target at every concurrency. d1 passed at c10
and c500 but missed at c100. A focused ten-repetition d1/c100 run confirmed
95.24% of Phase 1B; however Phase 1B was itself 103.84% of raw, while Candidate
C remained 98.90% of raw. The isolated d1 cost was indistinguishable from A,
so this single incremental miss is recorded rather than used to overfit the
kernel.

A separate contemporaneous raw/C d3 run measured C at 99.81%, 102.89%, and
101.75% of raw for c10/c100/c500. The complete-stack 95% budget therefore
passes at all production concurrencies.

### 1,000 routes / depth 3

Five HTTP repetitions at concurrency 100 produced:

| Implementation | req/s | vs 1B | vs raw | p50/p95/p99 ms | Peak RSS MiB | CPU |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Generated A | 5,243.91 | 97.90% | 99.01% | 18.413 / 23.155 / 26.223 | 56.68 | 120.92% |
| Runtime B | 5,504.67 | 102.77% | 103.94% | 17.470 / 22.067 / 25.297 | 57.05 | 121.40% |
| Shared C | 5,453.54 | 101.82% | 102.97% | 17.724 / 21.678 / 25.113 | 56.34 | 122.96% |

The final AOT build measurements were:

| Candidate | Source bytes | Lines | AOT bytes | Compile s |
| --- | ---: | ---: | ---: | ---: |
| Generated A | 1,764,694 | 54,795 | 7,929,344 | 6.822 |
| Runtime B | 817,702 | 28,747 | 7,834,624 | 5.450 |
| Shared C | 829,694 | 27,744 | 7,505,408 | 5.170 |

Candidate C source is 47.02% of A and 101.47% of B. Its AOT binary is 94.65%
of A and 95.80% of B. Its observed compile time is 75.78% of A and 94.87% of
B. It is materially closer to B than A in source growth while winning the
measured binary and compile dimensions.

At 100 routes, C d1/d3/d5 executables were all exactly 6,595,584 bytes; d0 was
6,575,104 and d10 was 6,596,096. This is practical evidence that unused depth
helpers do not materially survive AOT tree shaking, but it is not a symbol-level
proof and no custom binary analyzer was built.

## Isolated AOT microbenchmark

Each case ran five trials with observable checksums:

| Case | ns/call mean | median | min | max | stddev |
| --- | ---: | ---: | ---: | ---: | ---: |
| Direct handler | 1.393 | 1.389 | 1.389 | 1.401 | 0.005 |
| Generated d1 | 2.199 | 2.189 | 2.182 | 2.250 | 0.026 |
| Generated d3 | 5.770 | 5.758 | 5.734 | 5.830 | 0.032 |
| Runtime d1 | 9.443 | 9.516 | 9.303 | 9.561 | 0.114 |
| Runtime d3 | 17.389 | 17.268 | 17.113 | 18.027 | 0.329 |
| Shared d1 | 2.173 | 2.179 | 2.133 | 2.209 | 0.027 |
| Shared d3 | 5.739 | 5.735 | 5.691 | 5.794 | 0.033 |
| Shared d5 | 14.163 | 14.244 | 13.823 | 14.338 | 0.186 |

AOT may inline and devirtualize these tiny helpers. The result establishes that
C does not carry B's local traversal overhead and is indistinguishable from A
at d1/d3; HTTP remains authoritative.

## Maintainability comparison

| Concern | Generated A | Runtime B | Shared C |
| --- | --- | --- | --- |
| Generated code | Highest; routes × depth | Low, closure adapter per route | Low; pipeline identity per route |
| Shared runtime code | Minimal | One list traversal | Bounded depth helpers plus one async loop |
| Debugging/stacks | Explicit but very large | Central, includes closure/loop frames | Central enter/exit frames; direct handler frame retained |
| Sync complexity | Simple unrolled calls | Loop plus handler closure | Simple bounded helper calls |
| Async complexity | Generated per profile | One universal traversal | One connector and shared async boundary loop |
| Codegen complexity | Highest | Moderate | Moderate; depth name and direct handler connection |
| Binary behavior | Grows with deep replication | Stable but retains adapters | Best measured size; practical tree shaking |
| Extensibility | New shapes can duplicate code | Most runtime-flexible | Add measured shared shapes without erasing types |

C is the lowest-complexity design that retains A's closure-free typed fast
path while achieving B-like source growth. B remains useful as a diagnostic,
not as the selected production direction.

## Decision and remaining risks

ADR 0005 accepts Candidate C, the shared closure-free kernel. Confidence is
high for the internal execution boundary: correctness is exhaustive for the
modeled semantics, AOT diagnostics explain the local cost, and the decisive
1,000-route experiment covers throughput and growth together.

Remaining risks belong to the future public design rather than another kernel
phase: defining middleware types and response ownership, controlling the
number of async shape specializations, preserving useful stack traces with
real application middleware, deciding cancellation/streaming behavior, and
validating the HTTP foundation on native Linux. ADR 0002 remains Proposed.
