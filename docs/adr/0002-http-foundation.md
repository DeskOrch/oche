# ADR 0002: HTTP foundation

- Status: Proposed
- Date: 2026-08-27

## Context

Oche needs an HTTP foundation that remains close to Dart's runtime cost while
supporting compile-time-known routes and an enterprise-oriented developer
experience. The candidates tested so far are Relic 1.2.0 and a deliberately
narrow static-dispatch spike directly over `dart:io`.

The spike is evidence about dispatch overhead, executable size, startup, and
memory. It is not a production router and does not implement a public Oche API,
middleware, streaming policies, WebSocket abstractions, or security hardening.

## Options considered

### Relic as Oche's HTTP foundation

Relic supplies a typed request/response model, trie-based routing, middleware,
streaming, WebSocket support, connection lifecycle behavior, static assets, and
HTTP header handling. Oche could generate Relic registrations without runtime
reflection or package scanning.

This reduces Oche's correctness and maintenance burden. It also leaves Relic's
general routing and message-model costs on every request, adds about 1.6 MiB to
the current AOT executable, and uses materially more memory under the tested
load.

### Thin Oche runtime over `dart:io`

Oche could generate method-first and path-first dispatch with direct handler
calls. This fits routes known at compile time and keeps runtime discovery out of
the request path. The current spike remains effectively at the raw `dart:io`
baseline for throughput, idle RSS, peak RSS, and executable size on Windows.

The cost is ownership of framework-level semantics and a larger correctness
surface. Runtime composition and third-party integration also become deliberate
extension points rather than properties inherited from a general router.

## Phase 0.6 methodology

The earlier Windows sweep always ran raw `dart:io`, then Relic, then Oche static.
Phase 0.6 removed that systematic order by cycling through all six permutations
of the three implementations. Endpoint order uses the same deterministic cycle.
The first five permutations put every implementation and endpoint first, middle,
and last at least once. Every raw result records the complete orders, positions,
iteration, global sequence, suite run ID, and cooldown.

The clean confirmation run used:

- Windows native AOT executables, one isolate, and loopback `127.0.0.1`;
- concurrency 10, 100, and 500 on `/plaintext`, `/json`, and `/users/42`;
- five iterations, five seconds of separate warmup, 30 seconds measured, and a
  two-second cooldown between trials;
- `oha` 1.16.0 for every load trial;
- 135 retained raw trials and 27 five-sample aggregate groups;
- median, minimum, maximum, and population standard deviation for every numeric
  metric, plus median-based ratios against the matching raw group.

The recorded host was Windows 11 Pro build 26200, Windows x64, Dart 3.13.1,
Intel Xeon E5-2680 v4, with 28 logical CPUs visible. The aggregate and raw
evidence were generated under `benchmarks/results/phase06-windows-balanced/`.
Generated JSON is intentionally ignored by Git; the retained report summarizes
the evidence, while the cross-platform workflow uploads raw files as artifacts.

## Windows evidence

The following values are endpoint-means of the three per-endpoint medians. They
summarize the trend; the retained aggregate keeps every endpoint separate.

| Concurrency | Implementation | Requests/s | Relative to raw | p50 ms | p95 ms | p99 ms |
| ---: | --- | ---: | ---: | ---: | ---: | ---: |
| 10 | raw `dart:io` | 5,865.6 | 100.00% | 1.664 | 1.951 | 2.194 |
| 10 | Oche static | 5,900.4 | 100.60% | 1.661 | 1.945 | 2.205 |
| 10 | Relic | 4,756.5 | 81.09% | 2.028 | 2.720 | 3.097 |
| 100 | raw `dart:io` | 5,846.3 | 100.00% | 16.852 | 18.736 | 20.398 |
| 100 | Oche static | 5,866.9 | 100.38% | 16.740 | 18.586 | 20.506 |
| 100 | Relic | 4,919.6 | 84.17% | 20.131 | 22.817 | 24.776 |
| 500 | raw `dart:io` | 6,244.3 | 100.00% | 82.863 | 93.858 | 99.520 |
| 500 | Oche static | 6,273.2 | 100.46% | 82.482 | 93.108 | 97.053 |
| 500 | Relic | 4,515.9 | 72.32% | 110.696 | 117.608 | 123.998 |

Across individual endpoints, Oche static throughput was 99.53-101.77% of raw at
concurrency 10, 99.34-102.13% at 100, and 100.26-100.59% at 500. Relic was
79.12-82.26%, 83.14-85.91%, and 71.76-72.79%, respectively. Oche static p99 was
94.37-106.15% of raw at concurrency 10, 96.95-105.04% at 100, and
95.47-98.73% at 500, where lower is better. Relic p99 was 108.72-150.37% of raw
across the same groups.

