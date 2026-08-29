# Internal handler execution contract

## Scope

Phase 1B evaluates the private boundary between the accepted generated
segmented route tree and application-shaped Dart methods. It does not define
controllers, annotations, dependency injection, middleware, serialization, or
any public Oche API. Every type under `benchmarks/handler_execution` may be
deleted or redesigned in a later phase and is not exported by `package:oche`.

The experimental path is:

```text
HttpRequest
  -> generated segmented tree
  -> generated typed local binding
  -> generated specialized leaf adapter
  -> direct top-level or statically known instance method
  -> result-type-specific mapping
  -> HttpResponse
```

Handler execution begins after method/path selection and successful typed
binding. It ends when the result writer has configured and closed the response,
or when the error boundary has written a mapped failure. Future generated
middleware can wrap this interval without changing the handler signature.

## Compared strategies

### Phase 1A direct-response baseline

The generated tree invokes an application-shaped handler and creates the same
kind of status/content-type/body value used by the Phase 1A kernel. One shared
writer applies that value to `HttpResponse`. This is the primary 100% baseline
for incremental Phase 1B cost.

### Generated specialized adapter

Each leaf statically knows the handler return type. A synchronous `String`, byte
payload, `void`, or `UserResult` follows a synchronous mapping function and does
not allocate a `Future` merely for normalization. A handler returning
`Future<T>` enters a type-specific async helper which awaits the future, maps
`T`, and handles asynchronous failure. Calls remain direct, for example:

```dart
final id = int.tryParse(segments[1]);
if (id == null) {
  writeInvalidParameter(request, 'id');
  return;
}
writeUserResult(request, userResultHandler(id));
```

The generated router contains no generic closure registry or dynamic argument
container.

### Uniform internal adapter

The credible convenience alternative preserves generated typed argument
binding and direct calls but passes values through a common
`FutureOr<Object?>` discriminator and maps them by an internal result-kind enum.
It then creates an intermediate response value. `Future<void>` uses a dedicated
helper because a `void` expression is not a useful object value. This candidate
does not intentionally add parameter maps, argument lists, reflection, or
runtime registration.

## Sync and async contract

Generated synchronous leaves return `void` after writing the response. They do
not use `async`, `Future.sync`, or `Future.value`. A synchronous throw reaches
one shared dispatch boundary in the server listener.

Generated asynchronous leaves start the application future and pass it to a
typed helper. The helper owns the `await`, result mapping, response close, and
post-await exception boundary. An immediately completed future and a future
with `Future<void>.delayed(Duration.zero)` are measured separately; the latter
introduces one deterministic event-loop boundary without an artificial timer or
external I/O.

`FutureOr` is used only by the uniform comparison and the isolated
microbenchmark. It is not part of the selected specialized contract.

## Typed arguments and instances

The generated tree binds and validates parameters into locals and invokes:

```text
handler()
handler(id)
handler(userId, orderId)
handler(sku, id)
controller.findById(id)
```

There is no request-parameter map. The benchmark controller is constructed once
at startup and referenced by a statically known final variable. No service
lookup occurs per request. Top-level and instance calls use the same result
mapping contract.

## Request access

Handlers can receive raw `HttpRequest` directly. The alternative
`ExperimentalRequestView` stores only that reference and forwards method, URI,
headers, and cookies lazily. It does not eagerly copy headers, URI, query
parameters, cookies, or body. It does, however, create one wrapper object each
time a generated leaf constructs it. It remains experimental unless HTTP
evidence shows value beyond abstraction alone.

## Result mapping

The experiment maps:

| Handler result | HTTP mapping |
| --- | --- |
| `String` text | 200, `text/plain; charset=utf-8` |
| JSON-shaped `String` | 200, `application/json; charset=utf-8` |
| `List<int>` | 200, `application/octet-stream` |
| `void` / `Future<void>` | 204, empty body, `dart:io` default text content type |
| `UserResult` | 200 JSON through a manual generated-equivalent serializer |

The specialized candidate writes each category directly. The uniform and Phase
1A baselines route through `ExperimentalHandlerResponse`. `UserResult` and that
response value are benchmark-only types, not proposed framework APIs.

## Error boundary

