# Oche

> Oche is an experimental compile-time, native-first backend framework for Dart focused on enterprise developer ergonomics with minimal runtime overhead.

Oche is an early experiment, not a production-ready framework. Its first
development phase measures Dart's server-side performance baseline before any
high-level framework API or runtime architecture is selected.

Phase 0.5 compares equivalent implementations built on raw `dart:io`, Relic,
and a deliberately narrow static-routing spike over `dart:io`. It includes
endpoint contract tests, AOT build commands, repeated-result aggregation, route
scaling experiments, and a reproducible benchmark harness. See
[benchmarks/README.md](benchmarks/README.md).

## Repository map

```text
packages/                 Minimal future package boundaries only
benchmarks/raw_dart_io/   Raw dart:io reference server
benchmarks/relic/         Equivalent Relic reference server
benchmarks/oche_static/   Direct static-routing experiment
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
