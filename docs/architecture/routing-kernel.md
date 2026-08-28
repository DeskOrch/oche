# Generated routing kernel

Phase 1A evaluates internal code shapes that a future Oche generator could
emit. It does not define an application API, annotations, a production code
generator, or a general middleware abstraction. The experiment keeps one
shared `dart:io` transport, response mapper, handler set, route model, and
benchmark harness so only dispatch differs.

The route-count values in this experiment mean distinct path templates.
Multiple methods on one path share one template. The first ten templates cover
the required semantic routes plus the internal error route; deterministic
literal, one-parameter, and two-parameter shapes fill the 100- and 1,000-route
sets. Generated files are disposable benchmark artifacts and are ignored by
Git.

## Candidate A: segmented tree

The tree candidate switches first on segment count and then follows generated
literal branches. A literal branch is emitted before a parameter branch at the
same depth. Parameter leaves parse values and invoke typed top-level handlers
directly. Synthetic route families use a generated switch on their stable
literal route identifier.

This shape mirrors the route declaration structure, is straightforward to
inspect, and does no runtime registration, reflection, regular-expression
matching, or handler lookup. Its main cost is verbose generated source: deeply
nested or very wide applications can produce many branch lines.

## Candidate B: indexed/hash-assisted

The indexed candidate also partitions by segment count. It computes a small
FNV-style integer hash from only the literal positions that define a route
shape, then switches on precomputed constants. Every hash case includes literal
equality guards, so a collision cannot resolve to the wrong route. Parameter
segments are excluded from skeleton hashes, parsed at the selected leaf, and
passed directly to typed handlers.

This shape trades nested branch comparisons for hash work. The final
formatter-safe output did not reduce source size or lines at the tested route
counts, and the generator is more complex; collision guards are mandatory for
correctness and security. It is not a `Map<String, Handler>` and does not build
keys or register handlers at runtime.

## Resolution contract

Both candidates use the same deterministic policy:

1. Validate the decoded URI path and select the exact segment count.
2. Prefer a matching literal segment over a parameter segment.
3. Match the entire path; no prefix, wildcard, or catch-all match exists.
4. Once a path exists, dispatch its HTTP method.
5. Return 405 for an unsupported method and emit `Allow` in stable
   `GET, POST, PUT, PATCH, DELETE` subset order.
6. Return 404 only when no valid complete path exists.

Consequently `/users/search` is never interpreted as `/users/{id}`, and
`/users`, `/users/42`, and `/users/42/orders/91` remain different leaves.
Literal matching is case-sensitive.

The experiment recognizes GET, POST, PUT, PATCH, and DELETE. Handler calls are
statically named functions. Integer parameters use `int.tryParse` at the leaf;
string parameters are passed directly. Multiple values are local variables,
not a per-request `Map<String, String>`.

## Error and response mapping

The shared transport catches only around route dispatch and maps outcomes to a
small internal contract:

| Outcome | HTTP result |
| --- | --- |
| Invalid declared integer parameter | 400 JSON error |
| No complete path | 404 plain text |
| Existing path, unsupported method | 405 plus stable `Allow` |
| Expected internal experiment exception | 409 generic JSON error |
| Any unexpected handler exception | 500 generic JSON error |

Expected and unexpected exception messages and stack traces never enter the
response. These internal types are experimental and are not a proposed public
exception API.

## URI and normalization decision

Query strings are separate in `Uri` and do not participate in path matching.
The dispatcher does not normalize trailing or duplicate slashes: except for the
root itself, a trailing slash is rejected, and any duplicate slash is rejected.
Decoded slash, backslash, NUL, and surviving `.` or `..` segments are rejected.

Dart owns URI parsing and percent decoding. In particular, Dart can normalize
percent-encoded dot segments before dispatch; the kernel accepts that standard
`Uri` result rather than implementing a second decoder. Invalid request-target
syntax is left to `dart:io`. Literal comparisons always run on decoded,
validated segments, and encoded slash or backslash cannot cross a route
boundary. The experiment intentionally does not define application-level URL
canonicalization.

## Measurement design

The deterministic generator emits both candidates at 10, 100, and 1,000 path
templates. Each generated program can run as an HTTP server or execute a
90%-hit/10%-miss isolated lookup stream. The primary HTTP suite compares the two
candidates with a hand-written raw `dart:io` lower bound through identical
transport and handlers.

The earlier `oche_static` program remains in the repository as Phase 0.6
evidence, but its three-route contract cannot serve the nested Phase 1A
workloads. Reusing it here would compare different semantics, so the Phase 1A
matrix uses the new hand-written raw kernel baseline instead.