Binding failures are generated 400 responses and never invoke a handler.
Unknown routes return 404; known paths with a wrong method return 405 and an
exact `Allow` header. `ExpectedHandlerException` maps to the experiment's 409.
All other synchronous and asynchronous failures map to a fixed 500 JSON body.
Neither boundary writes exception messages or stack traces to the client.

One shared try/catch around synchronous dispatch is cheaper and simpler than a
generated try/catch at every leaf. Async helpers require their own catch after
`await`; a listener-level synchronous catch cannot observe a later future error.

## Allocation observations

Source inspection directly establishes:

- typed arguments remain locals; no lists, maps, or parameter containers are
  created;
- specialized synchronous paths do not create a future or intermediate
  response object;
- string and structured mapping still allocates encoded body bytes;
- `UserResult` is an application result allocation;
- the request-view route creates one wrapper;
- uniform mapping creates an intermediate response value;
- every naturally asynchronous handler creates/returns its application future.

No reliable per-request allocation profiler was collected on this Windows AOT
host. These observations must not be read as a zero-allocation claim.

## Isolated AOT findings

Five-trial medians on the Phase 1B Windows host showed approximately 1.37 ns
for a direct top-level call, 2.98 ns for a direct instance call, 1.29 ns for a
tear-off, 1.28-1.29 ns for specialized/uniform synchronous invocation, and
3.13 ns for a non-throwing try/catch. `FutureOr` discrimination of a synchronous
value was about 1.37 ns. Creating and encoding the Phase 1A-style intermediate
result was about 197 ns. Awaiting the immediately completed application future
was about 213 ns, while one real event-loop boundary was about 15.5
microseconds. The AOT optimizer can inline or devirtualize these tiny loops, so
sub-nanosecond ordering differences are not interpreted as costs.

These nanosecond results establish that direct calls, instance calls, tear-offs,
and `FutureOr` discrimination are not architectural differentiators in
isolation. In particular, this microbenchmark does not isolate tear-off binary
size, allocation count, or HTTP p99. It therefore supports only the narrow
throughput observation and does not replace the end-to-end AOT HTTP evidence.

## End-to-end Windows AOT evidence

The development host was native Windows 11 Pro build 26200 on an Intel Xeon
E5-2680 v4, with 28 logical CPUs, Dart 3.13.1 AOT, one server isolate, and
`oha` 1.16.0 on loopback. Generated JSON remains local and ignored by Git.

The broad synchronous screening matrix covered 10, 100, and 1,000 routes;
concurrency 10, 100, and 500; all three synchronous workloads; all four
implementations; and five balanced repetitions: 540 trials. To keep that local
matrix practical it used one second of warmup, five measured seconds, and no
cooldown. The reproducible scripts retain the target five-second warmup,
30-second measurement, five repetitions, and two-second cooldown.

The specialized candidate produced the following absolute values. Each row is
the mean of the three workload-level medians; the aggregate retains the
workloads separately.

| Routes | Concurrency | Requests/s | p50 ms | p95 ms | p99 ms |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 10 | 10 | 5,838.6 | 1.678 | 1.948 | 2.237 |
| 10 | 100 | 5,691.4 | 17.108 | 19.568 | 22.906 |
| 10 | 500 | 5,905.2 | 80.980 | 97.341 | 147.371 |
| 100 | 10 | 5,805.2 | 1.680 | 1.969 | 2.286 |
| 100 | 100 | 5,789.9 | 16.925 | 18.568 | 21.708 |
| 100 | 500 | 5,947.1 | 80.458 | 96.525 | 171.428 |
| 1,000 | 10 | 5,758.1 | 1.691 | 1.992 | 2.295 |
| 1,000 | 100 | 5,622.5 | 17.253 | 20.264 | 24.668 |
| 1,000 | 500 | 5,719.4 | 83.031 | 104.517 | 174.184 |

Across the 27 synchronous groups, specialized throughput averaged 100.79% of
the matching Phase 1A direct median and 100.41% of raw. The ranges were
97.30-110.52% and 96.36-107.90%. Uniform averaged 101.06% of Phase 1A direct
and 100.67% of raw, with ranges of 97.35-107.70% and 97.52-105.15%. These
overlapping results do not establish an end-to-end throughput winner.

Three short specialized groups were marginally below the primary 98% target.
The worst was the one-`int` handler at 100 routes and concurrency 500, at
97.30%. A focused run of that exact group used the target 5/30/5/2-second
protocol and balanced the four implementation positions. Its medians were:

