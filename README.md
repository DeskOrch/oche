# Oche

> Oche is an experimental compile-time, native-first backend framework for Dart focused on enterprise developer ergonomics with minimal runtime overhead.

Oche is an early experiment, not a production-ready framework. Its first
development phase measures Dart's server-side performance baseline before any
high-level framework API or runtime architecture is selected.

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

Phase 1C evaluates generated direct middleware composition against a prebuilt
runtime traversal across synchronous, asynchronous, mixed, short-circuit,
error, state, and instance shapes. Its private execution contract and measured
source/AOT trade-offs are documented in
[docs/architecture/middleware-execution.md](docs/architecture/middleware-execution.md).
ADR 0005 remains Proposed because one incremental throughput budget missed and
the deep-chain code-sharing trade-off does not yet have a clear winner.

## Repository map

```text
packages/                 Minimal future package boundaries only
benchmarks/raw_dart_io/   Raw dart:io reference server
benchmarks/relic/         Equivalent Relic reference server
benchmarks/oche_static/   Direct static-routing experiment
benchmarks/routing_kernel/ Generated Phase 1A kernel experiment
benchmarks/handler_execution/ Generated Phase 1B/1C execution experiments
benchmarks/harness/       Process and load-generator harness
docs/architecture/        Architectural principles
docs/adr/                 Architecture decision records
examples/                 Reserved for later phases
tool/                     Repository scripts
```

## Verify the repository

```console
dart pub get
dart analyze
dart test
```

No controllers, dependency injection, ORM, authentication, validation, code
generation, or other application-framework features are implemented yet.