| Concurrency | Implementation | Idle RSS MiB | Peak RSS MiB | Server CPU |
| ---: | --- | ---: | ---: | ---: |
| 10 | raw `dart:io` | 14.581 | 18.622 | 124.6% |
| 10 | Oche static | 14.572 | 18.479 | 124.8% |
| 10 | Relic | 17.065 | 53.092 | 125.6% |
| 100 | raw `dart:io` | 14.583 | 55.391 | 121.8% |
| 100 | Oche static | 14.572 | 55.065 | 122.5% |
| 100 | Relic | 17.074 | 90.436 | 124.9% |
| 500 | raw `dart:io` | 14.581 | 84.757 | 124.9% |
| 500 | Oche static | 14.569 | 84.254 | 124.0% |
| 500 | Relic | 17.070 | 122.948 | 126.4% |

Oche static idle RSS was 99.87-100.00% of raw and peak RSS was 97.57-100.75%.
Relic idle RSS was 117.01-117.15% of raw. Its peak RSS was 281.34-290.47% at
concurrency 10, 162.96-163.48% at 100, and 143.49-145.97% at 500. Server CPU
was similar across implementations even though Relic completed fewer requests;
100% represents one fully busy logical CPU and runtime helper threads can put
the whole-process value above 100%.

| Implementation | Native executable MiB | Relative to raw (lower is better) |
| --- | ---: | ---: |
| raw `dart:io` | 6.204 | 100.00% |
| Oche static | 6.171 | 99.46% |
| Relic | 7.789 | 125.55% |

Startup medians overlapped at roughly 308-327 ms, so the run does not establish
a startup ranking.

The previous fixed-order trend survived balancing. The largest change was a
5.94 percentage-point increase in Relic's `/users/42` throughput ratio at
concurrency 100; it still reached only 85.91% of raw. At concurrency 500 the
new ratios remained especially stable for Oche static and especially costly for
Relic.

Twenty of the 45 concurrency-500 trials reported tiny non-success fractions;
the worst was approximately 20 of 182,865 requests, or 99.989% success. Relic
also had one `/users/42`, concurrency-100 p99 spike to 101.689 ms; the other
four trials were 24.031-32.642 ms and the group median was 24.379 ms. These
effects do not alter the median ranking, but they limit claims about extreme
tail reliability on this loopback developer host.

## Linux validation

No usable Linux benchmark host was available. WSL listed only the stopped,
Docker-internal `docker-desktop` distribution at WSL version 2, and the Docker
Linux engine was not running. Treating that as native Linux, or fabricating a
result from it, would violate the environment rule.

The repository includes an exact Linux AOT script and a manually triggered
Windows/Ubuntu validation workflow. Until one of those produces retained Linux
evidence, cross-platform reproduction remains unknown.

## Architectural boundary

Choosing `dart:io` would not mean implementing HTTP from TCP sockets. Dart
continues to own `HttpServer`, `HttpRequest`, `HttpResponse`, WebSocket protocol
machinery, parsing, and connection behavior. A thin Oche layer may own routing,
middleware execution, request binding, response handling, error mapping, and
application lifecycle. It should delegate protocol behavior to `dart:io` and
avoid recreating a full HTTP server framework.

## Proposed disposition

Keep this ADR **Proposed** because Linux validation is outstanding. Within the
available Windows evidence, the recommended direction is a thin Oche runtime
over `dart:io`: it satisfies the stated 95%-of-raw throughput criterion on every
important workload, remains at raw's memory and binary-size baseline, and fits
Oche's compile-time/native-first model. Relic's correctness and maintenance
benefits remain real, but its measured request-path and footprint costs are too
large to make it the preferred foundation on this evidence.

Confidence is high for the Windows relative ranking and moderate for the
architectural recommendation overall. The remaining risks are Linux behavior,
separate-host load generation, broader route shapes, streaming and backpressure,
WebSockets, response/error semantics, security edge cases, and the maintenance
cost of keeping Oche's framework layer thin.

The next architectural experiment, after review and only as Phase 1 work,
should compare two generated static-dispatch kernels for mixed literal and
parameterized route sets at 10, 100, and 1,000 routes. Keep handlers and
`dart:io` transport identical; validate precedence, parameter failures, 404,
405, and response/error mapping; measure AOT end-to-end throughput, p99, RSS,
and code size against raw dispatch. This would select the internal kernel
boundary and routing shape without introducing public annotations, dependency
injection, or other application-framework APIs.
