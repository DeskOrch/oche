# Oche

> Oche is an experimental compile-time, native-first backend framework for Dart focused on enterprise developer ergonomics with minimal runtime overhead.

Oche is experimental pre-alpha software, not a production-ready framework.
Phase 2A introduces its first thin public vertical slice while keeping the
request path compile-time generated.

```dart
import 'package:oche/oche.dart';

@Controller('/users')
final class UserController {
  @Get('/{id}')
  String find(@Path('id') int id) => 'User $id';
}

@OcheApplication(controllers: [UserController])
final class Application {}
```

Generation creates a statically named bootstrap:

```dart
import 'package:my_app/application.oche.dart';

Future<void> main() => ApplicationOche.run();
```

See [Getting started](docs/getting-started.md) and the runnable
[`hello_oche`](examples/hello_oche) application. There is no runtime controller
scan or route registration.

## Architecture evidence

The earlier phases measured Dart's server-side baseline and selected the
private architecture now emitted by the production generator.

Phase 0.6 compares equivalent implementations built on raw `dart:io`, Relic,
and a deliberately narrow static-routing spike over `dart:io`. Its deterministic
balanced scheduler, environment metadata, AOT build commands, repeated-result
aggregation, route-scaling evidence, and Windows/Linux reproduction scripts are
documented in [benchmarks/README.md](benchmarks/README.md). The balanced Windows
results are summarized in
[benchmarks/results/README.md](benchmarks/results/README.md); Linux validation is
still outstanding, so the HTTP-foundation ADR remains Proposed.

Phase 1A adds two internal generated routing-kernel candidates over the same
`dart:io` transport: segmented tree dispatch and guarded hash-assisted dispatch.
The Windows AOT evidence selects segmented tree dispatch for the experimental
kernel; its semantics, source/AOT growth, correctness contract, measured
trade-offs, and benchmark method are documented in
[docs/architecture/routing-kernel.md](docs/architecture/routing-kernel.md).

Phase 1B evaluates the internal boundary between that generated tree and
realistic synchronous/asynchronous handlers. Its generated specialized and
uniform candidates, typed binding, result/error semantics, controller-instance
calls, and reproducible AOT method are documented in
[docs/architecture/handler-execution.md](docs/architecture/handler-execution.md).

Phases 1C and 1D compare generated direct composition, immutable runtime
traversal, and a shared closure-free middleware kernel across synchronous,
asynchronous, mixed, short-circuit, error, state, and instance shapes. ADR 0005
accepts the shared kernel: it preserves direct typed handler calls and
generated-like execution cost while materially reducing source and AOT growth.
The private contract and evidence are documented in
[docs/architecture/middleware-execution.md](docs/architecture/middleware-execution.md).

Phase 1E defines the internal response ownership, commit/completion, streaming,
disconnect, startup, and graceful-shutdown contract without introducing a
public framework API. ADR 0006 accepts the contract after correctness and
limited Windows AOT validation. Details are in
[docs/architecture/response-lifecycle.md](docs/architecture/response-lifecycle.md).

Phase 2A promotes those contracts into the explicit `@OcheApplication` and
`@Controller` model. The production `build_runner` pipeline emits an
inspectable `.oche.dart` segmented tree with typed direct calls and specialized
sync/async response adapters. Its design and constraints are documented in
[docs/architecture/code-generation.md](docs/architecture/code-generation.md).

## Repository map

```text
packages/oche/            Public annotations and generated-runtime bridge
packages/oche_core/       Internal production dart:io runtime
packages/oche_codegen/    Analyzer-backed production builder
benchmarks/raw_dart_io/   Raw dart:io reference server
benchmarks/relic/         Equivalent Relic reference server
benchmarks/oche_static/   Direct static-routing experiment
benchmarks/routing_kernel/ Generated Phase 1A kernel experiment
benchmarks/handler_execution/ Generated Phase 1B/1C/1D/1E runtime experiments
benchmarks/harness/       Process and load-generator harness
docs/architecture/        Architectural principles
docs/adr/                 Architecture decision records
examples/hello_oche/      First generated public Oche application
tool/                     Repository scripts
```

## Verify the repository

```console
dart pub get
cd examples/hello_oche
dart run build_runner build
cd ../..
dart analyze
dart test
```

Phase 2A intentionally has no dependency injection, request-body/query/header
binding, structured JSON mapping, authentication, validation, public
middleware, streaming API, ORM, OpenAPI, or runtime registration. The next
reviewed phase may focus on request inputs and structured JSON; this phase does
not implement them.
