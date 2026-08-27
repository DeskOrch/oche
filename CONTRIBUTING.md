# Contributing to Oche

Oche is experimental. Phases 0 and 0.5 are intentionally limited to repository
hygiene, architecture records, and objective HTTP/routing performance evidence.
Proposals for high-level framework APIs should wait until the HTTP foundation
work has been reviewed.

## Development setup

Install the stable Dart SDK, then run from the repository root:

```console
dart pub get
dart format --output=none --set-exit-if-changed .
dart analyze
dart test
```

Keep dependencies minimal, avoid runtime reflection and runtime discovery, and
record consequential architectural choices in an ADR. Benchmark changes must
keep workloads equivalent across implementations and must include correctness
tests. Never commit fabricated or placeholder measurements.