| Implementation | Requests/s | p50 ms | p95 ms | p99 ms | Peak RSS MiB | Server CPU |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Raw `dart:io` | 5,972.45 | 85.820 | 99.620 | 107.323 | 84.008 | 121.02% |
| Phase 1A direct | 6,064.25 | 84.341 | 98.552 | 107.375 | 84.137 | 120.17% |
| Specialized | 6,007.96 | 84.516 | 100.727 | 112.200 | 83.359 | 119.20% |
| Uniform | 6,205.16 | 82.893 | 94.616 | 100.303 | 85.145 | 121.33% |

Specialized therefore reached 99.07% of Phase 1A direct and 100.59% of raw in
the longer diagnostic, satisfying the primary 98% and long-term 95% budgets.
The p99 differences are not treated as architectural because the candidates'
five-trial ranges overlap and loopback load competes with the server.

At 100 routes and concurrency 100, the abbreviated async/request screening
showed specialized at 100.79% of Phase 1A direct for an immediately completed
future, 100.63% for one real event-loop boundary, 102.57% for the instance
method, 100.06% for raw-request access, 98.84% for the lazy request view, and
99.57% for structured-result mapping. The same groups were all above 100% of
raw except the comparison-specific baseline noise. The request view delivered
99.07% of specialized raw-request throughput. Across all implementations its
within-implementation ratio ranged from 98.19% to 100.69%, so HTTP evidence
shows no consistent difference; source inspection still establishes its one
wrapper allocation per invocation.

Synchronous idle RSS ranges were 14.512-14.840 MiB for specialized and
14.523-14.832 MiB for uniform. Peak RSS ranges were 18.758-84.000 MiB and
18.676-85.672 MiB; server CPU ranges were 109.21-120.10% and 109.54-121.30%.
They overlap the raw and Phase 1A ranges. A server value above 100% represents
whole-process CPU time, including runtime helper threads.

## Source, compile, and binary growth

The final local AOT build measurements were:

| Candidate | Routes | Generated bytes | Lines | Compile ms | AOT MiB |
| --- | ---: | ---: | ---: | ---: | ---: |
| Phase 1A direct | 10 | 6,170 | 234 | 2,847.6 | 6.208 |
| Specialized | 10 | 5,854 | 222 | 2,698.1 | 6.208 |
| Uniform | 10 | 6,664 | 272 | 2,722.2 | 6.208 |
| Phase 1A direct | 100 | 35,536 | 1,072 | 2,934.3 | 6.227 |
| Specialized | 100 | 35,187 | 1,057 | 2,831.1 | 6.226 |
| Uniform | 100 | 36,048 | 1,111 | 2,854.2 | 6.226 |
| Phase 1A direct | 1,000 | 325,327 | 9,172 | 4,014.8 | 6.529 |
| Specialized | 1,000 | 324,978 | 9,157 | 4,025.2 | 6.529 |
| Uniform | 1,000 | 325,839 | 9,211 | 4,067.6 | 6.529 |

Raw `dart:io` was 6.207 MiB. Specialized and uniform executables were identical
in byte size at every route count and 512 bytes smaller than their matching
Phase 1A binaries. Compile-time differences are single observations and not a
ranking. Specialized consistently emitted 810-861 fewer source bytes than
uniform.

## Decision

The generated specialized adapter is selected. It preserves a synchronous,
direct, statically typed path; makes async and result mapping explicit; avoids
the uniform candidate's intermediate response value on synchronous paths; has
the smaller generated source; and meets both throughput budgets in the target
protocol. The uniform candidate's throughput is equally credible, but its
common discriminator and response allocation add machinery without a current
behavioral requirement.

## Rejected or deferred alternatives

- `Function.apply`, dynamic argument lists, parameter maps, reflection, runtime
  handler registration, and service locators violate the static architecture.
- Forcing all synchronous handlers through a future adds machinery with no
  required behavior.
- A permanent internal response abstraction is deferred unless future features
  need it and its measured cost remains acceptable.
- The request view is not selected merely for abstraction purity.
- Public exception, request, response, controller, middleware, and serialization
  APIs remain out of scope.

ADR 0003 remains Accepted and the generated segmented tree is unchanged. ADR
0002 remains Proposed pending independent native-Linux evidence.
