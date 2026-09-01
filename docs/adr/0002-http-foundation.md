# ADR 0002: HTTP foundation

- Status: Accepted
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

The outstanding Linux gate completed on Ubuntu 26.04.1 LTS with kernel
7.0.0-30-generic in an x86_64 Hyper-V VM. This was a real Linux guest, not WSL
or a container. The guest exposed eight logical Intel Xeon E5-2680 v4 CPUs and
7.248 GiB RAM. It used Dart 3.13.1 stable, `oha` 1.15.0, and loopback
`127.0.0.1:8080`.

Validation commit `41963e4` has Phase 2A commit `12a9cf8` as its parent. It adds
only the reproducible validation application, harness, tests, and documentation;
no framework package changed between those revisions. The Oche candidate was
the real public annotated application compiled from production-generated code,
not `oche_static` or another internal spike. Its recorded generated-source
SHA-256,
`37e2fa450bc15b060025f3407a2ab4210be81bc90569f7b5a628662c02b2847b`,
matches the tracked production-generated `application.oche.dart`.

The balanced AOT matrix compared raw `dart:io`, Relic, and public Oche across
synchronous, asynchronous, and typed-`int` workloads at concurrency 10, 100,
and 500. Every group used five iterations, a five-second warmup, 30-second
measurement, and two-second cooldown. All 135 trials completed with a 1.0 HTTP
success rate, producing 27 five-trial groups.

An independent raw-trial review reproduced the aggregate exactly and retained
every trial. All nine public-Oche workload/concurrency groups meet the central
95%-of-raw throughput criterion:

| Measure | Linux result |
| --- | ---: |
| Median of the nine group-median Oche/raw ratios | 102.03% |
| Range of group-median Oche/raw ratios | 100.07-105.20% |
| Worst group-median result | 100.07% |
| Range of same-iteration paired-median ratios | 98.44-103.56% |
| Worst paired diagnostic (`async`, concurrency 500) | 98.44% |

The `async`/500 group illustrates temporal and order noise: its independently
aggregated median ratio is 105.20%, while the more conservative median of
same-iteration ratios is 98.44%. Both pass the budget, but the higher value is
not evidence that Oche is architecturally faster than raw `dart:io`. Within the
observed noise, the candidates are performance-equivalent for the selected
foundation decision.

Oche median p99 was 95.44-102.47% of matching raw p99, idle RSS was
97.00-100.62% of raw, and CPU and startup distributions did not show a
systematic regression or establish a winner. Peak RSS normally tracked raw.
The `async`/100 raw and Oche trials crossed two different heap-growth states,
so that group's bimodal peak RSS must not be used to claim an Oche memory
advantage. The Oche AOT executable was 6,887,328 bytes versus 6,882,896 bytes
for raw, an overhead of 4,432 bytes or 0.064%.

The local validation archive `oche-linux-validation.zip` contains 135 per-trial
JSON files and the aggregate. It is intentionally not versioned and does not
contain the original `oha` transcripts, console logs, AOT binaries, referenced
public-build manifest, generated source, or explicit Git revision and
dirty-worktree metadata. The raw JSON and matching generated-source hash are
sufficient for this performance decision, but future archives should retain
those additional provenance artifacts.

This single-VM loopback run validates the absence of a material Linux-specific
architectural regression; it is not a bare-metal capacity claim. Server and
load generator shared eight virtual CPUs, Hyper-V host scheduling can influence
absolute results, five permutations leave candidate position partially
confounded with iteration, and the loopback topology does not replace a
separate-host production load test.

### Acceptance criteria

| Criterion | Result | Evidence |
| --- | --- | --- |
| At least 95% of raw throughput on every important workload | **PASS** | 9/9 groups pass; worst group median 100.07%, worst paired diagnostic 98.44% |
| No material tail-latency regression | **PASS** | Median p99 is 95.44-102.47% of raw without a systematic adverse pattern |
| Remain near raw's resource and AOT-size baseline | **PASS** | Idle RSS and CPU track raw; binary overhead is 0.064%; bimodal peak RSS is retained as a caveat |
| Independent Linux reproduction | **PASS** | Complete balanced AOT matrix on an Ubuntu Hyper-V guest, with all 135 trials successful |
| Exercise the production public architecture | **PASS** | Public annotated application, production generated-source hash, and no package changes after `12a9cf8` |

## Architectural boundary

Choosing `dart:io` would not mean implementing HTTP from TCP sockets. Dart
continues to own `HttpServer`, `HttpRequest`, `HttpResponse`, WebSocket protocol
machinery, parsing, and connection behavior. A thin Oche layer may own routing,
middleware execution, request binding, response handling, error mapping, and
application lifecycle. It should delegate protocol behavior to `dart:io` and
avoid recreating a full HTTP server framework.

## Decision

Accept a thin Oche runtime over `dart:io` as the HTTP foundation. Windows and
Linux independently show that the generated/runtime architecture meets the
95%-of-raw throughput criterion on every important workload, remains near raw's
resource and AOT-size baseline, and fits Oche's compile-time/native-first model.
Linux reproduces the absence of a material architectural regression, so the
previous cross-platform evidence gap is closed.

Relic's correctness and maintenance benefits remain real, but its measured
request-path and footprint costs do not make it the preferred foundation. This
decision does not mean reimplementing HTTP from TCP sockets: Dart continues to
own protocol parsing and connection machinery, while Oche owns the deliberately
thin framework semantics described above.

Confidence is high for the relative ranking and architectural direction within
the tested Windows and Linux loopback environments. Remaining risks include
separate-host and bare-metal validation, broader traffic and route shapes,
streaming and backpressure, WebSockets, security edge cases, allocation
profiling, and the maintenance cost of keeping the framework layer thin. These
limits constrain the scope of the evidence but do not require reopening the
selected HTTP foundation.
