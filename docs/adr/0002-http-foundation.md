# ADR 0002: HTTP foundation

- Status: Proposed
- Date: 2026-08-27

## Context

Oche needs an HTTP foundation that remains close to Dart's runtime cost while
supporting compile-time-known routes and an enterprise-oriented developer
experience. Phase 0 established raw `dart:io` and Relic baselines. Phase 0.5
adds a deliberately narrow static-dispatch spike directly over `dart:io`.

The spike is evidence about routing shape, executable size, startup, and idle
memory. It is not a production router and does not implement middleware,
streaming policies, WebSockets, protocol edge cases, or security hardening.

## Options

### Option A: Relic as Oche's HTTP foundation

Relic supplies a typed request/response model, trie-based routing, middleware,
streaming, WebSocket support, connection lifecycle behavior, static assets, and
HTTP header handling. Oche could generate direct Relic route registration and
handlers at compile time without runtime reflection or package scanning.

Trade-offs:

- **Performance:** framework-specific routing and message-model overhead remains
  on every request. HTTP throughput and latency have not yet been measured in
  this environment.
- **Memory and binary size:** current Windows AOT measurements show about 17.07
  MiB idle RSS and a 7.789 MiB binary, versus about 14.57–14.59 MiB and
  6.17–6.20 MiB for the direct `dart:io` implementations.
- **HTTP correctness and maintenance:** Relic owns substantially more tested
  HTTP behavior, reducing Oche's correctness and security burden.
- **Routing flexibility:** its general router and middleware model support more
  runtime composition than a generated static table may require, but also cover
  cases future Oche applications may need.
- **Streaming, WebSockets, and future HTTP features:** already represented in
  the foundation rather than becoming Oche-owned protocol work.
- **Developer ergonomics:** typed APIs are available now. Oche would still need
  compile-time tooling and its own ergonomic layer.
- **Compile-time generation:** compatible, although generated routes would
  target Relic abstractions rather than the shortest possible dispatch path.

### Option B: Thin Oche runtime directly over `dart:io`

Oche could generate method-first, path-first control flow and direct handler
calls. The Phase 0.5 server uses exact string switches for literal routes and a
single validated prefix/segment extraction for `/users/{id}`.

Trade-offs:

- **Performance:** this has the shortest visible dispatch path, but external
  HTTP throughput and latency evidence is unavailable. Microbenchmark lookup
  speed must not be treated as end-to-end HTTP speed.
- **Memory and binary size:** the current spike is 6.171 MiB and about 14.57 MiB
  idle RSS, close to the raw lower-bound reference.
- **HTTP correctness and maintenance:** Oche would own response semantics,
  method negotiation, headers, streaming integration, errors, connection
  lifecycle, and a growing set of edge cases. That cost can dominate a modest
  throughput advantage.
- **Routing flexibility:** generated static dispatch suits routes known at
  compile time but makes runtime composition and third-party integrations more
  deliberate.
- **Streaming, WebSockets, and future HTTP features:** `dart:io` exposes lower
  level primitives, but Oche would need to define and maintain safe ergonomic
  APIs without recreating a full server framework.
- **Developer ergonomics:** the benchmark code is intentionally not ergonomic.
  Any eventual API must prove that its abstractions do not erase the measured
  advantage.
- **Compile-time generation:** a natural fit; generated code can emit direct
  branches, segmented dispatch, or static lookup data with no runtime discovery.

## Evidence collected

All three AOT servers pass the same endpoint contract, including invalid route
parameters, 404 behavior, and 405 method negotiation. Five process-only trials
per endpoint found startup medians between 349.6 and 364.6 ms with outliers on
all implementations. That is insufficient to distinguish startup behavior.

Executable sizes on the current Windows x64 host:

| Implementation | Bytes | MiB |
| --- | ---: | ---: |
| raw `dart:io` | 6,505,472 | 6.204 |
| Relic | 8,167,424 | 7.789 |
| Oche static spike | 6,470,656 | 6.171 |

Median idle RSS across endpoints is approximately 14.58 MiB for raw `dart:io`,
17.07 MiB for Relic, and 14.57 MiB for the static spike.

A separate AOT lookup microbenchmark used 90% hits and 10% misses. At 1,000
routes, median lookup throughput was approximately 0.44 million/s for a full
linear scan, 1.44 million/s for a ten-way segmented leaf scan, and 41.51
million/s for a prebuilt hash table. This rejects unbounded leaf scanning for
large route tables in this synthetic shape. It does not establish that a hash
table is the final router or measure HTTP request throughput.

No supported external load generator was installed. Requests/second, p50/p95/
p99 latency, load RSS, and load CPU remain unknown.

## Proposed disposition

Keep this ADR **Proposed**. The evidence shows that a thin static runtime can
match raw `dart:io` binary size and idle memory, and that static lookup strategy
matters at larger route counts. It does not show whether the end-to-end savings
over Relic are material enough to justify taking ownership of higher-level HTTP
behavior.

The next evidence should be five repeated AOT trials for all endpoints on a
representative Linux host using the same external load generator, followed by
targeted CPU/allocation profiling only where it explains an observed gap. If
the gap is small, prefer Relic's correctness and maintenance benefits. If it is
large and attributable to unavoidable Relic abstractions, investigate a narrow
generated router/runtime boundary without reimplementing HTTP parsing.