Success workloads are literal, one typed parameter, and two typed parameters.
Error workloads are method mismatch, invalid typed parameter, and unexpected
handler failure; they are scheduled and aggregated separately. Every raw HTTP
trial records route count, method, expected status, workload, full balanced
implementation/workload order, order positions, compile observation, source
size, environment, and the Phase 0.6 metrics. Aggregate groups report ratios
against raw `dart:io` and against the matching ten-route variant.

The required AOT matrix uses concurrency 10, 100, and 500, five seconds of
warmup, 30 seconds measured, five iterations, and two seconds of cooldown.
Compile durations are noisy wall-clock observations from one developer machine,
not portable compiler benchmarks.

The HTTP route-count comparison intentionally keeps the same three semantic
endpoints at every size; it measures whether adding unrelated generated routes
slows established hot routes. The isolated stream distributes hits across the
generated table and therefore covers late synthetic branches as well. This
combination does not model every possible production route shape or instruction
cache pathology.

## Native-Windows AOT findings

The recorded success run (`2026-08-27T23-10-27-951515Z`) and error run
(`2026-08-28T15-00-00-000000Z`) completed 405 trials each. Every group contains
five repetitions. The tables below average the three workload-level medians at
each route-count/concurrency point; the retained aggregates preserve every
workload separately.

| Routes | Concurrency | Raw req/s | Tree req/s (% raw) | Indexed req/s (% raw) | Raw p99 ms | Tree p99 ms | Indexed p99 ms |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 10 | 10 | 5,635.4 | 5,718.1 (101.48%) | 5,766.8 (102.36%) | 2.464 | 2.366 | 2.292 |
| 10 | 100 | 5,858.7 | 5,855.6 (99.95%) | 5,860.6 (100.03%) | 19.840 | 19.652 | 19.219 |
| 10 | 500 | 6,158.8 | 6,191.4 (100.53%) | 6,203.1 (100.72%) | 101.325 | 99.490 | 98.179 |
| 100 | 10 | 5,874.7 | 5,932.1 (100.99%) | 5,893.4 (100.33%) | 2.185 | 2.116 | 2.195 |
| 100 | 100 | 5,951.5 | 5,941.7 (99.84%) | 5,966.8 (100.26%) | 18.828 | 18.950 | 18.879 |
| 100 | 500 | 5,878.6 | 5,982.0 (101.76%) | 5,945.5 (101.13%) | 112.090 | 109.862 | 110.205 |
| 1,000 | 10 | 5,604.7 | 5,486.8 (97.94%) | 5,552.3 (99.11%) | 2.519 | 2.683 | 2.618 |
| 1,000 | 100 | 5,803.3 | 5,709.7 (98.39%) | 5,788.2 (99.74%) | 21.299 | 22.813 | 21.240 |
| 1,000 | 500 | 6,041.6 | 6,047.8 (100.10%) | 6,018.1 (99.61%) | 105.007 | 105.681 | 109.079 |

Both candidates are effectively tied with transport noise in end-to-end HTTP.
Across the 27 successful workload groups, tree throughput averaged 100.11% of
raw and never fell below 96.59%. Indexed averaged 100.37%, but its 1,000-route
literal/c=10 group was 94.69% of raw, with p99 at 117.47% of raw. That single
miss is noisy (the five indexed trials had a 376.8 req/s standard deviation),
but it prevents claiming that indexed met the 95% budget in every group. Tree
met it everywhere.

At concurrency 100, the average p50/p95/p99 values were 16.825/18.337/19.652
ms for tree and 16.837/18.232/19.219 ms for indexed at 10 routes;
16.621/17.775/18.950 ms and 16.578/17.662/18.879 ms at 100 routes; and
17.103/19.566/22.813 ms and 16.934/18.783/21.240 ms at 1,000 routes. These
differences do not establish an HTTP latency winner.

Average throughput relative to each implementation's ten-route variant was
100.62%/97.05% for tree at 100/1,000 routes and 99.96%/97.36% for indexed.
The raw lower bound itself measured 100.43%/98.88%, showing that most of the
small end-to-end shift is not route lookup alone.

Idle RSS medians ranged from 14.637-15.020 MiB for tree, 14.645-15.066 MiB for
indexed, and 14.508-14.531 MiB for raw. Peak RSS ranges were 18.895-86.863 MiB,
18.887-87.316 MiB, and 18.762-85.848 MiB respectively. Server CPU ranges were
117.40-126.28%, 117.88-126.54%, and 120.16-127.32%; startup ranges were
300.47-323.44 ms, 300.45-330.30 ms, and 300.92-326.71 ms. No material RSS,
CPU-efficiency, or startup distinction emerged between the candidates.

All 405 error-path trials returned only their expected status (400, 405, or
500), so every one of the 81 aggregate groups has success rate 1.0. Candidate
throughput averaged between 100.01% and 101.05% of matching raw groups across
the three error workloads. Error mapping therefore did not expose a separate
performance concern.

## Isolated lookup findings

