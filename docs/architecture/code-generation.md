# Production code generation

Phase 2A turns the private contracts selected by ADRs 0003 through 0006 into
the first production generator. Source remains high-level while request
execution is static and small.

## Tooling choice

Oche uses `build_runner` 2.16, `package:build` 4.0, and the analyzer 14.1
semantic element model on Dart 3.13. The builder asks the build resolver for a
fully resolved library, follows controller `Type` constants from the explicit
application root, validates the graph, and emits Dart. It does not parse Dart
text itself.

`package:build` is used directly rather than wrapping the generator in
`source_gen`. Oche needs whole-application conflict validation and full control
of a standalone output library; the thinner builder interface provides those
properties without another generation convention. `build_runner` supplies
dependency tracking, deterministic build orchestration, watch mode, and the
normal incremental workflow.

The versions above are workspace constraints and lockfile observations, not a
promise that all future Oche releases will pin them.

## Explicit graph analysis

Generation starts only at a class annotated with `@OcheApplication`. Its
constant `controllers` list is the complete discovery boundary. For each type,
the analyzer supplies its resolved class, annotation values, constructors,
methods, parameter types, return types, and source library URI.

The generator rejects:

- a non-controller or duplicate controller entry;
- a controller without an unnamed zero-argument-callable constructor;
- multiple application roots in one library;
- malformed paths or placeholder/binding disagreement;
- duplicate route method and normalized shape;
- unsupported parameter and return types;
- static, private, or multiply annotated route methods.

No application assembly happens at runtime. Controllers are imported by their
resolved library URI and stored in generated static final fields. The generated
bootstrap evaluates those fields before binding the server, so each controller
is constructed once before requests are accepted.

## Output strategy

For an input such as `lib/application.dart`, the builder writes the standalone
library `lib/application.oche.dart` into the source tree. The unique `.oche.dart`
suffix avoids the shared `.g.dart` part convention and makes output directly
importable and inspectable. Files without an application root produce no
output.

The generated library imports `package:oche/oche_generated.dart`, a narrow
generator-facing library not reexported from `package:oche/oche.dart`. User
projects therefore depend only on `oche`; Oche's internal package topology is
not exposed in their `pubspec` or public imports.

Output order is deterministic: controllers retain explicit declaration-list
order, segment lengths and literals are sorted, and HTTP methods follow GET,
POST, PUT, PATCH, DELETE order. Generated text is formatted with the Dart
formatter before it is written.

## Mapping to the accepted kernels

The emitter maps each application to the existing architecture:

1. ADR 0003: switch on exact segment count, then literal segments before the
   single parameter branch; full paths are required and 404/405 remain
   distinct.
2. ADR 0004: parse parameters into typed locals and call a statically known
   controller method directly; sync values stay sync and each future result
   shape uses a typed helper.
3. ADR 0005: Phase 2A emits the valid depth-zero pipeline identity. There is no
   public middleware syntax and no per-request closure/list machinery.
4. ADR 0006: the runtime attaches one ownership controller per accepted
   request, writes framework-owned values once, observes `response.done`, maps
   failures before commitment, and drains active responses on shutdown.

A representative leaf is:

```dart
case 'GET':
  final path0 = int.tryParse(segments[1]);
  if (path0 == null) {
    oche_runtime.writeInvalidParameter(request, 'id');
    return;
  }
  final result = _controller1.find(path0);
  oche_runtime.writeString(request, result);
  return;
```

There is no handler table, route descriptor lookup, parameter map,
`Function.apply`, reflection, or controller discovery in this path.

## Bootstrap alternatives

Phase 2A selects `ApplicationOche.run()` because it names a generated symbol
that the compiler can resolve directly. `Oche.run<Application>()` was rejected:
making the generic type locate a generated graph would require a registry,
runtime discovery, or additional manual wiring. A generated top-level `run`
function would be equally static but less clearly namespaced when a library
contains other generated APIs.

## Validation and limits

Builder tests normalize expectations around architectural tokens rather than
goldening every whitespace character. Invalid source fixtures exercise all
required diagnostics. A process-level HTTP test imports the real generated
example and checks success, typed binding, literal precedence, 400, 404, 405
with deterministic `Allow`, 204, bytes, and sync/async failure mapping.

## Windows AOT evidence

The Phase 2A public example was generated, compiled, and measured on native
Windows build 26200, an Intel Xeon E5-2680 v4, Dart 3.13.1, and `oha`
1.16.0. Each primary group used a five-second warmup, 30-second measurement,
five repetitions, and a two-second cooldown. All requests succeeded.

| Workload | Concurrency | Requests/s | p99 (ms) | Idle RSS (MiB) | Peak RSS (MiB) | Startup (ms) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| sync `int` | 10 | 5,248.85 | 2.794 | 14.54 | 18.84 | 317.98 |
| sync `int` | 100 | 5,267.04 | 26.641 | 14.54 | 55.42 | 317.77 |
| sync `int` | 500 | 5,075.24 | 154.535 | 14.53 | 84.53 | 328.96 |
| async `int` | 10 | 5,539.93 | 2.658 | 14.53 | 18.88 | 319.41 |
| async `int` | 100 | 5,534.30 | 22.789 | 14.53 | 55.42 | 319.26 |
| async `int` | 500 | 5,202.64 | 152.298 | 14.54 | 84.88 | 318.94 |

The c500 groups and the borderline sync/c100 group were then repeated against
the current Phase 1E and raw binaries in one balanced, interleaved run. It used
ten repetitions and the same warmup, measurement, and cooldown. The retention
metric is the median of the ten same-iteration throughput ratios, which keeps
each public observation paired with references measured in the same rotation:

| Workload | Concurrency | Public requests/s | Phase 1E requests/s | Raw requests/s | Phase 1E retention | Raw retention |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| sync `int` | 100 | 4,960.97 | 5,203.10 | 4,964.44 | 98.95% | 100.43% |
| sync `int` | 500 | 5,471.98 | 5,356.85 | 5,460.40 | 102.20% | 102.61% |
| async `int` | 500 | 5,657.68 | 5,607.48 | 5,809.79 | 99.35% | 98.81% |

The separately aggregated medians for sync/c100 give a noisier 95.35% ratio
to Phase 1E; its paired median is 98.95%, while both public and raw group
medians are essentially equal. The result is retained here rather than hidden.
Using the focused paired values for suspect groups and primary values for the
others, public throughput retains 98.67% to 102.24% of Phase 1E and 96.18% to
102.61% of raw, satisfying both budgets.

The example generates 6,803 bytes/206 lines, compiles to a 6,510,080-byte
(6.208 MiB) executable, and took 3,089 ms to compile to AOT in the recorded
build. Its binary is 108,544 bytes (1.64%) smaller than the Phase 1E benchmark
binary. Source-size and binary comparisons are directional only: the public
example has 11 annotated routes across seven path templates at depth zero,
while the Phase 1E reference has 100 routes and middleware depth three.

A clean one-shot `build_runner build` took about 44 seconds on this host,
almost entirely compiling the builder snapshot; the actual builder phase was
under one second. Long-lived watch or incremental sessions amortize that
startup cost. Generated output was regenerated from a clean graph with an
identical SHA-256 digest, confirming deterministic output.

Phase 2A does not expose middleware, request inputs beyond path values,
structured JSON, streaming, detached sockets, DI, runtime registration, or
generic response objects. Those omissions keep the first public slice aligned
with the kernels already measured.