Each AOT executable ran a deterministic 90%-hit/10%-miss stream for five
million lookups per iteration, five iterations. Unlike the HTTP hot-endpoint
test, hits are distributed across the generated table.

| Candidate | Routes | Lookups/s | ns/lookup | Relative to 10 routes |
| --- | ---: | ---: | ---: | ---: |
| Tree | 10 | 3,692,965 | 270.79 | 100.00% |
| Tree | 100 | 1,653,117 | 604.92 | 44.76% |
| Tree | 1,000 | 589,251 | 1,697.07 | 15.96% |
| Indexed | 10 | 3,143,852 | 318.08 | 100.00% |
| Indexed | 100 | 1,608,910 | 621.54 | 51.18% |
| Indexed | 1,000 | 1,218,332 | 820.79 | 38.75% |

Tree is faster at 10 and 100 routes, while indexed is 2.07 times faster at
1,000. The tree's 6.27-times latency growth is the main pathological case found
in this phase. Its absolute 1.70 microsecond lookup remained small enough that
the complete HTTP matrix did not show a corresponding material regression,
but a future full-table production workload must be profiled before assuming
the result generalizes beyond 1,000 routes.

## Generated-code growth on Windows

The recorded native-Windows build used Dart 3.13.1. MiB values use 1,048,576
bytes.

| Candidate | Routes | Source bytes | Lines | AOT bytes | Compile ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| Tree | 10 | 3,804 | 116 | 6,577,664 | 2,776 |
| Tree | 100 | 41,502 | 1,028 | 6,630,400 | 2,898 |
| Tree | 1,000 | 417,693 | 10,028 | 6,990,336 | 4,524 |
| Indexed | 10 | 5,006 | 151 | 6,578,176 | 2,771 |
| Indexed | 100 | 45,716 | 1,108 | 6,631,424 | 2,944 |
| Indexed | 1,000 | 455,022 | 10,708 | 7,044,096 | 6,248 |

From 10 to 1,000 templates, the tree executable grew 412,672 bytes and the
indexed executable grew 465,920 bytes. At 1,000 routes, indexed used 37,329
more source bytes, 680 more lines, and 53,760 more executable bytes; its single
observed compilation also took about 1.72 seconds longer. Neither source nor
native size grew explosively in this range; both remain approximately linear
generated-source designs.

The HTTP matrix used the same generated AST before formatting was enforced in
the benchmark tooling. The final formatter-safe regeneration changed only
whitespace/source locations, then the build and isolated lookup measurements
above were repeated. The large-table lookup conclusion was unchanged. HTTP
numbers remain labeled with their original run IDs rather than being silently
attributed to the later build.

## Controlled middleware experiment

The optional experiment compares 0, 1, and 5 trivial stages as either a
pre-generated direct call chain or a traversal over a prebuilt runtime function
list. It performs no HTTP work and exposes no API. Its result must not be used
to choose a router; it only estimates the invocation cost that a later, scoped
middleware design would need to validate end to end.

The observed direct-chain medians for 0/1/5 stages were 6.76/9.62/8.33 ns per
call; runtime-list medians were 9.70/10.91/13.89 ns. The non-monotonic direct
result is expected for these deliberately trivial synchronous XOR stages: AOT
can inline and collapse them. This only supports keeping generated direct
chains available for a later experiment; it is not an estimate for real async
middleware.

No reliable allocation profile was collected. Both candidates share Dart's
`Uri.pathSegments`, HTTP response encoding, and handler response objects, while
generated binding demonstrably avoids a parameter-map allocation. RSS and CPU
measurements can expose large aggregate differences but cannot attribute
individual allocations.

## Maintainability assessment

The tree candidate has the smaller correctness surface and makes precedence
visible in ordinary control flow. The indexed candidate is still deterministic
and safe because of its guards, but needs hash generation, collision handling,
literal-position bookkeeping, and more careful generated-code review.

## Selection

Use the generated segmented tree for Oche's next internal kernel experiment.
It is the only candidate that cleared the HTTP throughput budget in every
successful group, has the smaller correctness surface, compiles faster at
1,000 routes, and produces the slightly smaller large executable. The indexed
candidate's repeatable large-table lookup advantage is real, but it did not
translate into end-to-end HTTP benefit in this experiment and does not yet
justify hashing, collision buckets, and literal-position bookkeeping.

Confidence is medium-high for the tested 10-1,000-route Windows shapes, and
lower outside them because this is one loopback host and three hot endpoints.
The smallest sensible Phase 1B experiment is an internal generated
handler-adapter over the selected tree, retaining direct typed arguments and
the established response/error mapper. It should not introduce a public API.
ADR 0003 records this decision as Accepted. ADR 0002 remains Proposed because
Phase 1A does not supply independent Linux evidence for the HTTP-foundation
decision.
